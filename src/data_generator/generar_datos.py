"""Generador de datos historicos SUCIOS para el pipeline batch.

Inserta filas deliberadamente erroneas en oltp.accidentes:
 - nombres de ciudad / avenida inconsistentes (mayus/minus, acentos, alias)
 - fechas en formatos mezclados
 - numeros como texto, nulos, vacios
 - valores absurdos (ej. 30 vehiculos en un choque)
 - responsables nulos / vacios

Lee la contrasena del RDS desde AWS Secrets Manager (por nombre del secreto),
o desde la variable de entorno PGPASSWORD si se prefiere.

Uso:
    python generar_datos.py --rows 500 \
        --secret-name <nombre_secreto> --region us-east-1

    # o con conexion manual:
    python generar_datos.py --rows 500 \
        --host <endpoint> --dbname trafico --user trafico_admin
        (toma la password de $PGPASSWORD)
"""
import argparse
import json
import os
import random
import sys
from datetime import datetime, timedelta

import dominio as D

try:
    import psycopg2
    from psycopg2.extras import execute_values
except ImportError:
    sys.exit("Falta psycopg2. Ejecuta: pip install psycopg2-binary")


def get_conn_params(args):
    """Resuelve host/puerto/credenciales: desde Secrets Manager o flags+env."""
    if args.secret_name:
        import boto3
        sm = boto3.client("secretsmanager", region_name=args.region)
        sec = json.loads(sm.get_secret_value(SecretId=args.secret_name)["SecretString"])
        return dict(
            host=sec["host"], port=int(sec["port"]), dbname=sec["dbname"],
            user=sec["username"], password=sec["password"],
        )
    pwd = os.environ.get("PGPASSWORD")
    if not pwd:
        sys.exit("Define $PGPASSWORD o usa --secret-name.")
    return dict(host=args.host, port=args.port, dbname=args.dbname,
                user=args.user, password=pwd)


def fecha_sucia():
    base = datetime(2020, 1, 1) + timedelta(days=random.randint(0, 2000))
    fmt = random.choice([
        "%Y-%m-%d", "%d/%m/%Y", "%m-%d-%Y", "%Y/%m/%d %H:%M",
        "%d-%b-%Y",
    ])
    val = base.strftime(fmt)
    # a veces fecha corrupta
    if random.random() < 0.05:
        val = random.choice(["32/13/2021", "sin fecha", "", None])
    return val


def vehiculos_sucio():
    r = random.random()
    if r < 0.08:
        return str(random.randint(15, 40))      # absurdo (ej. 30 carros)
    if r < 0.13:
        return random.choice([None, "", "varios", "N/A"])
    if r < 0.18:
        return "0"                               # tambien invalido
    return str(random.randint(1, 6))


def heridos_sucio():
    r = random.random()
    if r < 0.1:
        return random.choice([None, "", "muchos", "-2"])
    return str(random.randint(0, 8))


def coord_sucia(base, spread):
    r = random.random()
    if r < 0.08:
        return random.choice([None, "", "NaN"])
    return f"{base + random.uniform(-spread, spread):.5f}"


def build_rows(n):
    rows = []
    for _ in range(n):
        rows.append((
            fecha_sucia(),
            random.choice(D.CIUDADES_SUCIAS),
            random.choice(D.AVENIDAS_SUCIAS),
            vehiculos_sucio(),
            heridos_sucio(),
            random.choice(D.RESPONSABLES),
            random.choice(D.GRAVEDAD_SUCIA),
            coord_sucia(6.2442, 0.15),   # lat ~ Medellin
            coord_sucia(-75.5812, 0.15), # lon ~ Medellin
        ))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", type=int, default=500)
    ap.add_argument("--secret-name")
    ap.add_argument("--region", default=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"))
    ap.add_argument("--host")
    ap.add_argument("--port", type=int, default=5432)
    ap.add_argument("--dbname", default="trafico")
    ap.add_argument("--user", default="trafico_admin")
    args = ap.parse_args()

    params = get_conn_params(args)
    rows = build_rows(args.rows)

    sql = """
        INSERT INTO oltp.accidentes
            (fecha_raw, ciudad_raw, avenida_raw, vehiculos_raw, heridos_raw,
             responsable, gravedad_raw, lat_raw, lon_raw)
        VALUES %s
    """
    conn = psycopg2.connect(**params)
    conn.autocommit = True
    with conn.cursor() as cur:
        execute_values(cur, sql, rows)
        cur.execute("SELECT count(*) FROM oltp.accidentes;")
        total = cur.fetchone()[0]
    conn.close()
    print(f"Insertadas {len(rows)} filas sucias. Total en oltp.accidentes: {total}")


if __name__ == "__main__":
    main()
