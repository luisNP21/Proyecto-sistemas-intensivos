"""Consulta rapida del estado de la base de datos (schemas y conteos)."""
import json
import os
import sys

import boto3
import psycopg2

SECRET = os.environ.get("DB_SECRET_NAME", "trafico-valle-db-20261117034556241200000003")
REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")

def fail(msg):
    with open("terraform/_dbresult.txt", "w", encoding="utf-8") as f:
        f.write("ERROR: " + msg)
    print("ERROR:", msg)
    sys.exit(1)

try:
    sm = boto3.client("secretsmanager", region_name=REGION)
    s = json.loads(sm.get_secret_value(SecretId=SECRET)["SecretString"])
except Exception as e:
    fail(f"secretsmanager: {e}")

try:
    conn = psycopg2.connect(host=s["host"], port=int(s["port"]), dbname=s["dbname"],
                            user=s["username"], password=s["password"], connect_timeout=15,
                            sslmode="require")
except Exception as e:
    fail(f"connect RDS {s.get('host')}: {e}")
conn.autocommit = True
out = []
with conn.cursor() as cur:
    cur.execute("SELECT nspname FROM pg_namespace WHERE nspname IN ('oltp','analytics') ORDER BY 1;")
    out.append("schemas: " + ", ".join(r[0] for r in cur.fetchall()))
    for tbl in ["oltp.accidentes", "analytics.accidentes_agg", "analytics.lecturas_trafico"]:
        try:
            cur.execute(f"SELECT count(*) FROM {tbl};")
            out.append(f"{tbl}: {cur.fetchone()[0]} filas")
        except Exception as e:
            out.append(f"{tbl}: ERROR {e}")
    # muestra algunas filas de lecturas si hay
    try:
        cur.execute("SELECT ventana_inicio, ciudad, avenida, velocidad_prom, estado FROM analytics.lecturas_trafico ORDER BY ventana_inicio DESC LIMIT 5;")
        rows = cur.fetchall()
        if rows:
            out.append("ultimas lecturas_trafico:")
            for r in rows:
                out.append(f"  {r}")
    except Exception:
        pass
conn.close()
result = "\n".join(out)
print(result)
with open("terraform/_dbresult.txt", "w", encoding="utf-8") as f:
    f.write(result)
