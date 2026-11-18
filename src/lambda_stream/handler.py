"""Lambda de streaming "solo mueve datos".

Disparada por SQS (event source mapping). Toma el lote de mensajes, valida cada
lectura y escribe:
  - validas  -> landing/dt=YYYY-MM-DD/HH/<uuid>.json  (una lectura por linea, JSONL)
  - invalidas -> failed/dt=YYYY-MM-DD/HH/<uuid>.json

No transforma: solo normaliza minimamente y separa validas de invalidas, para que
EMR Serverless lea los archivos de landing/.

Formato esperado de cada mensaje (JSON publicado por el sensor):
  { "sensor_id": "s-av80-01", "ciudad": "Medellin", "avenida": "Av 80",
    "velocidad_kmh": 0.0, "ts": "2026-11-16T10:00:00Z" }

Variables de entorno:
  DATA_BUCKET   bucket S3 de datos
"""
import json
import os
import uuid
from datetime import datetime, timezone

import boto3

DATA_BUCKET = os.environ["DATA_BUCKET"]
_s3 = boto3.client("s3")

CAMPOS = {"sensor_id", "ciudad", "avenida", "velocidad_kmh", "ts"}


def _valida(msg: dict):
    if not CAMPOS.issubset(msg.keys()):
        return False, "campos_faltantes"
    v = msg.get("velocidad_kmh")
    if not isinstance(v, (int, float)):
        return False, "velocidad_no_numerica"
    if v < 0 or v > 200:
        return False, "velocidad_fuera_de_rango"
    if not str(msg.get("avenida", "")).strip():
        return False, "avenida_vacia"
    return True, None


def _put_jsonl(prefix, registros):
    if not registros:
        return None
    now = datetime.now(timezone.utc)
    # Prefijo PLANO (sin dt=/HH/): si se usan subcarpetas tipo "dt=...", Spark
    # Structured Streaming las interpreta como columnas de particion y rompe el
    # esquema. El timestamp va en el nombre del archivo, no en el path.
    key = f"{prefix}{now:%Y%m%dT%H%M%S}-{uuid.uuid4().hex}.json"
    body = "\n".join(json.dumps(r, ensure_ascii=False) for r in registros)
    _s3.put_object(Bucket=DATA_BUCKET, Key=key, Body=body.encode("utf-8"))
    return key


def handler(event, context):
    validas, invalidas = [], []
    for record in event.get("Records", []):
        raw = record.get("body", "")
        try:
            msg = json.loads(raw)
        except (ValueError, TypeError):
            invalidas.append({"body": raw, "motivo": "json_invalido"})
            continue
        ok, motivo = _valida(msg)
        if ok:
            validas.append(msg)
        else:
            invalidas.append({"mensaje": msg, "motivo": motivo})

    k_ok = _put_jsonl("landing/", validas)
    k_bad = _put_jsonl("failed/", invalidas)

    out = {"validas": len(validas), "invalidas": len(invalidas),
           "landing_key": k_ok, "failed_key": k_bad}
    print(json.dumps(out))
    return out
