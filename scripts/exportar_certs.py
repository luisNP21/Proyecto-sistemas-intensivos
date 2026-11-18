"""Exporta el certificado y la clave privada del dispositivo IoT desde los
outputs de Terraform a la carpeta certs/, y descarga la Amazon Root CA.

Debe ejecutarse desde la carpeta terraform/ o pasandole --tf-dir.

Uso:
  python ../scripts/exportar_certs.py            # desde terraform/
  python scripts/exportar_certs.py --tf-dir terraform
"""
import argparse
import json
import os
import subprocess
import sys
import urllib.request

ROOT_CA_URL = "https://www.amazontrust.com/repository/AmazonRootCA1.pem"


def tf_output(tf_dir, name):
    out = subprocess.check_output(
        ["terraform", f"-chdir={tf_dir}", "output", "-raw", name],
        text=True,
    )
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tf-dir", default=".")
    ap.add_argument("--out-dir", default=None)
    args = ap.parse_args()

    out_dir = args.out_dir or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "simulator", "certs")
    os.makedirs(out_dir, exist_ok=True)

    try:
        cert = tf_output(args.tf_dir, "iot_certificate_pem")
        key = tf_output(args.tf_dir, "iot_private_key")
        endpoint = tf_output(args.tf_dir, "iot_endpoint")
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        sys.exit(f"No se pudieron leer los outputs de Terraform: {e}\n"
                 f"Asegurate de haber ejecutado 'terraform apply' y de que 'terraform' este en el PATH.")

    with open(os.path.join(out_dir, "device.pem.crt"), "w", encoding="utf-8") as f:
        f.write(cert)
    with open(os.path.join(out_dir, "private.pem.key"), "w", encoding="utf-8") as f:
        f.write(key)

    ca_path = os.path.join(out_dir, "AmazonRootCA1.pem")
    urllib.request.urlretrieve(ROOT_CA_URL, ca_path)

    print("Certificados exportados a:", out_dir)
    print("Endpoint IoT:", endpoint)
    print("\nEjemplo para correr el simulador:")
    print(f'  python src/simulator/simulador.py --endpoint {endpoint} '
          f'--cert {os.path.join(out_dir, "device.pem.crt")} '
          f'--key {os.path.join(out_dir, "private.pem.key")} '
          f'--root-ca {ca_path} --topic trafico/lecturas')


if __name__ == "__main__":
    main()
