"""Simulador de sensores IoT de trafico (MQTT sobre mTLS a AWS IoT Core).

Publica lecturas de velocidad promedio por avenida. Modela tres estados:
  - choque           -> velocidad ~ 0 km/h
  - choque_cercano   -> velocidad ~ 10 km/h
  - sin_incidente    -> velocidad normal (30-80 km/h)

Credenciales/certs: se obtienen de los outputs de Terraform. Usa el script
scripts/exportar_certs.py (o el README) para volcarlos a la carpeta certs/.

Requisitos:
  pip install awsiotsdk
  (ver requirements.txt)

Uso:
  python simulador.py \
    --endpoint <IOT_ENDPOINT> \
    --cert certs/device.pem.crt \
    --key  certs/private.pem.key \
    --root-ca certs/AmazonRootCA1.pem \
    --topic trafico/lecturas \
    --intervalo 2 \
    --prob-choque 0.08
"""
import argparse
import json
import random
import sys
import time
from datetime import datetime, timezone

try:
    from awscrt import mqtt
    from awsiot import mqtt_connection_builder
except ImportError:
    sys.exit("Falta awsiotsdk. Ejecuta: pip install awsiotsdk")

CIUDAD_AVENIDAS = {
    "Medellin":    ["Av Regional", "Av Las Vegas", "Av El Poblado", "Av 80", "Av San Juan", "Av Oriental", "Av Guayabal", "Av 33"],
    "Bello":       ["Av Regional", "Av 80"],
    "Envigado":    ["Av Las Vegas", "Av El Poblado"],
    "Sabaneta":    ["Av Las Vegas"],
    "La Estrella": ["Av Regional"],
    "Caldas":      ["Av Regional"],
}


def _sensores():
    out = []
    for ciudad, avenidas in CIUDAD_AVENIDAS.items():
        for av in avenidas:
            sid = "s-" + (ciudad[:3] + "-" + av.replace("Av ", "").replace(" ", "")).lower()
            out.append((sid, ciudad, av))
    return out


def velocidad(prob_choque):
    r = random.random()
    if r < prob_choque:
        return round(random.uniform(0.0, 0.5), 1)        # choque
    if r < prob_choque + 0.10:
        return round(random.uniform(8.0, 12.0), 1)       # choque cercano
    return round(random.uniform(30.0, 80.0), 1)          # normal


def build_connection(args):
    return mqtt_connection_builder.mtls_from_path(
        endpoint=args.endpoint,
        cert_filepath=args.cert,
        pri_key_filepath=args.key,
        ca_filepath=args.root_ca,
        client_id=args.client_id,
        clean_session=False,
        keep_alive_secs=30,
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", required=True)
    ap.add_argument("--cert", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--root-ca", required=True)
    ap.add_argument("--topic", default="trafico/lecturas")
    ap.add_argument("--client-id", default="sim-trafico-" + str(random.randint(1000, 9999)))
    ap.add_argument("--intervalo", type=float, default=2.0)
    ap.add_argument("--prob-choque", type=float, default=0.08)
    ap.add_argument("--max-mensajes", type=int, default=0, help="0 = infinito")
    args = ap.parse_args()

    sensores = _sensores()
    conn = build_connection(args)
    print("Conectando a", args.endpoint, "...")
    conn.connect().result()
    print("Conectado. Publicando en", args.topic)

    enviados = 0
    try:
        while True:
            sid, ciudad, avenida = random.choice(sensores)
            msg = {
                "sensor_id": sid,
                "ciudad": ciudad,
                "avenida": avenida,
                "velocidad_kmh": velocidad(args.prob_choque),
                "ts": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            }
            conn.publish(topic=args.topic, payload=json.dumps(msg),
                         qos=mqtt.QoS.AT_LEAST_ONCE)
            enviados += 1
            print(f"[{enviados}] {msg['avenida']} {ciudad}: {msg['velocidad_kmh']} km/h")
            if args.max_mensajes and enviados >= args.max_mensajes:
                break
            time.sleep(args.intervalo)
    except KeyboardInterrupt:
        print("\nDetenido por el usuario.")
    finally:
        conn.disconnect().result()
        print(f"Desconectado. Total enviados: {enviados}")


if __name__ == "__main__":
    main()
