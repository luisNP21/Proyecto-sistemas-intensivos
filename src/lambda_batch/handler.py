"""Lambda ProcesarHistorico (batch, Pandas/PyArrow).

Flujo:
  1. Lee incrementalmente oltp.accidentes (id > watermark) via psycopg2.
  2. Limpia/valida/normaliza con limpieza.py.
  3. Escribe Parquet:
        curated/anio=YYYY/mes=MM/*.parquet   (validas)
        failed/anio=YYYY/mes=MM/*.parquet     (rechazadas, con motivo)
  4. Agrega validas por (ciudad, avenida, anio, mes) -> analytics.accidentes_agg (UPSERT).
  5. Avanza la watermark.
  6. Publica la metrica 'Errors' (nro de rechazadas) a CloudWatch.

Variables de entorno:
  SECRET_NAME   nombre del secreto en Secrets Manager con las credenciales RDS
  DATA_BUCKET   bucket S3 de datos
  METRIC_NS     namespace de CloudWatch (default: Trafico/Batch)
  BATCH_SIZE    maximo de filas por invocacion (default 5000)
"""
import io
import json
import os
import uuid
from datetime import datetime, timezone

import boto3
import pandas as pd
import psycopg2
from psycopg2.extras import RealDictCursor, execute_values

import limpieza

SECRET_NAME = os.environ["SECRET_NAME"]
DATA_BUCKET = os.environ["DATA_BUCKET"]
METRIC_NS = os.environ.get("METRIC_NS", "Trafico/Batch")
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "5000"))

_s3 = boto3.client("s3")
_cw = boto3.client("cloudwatch")
_sm = boto3.client("secretsmanager")


def _db_params():
    sec = json.loads(_sm.get_secret_value(SecretId=SECRET_NAME)["SecretString"])
    return dict(host=sec["host"], port=int(sec["port"]), dbname=sec["dbname"],
                user=sec["username"], password=sec["password"], connect_timeout=15)


def _df_to_parquet_bytes(df: pd.DataFrame) -> bytes:
    """Serializa un DataFrame a Parquet. fastparquet cierra el buffer, asi que
    se escribe a un archivo temporal en /tmp y se leen los bytes."""
    tmp = os.path.join("/tmp", f"{uuid.uuid4().hex}.parquet")
    try:
        df.to_parquet(tmp, engine="fastparquet", index=False)
        with open(tmp, "rb") as f:
            return f.read()
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def _put_parquet(df: pd.DataFrame, prefix: str):
    """Escribe un DataFrame como Parquet particionado por anio/mes."""
    if df.empty:
        return 0
    written = 0
    for (anio, mes), part in df.groupby(["anio", "mes"]):
        key = f"{prefix}anio={int(anio)}/mes={int(mes):02d}/{uuid.uuid4().hex}.parquet"
        _s3.put_object(Bucket=DATA_BUCKET, Key=key, Body=_df_to_parquet_bytes(part))
        written += len(part)
    return written


def _upsert_agg(conn, df: pd.DataFrame):
    if df.empty:
        return
    agg = (df.groupby(["ciudad", "avenida", "anio", "mes"])
             .agg(total_accidentes=("id", "count"),
                  total_heridos=("heridos", "sum"),
                  total_vehiculos=("vehiculos", "sum"))
             .reset_index())
    rows = [
        (r.ciudad, r.avenida, int(r.anio), int(r.mes),
         int(r.total_accidentes), int(r.total_heridos), int(r.total_vehiculos))
        for r in agg.itertuples()
    ]
    sql = """
        INSERT INTO analytics.accidentes_agg
            (ciudad, avenida, anio, mes, total_accidentes, total_heridos, total_vehiculos)
        VALUES %s
        ON CONFLICT (ciudad, avenida, anio, mes) DO UPDATE SET
            total_accidentes = analytics.accidentes_agg.total_accidentes + EXCLUDED.total_accidentes,
            total_heridos    = analytics.accidentes_agg.total_heridos + EXCLUDED.total_heridos,
            total_vehiculos  = analytics.accidentes_agg.total_vehiculos + EXCLUDED.total_vehiculos,
            actualizado      = now();
    """
    with conn.cursor() as cur:
        execute_values(cur, sql, rows)


def handler(event, context):
    conn = psycopg2.connect(**_db_params())
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT last_id FROM oltp.ingest_watermark WHERE pipeline='procesar_historico' FOR UPDATE;")
            last_id = cur.fetchone()[0]

        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT * FROM oltp.accidentes WHERE id > %s ORDER BY id ASC LIMIT %s;",
                (last_id, BATCH_SIZE),
            )
            raw = cur.fetchall()

        validas, rechazadas = [], []
        for row in raw:
            limpia, motivo = limpieza.limpiar_fila(dict(row))
            if motivo:
                rechazadas.append({"id": row["id"], "motivo": motivo,
                                   "ciudad_raw": row.get("ciudad_raw"),
                                   "avenida_raw": row.get("avenida_raw"),
                                   "fecha_raw": row.get("fecha_raw"),
                                   "vehiculos_raw": row.get("vehiculos_raw")})
            else:
                validas.append(limpia)

        df_ok = pd.DataFrame(validas)
        df_bad = pd.DataFrame(rechazadas)

        # Particion por anio/mes solo aplica a validas; rechazadas van a un prefijo por fecha de proceso.
        n_ok = _put_parquet(df_ok, "curated/") if not df_ok.empty else 0
        if not df_bad.empty:
            today = datetime.now(timezone.utc)
            key = f"failed/dt={today:%Y-%m-%d}/{uuid.uuid4().hex}.parquet"
            _s3.put_object(Bucket=DATA_BUCKET, Key=key, Body=_df_to_parquet_bytes(df_bad))

        if not df_ok.empty:
            _upsert_agg(conn, df_ok)

        new_last = max([r["id"] for r in raw], default=last_id)
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE oltp.ingest_watermark SET last_id=%s, actualizado=now() WHERE pipeline='procesar_historico';",
                (new_last,),
            )
        conn.commit()

        # Metrica Errors (rechazadas) a CloudWatch.
        _cw.put_metric_data(
            Namespace=METRIC_NS,
            MetricData=[{
                "MetricName": "Errors",
                "Value": float(len(rechazadas)),
                "Unit": "Count",
                "Timestamp": datetime.now(timezone.utc),
            }],
        )

        result = {
            "leidas": len(raw),
            "validas": n_ok,
            "rechazadas": len(rechazadas),
            "watermark_anterior": last_id,
            "watermark_nueva": new_last,
        }
        print(json.dumps(result))
        return result
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
