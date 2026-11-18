"""EMR Serverless - Spark Structured Streaming (file-based).

Lee micro-lotes JSONL que la Lambda escribe en s3://<data>/landing/, agrega la
velocidad promedio por avenida en ventanas de 1 minuto, clasifica el estado y
escribe los agregados a analytics.lecturas_trafico en RDS via JDBC.

Clasificacion por velocidad promedio de la ventana:
  <= 2 km/h   -> 'choque'
  <= 15 km/h  -> 'choque_cercano'
  en otro caso -> 'sin_incidente'

Las filas que no cumplen el esquema (velocidad nula/corrupta) se desvian a
s3://<data>/failed/streaming/ via foreachBatch.

Argumentos (todos requeridos):
  --data-bucket   nombre del bucket de datos
  --secret-name   nombre del secreto en Secrets Manager con credenciales RDS
  --region        region AWS
"""
import argparse
import json

import boto3
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import (DoubleType, StringType, StructField, StructType)


def get_db(secret_name, region):
    sm = boto3.client("secretsmanager", region_name=region)
    s = json.loads(sm.get_secret_value(SecretId=secret_name)["SecretString"])
    jdbc = f"jdbc:postgresql://{s['host']}:{s['port']}/{s['dbname']}"
    return jdbc, s["username"], s["password"]


SCHEMA = StructType([
    StructField("sensor_id", StringType()),
    StructField("ciudad", StringType()),
    StructField("avenida", StringType()),
    StructField("velocidad_kmh", DoubleType()),
    StructField("ts", StringType()),
])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-bucket", required=True)
    ap.add_argument("--secret-name", required=True)
    ap.add_argument("--region", required=True)
    args = ap.parse_args()

    jdbc_url, user, pwd = get_db(args.secret_name, args.region)

    landing = f"s3://{args.data_bucket}/landing/"
    checkpoint = f"s3://{args.data_bucket}/checkpoints/streaming/"
    failed = f"s3://{args.data_bucket}/failed/streaming/"

    spark = (SparkSession.builder
             .appName("trafico-streaming")
             .getOrCreate())
    spark.sparkContext.setLogLevel("WARN")

    # La Lambda escribe los JSON directamente en landing/ con nombre plano
    # (sin subcarpetas dt=/HH/), por lo que Spark no infiere particiones.
    raw = (spark.readStream
           .schema(SCHEMA)
           .option("maxFilesPerTrigger", 50)
           .option("pathGlobFilter", "*.json")
           .json(landing))

    # Marca invalidas (sin velocidad o sin avenida).
    marcado = raw.withColumn(
        "_invalida",
        F.col("velocidad_kmh").isNull() | (F.col("avenida").isNull()) |
        (F.col("velocidad_kmh") < 0) | (F.col("velocidad_kmh") > 200),
    ).withColumn("event_time", F.to_timestamp("ts"))

    validas = marcado.filter(~F.col("_invalida"))
    invalidas = marcado.filter(F.col("_invalida"))

    agregado = (validas
                .withWatermark("event_time", "2 minutes")
                .groupBy(
                    F.window("event_time", "1 minute"),
                    F.col("ciudad"),
                    F.col("avenida"),
                )
                .agg(
                    F.avg("velocidad_kmh").alias("velocidad_prom"),
                    F.count(F.lit(1)).alias("lecturas"),
                )
                .select(
                    F.col("window.start").alias("ventana_inicio"),
                    F.col("window.end").alias("ventana_fin"),
                    F.col("ciudad"),
                    F.col("avenida"),
                    F.round("velocidad_prom", 2).alias("velocidad_prom"),
                    F.col("lecturas"),
                )
                .withColumn(
                    "estado",
                    F.when(F.col("velocidad_prom") <= 2, F.lit("choque"))
                     .when(F.col("velocidad_prom") <= 15, F.lit("choque_cercano"))
                     .otherwise(F.lit("sin_incidente")),
                ))

    def escribir_agg(batch_df, batch_id):
        if batch_df.rdd.isEmpty():
            return
        # UPSERT real: se escribe el micro-lote a una tabla staging por batch y
        # luego se hace INSERT ... ON CONFLICT DO UPDATE contra la tabla final.
        # Esto evita el error de clave duplicada cuando una ventana se re-emite
        # como dato tardio (output mode 'update' + watermark).
        # El UPSERT se ejecuta via el driver JDBC ya cargado (--jars), por el JVM,
        # para no depender de psycopg2 en los workers de EMR Serverless.
        staging = f"analytics._stg_lecturas_{batch_id}"

        # Sin createTableColumnTypes: Spark usa el dialecto PostgreSQL por
        # defecto para crear la tabla staging (StringType->TEXT, etc.).
        (batch_df.write
            .format("jdbc")
            .option("url", jdbc_url)
            .option("dbtable", staging)
            .option("user", user)
            .option("password", pwd)
            .option("driver", "org.postgresql.Driver")
            .mode("overwrite")
            .save())

        jvm = batch_df.sparkSession._jvm
        props = jvm.java.util.Properties()
        props.setProperty("user", user)
        props.setProperty("password", pwd)
        jconn = jvm.java.sql.DriverManager.getConnection(jdbc_url, props)
        try:
            stmt = jconn.createStatement()
            stmt.execute(f"""
                INSERT INTO analytics.lecturas_trafico
                    (ventana_inicio, ventana_fin, ciudad, avenida,
                     velocidad_prom, lecturas, estado)
                SELECT ventana_inicio, ventana_fin, ciudad, avenida,
                       velocidad_prom, lecturas, estado
                FROM {staging}
                ON CONFLICT (ventana_inicio, ciudad, avenida) DO UPDATE SET
                    ventana_fin    = EXCLUDED.ventana_fin,
                    velocidad_prom = EXCLUDED.velocidad_prom,
                    lecturas       = EXCLUDED.lecturas,
                    estado         = EXCLUDED.estado,
                    actualizado    = now();
            """)
            stmt.execute(f"DROP TABLE IF EXISTS {staging};")
            stmt.close()
        finally:
            jconn.close()

    q_agg = (agregado.writeStream
             .outputMode("update")
             .option("checkpointLocation", checkpoint)
             .foreachBatch(escribir_agg)
             .trigger(processingTime="1 minute")
             .start())

    q_bad = (invalidas.select("sensor_id", "ciudad", "avenida", "velocidad_kmh", "ts")
             .writeStream
             .format("json")
             .option("path", failed)
             .option("checkpointLocation", f"s3://{args.data_bucket}/checkpoints/failed/")
             .outputMode("append")
             .start())

    # Si cualquiera de los dos streams falla, el driver termina (no queda colgado).
    spark.streams.awaitAnyTermination()


if __name__ == "__main__":
    main()
