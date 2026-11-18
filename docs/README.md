# Pipeline de datos de tráfico y accidentes — Valle de Aburrá (AWS + Terraform)

Proyecto de ingeniería de datos con dos pipelines desplegados con Terraform:

- **Streaming:** sensores IoT simulados reportan la velocidad promedio por avenida.
  `0 km/h` = choque en la avenida, `~10 km/h` = choque cercano, velocidad normal = sin incidente.
- **Batch:** carga histórica masiva de accidentes con datos sucios que se limpian y validan.

> **IMPORTANTE:** este repositorio NO debe subirse a GitHub. El `.gitignore` protege
> el estado de Terraform, los `*.tfvars`, los certificados y las claves. No ejecutes
> `git push`.

---

## Arquitectura

### Streaming (IoT Core + EMR Serverless)
```
Simulador (mTLS) --MQTT--> IoT Core (Topic Rule) --> SQS LecturasQueue --3 intentos--> LecturasDLQ
                                                        |
                                                        v
                                               Lambda "mueve datos"
                                                        |
                                    landing/ (válidas) / failed/ (inválidas)   [S3]
                                                        |
                                           EMR Serverless (Spark Structured Streaming)
                                                        |
                                           analytics.lecturas_trafico (RDS)
LecturasDLQ --> CloudWatch Alarm --> SNS (email)
```

### Batch (RDS + Lambda Pandas)
```
Script genera datos sucios --INSERT--> oltp.accidentes (RDS)
                                             |
                               Lambda ProcesarHistorico (Pandas/PyArrow)
                                 |                         |
                   curated/ + failed/ (Parquet, S3)   analytics.accidentes_agg (RDS)
                                 |
                       métrica Errors --> CloudWatch Alarm --> SNS (email)
analytics.* --> QuickSight (data source + datasets + dashboard)
```

El `EventBridge` del diagrama original **no se usa** (es una sola ingesta histórica).

---

## Requisitos locales

| Herramienta | Uso |
|-------------|-----|
| Terraform >= 1.6 | desplegar la infraestructura |
| Python 3.12 | construir capas Lambda, generador, simulador, scripts |
| pip | instalar dependencias de las capas (lo invoca Terraform) |
| AWS CLI (opcional) | inspección manual |
| psql (opcional) | verificar la base de datos |
| `psycopg2-binary`, `boto3` | para los scripts locales (`pip install -r src/data_generator/requirements.txt`) |

Terraform y Python deben estar en el `PATH`, porque varios módulos usan
`local-exec` con Python (construcción de capas, DDL, subida del driver JDBC,
lanzamiento del job EMR).

---

## Credenciales AWS (variables de entorno)

El provider lee las credenciales del entorno. En PowerShell:

```powershell
$env:AWS_ACCESS_KEY_ID     = "AKIA..."
$env:AWS_SECRET_ACCESS_KEY = "..."
$env:AWS_DEFAULT_REGION    = "us-east-1"
$env:AWS_DEFAULT_OUTPUT    = "json"   # opcional
```

El estado de Terraform es **local** (`terraform/terraform.tfstate`).

---

## Configuración (`terraform.tfvars`)

```powershell
cd terraform
Copy-Item terraform.tfvars.example terraform.tfvars
```

Edita `terraform.tfvars`:

| Variable | Qué poner |
|----------|-----------|
| `project_name` | prefijo de recursos (minúsculas/guiones), ej. `trafico-valle` |
| `aws_region` | tu región, ej. `us-east-1` |
| `alert_email` | correo para las alarmas SNS |
| `my_ip_cidr` | tu IP pública `/32` → `curl https://checkip.amazonaws.com` |
| `db_name`, `db_username` | nombre/usuario de la BD (la contraseña se autogenera) |
| `quicksight_user_arn` | ARN de tu usuario QuickSight (ver abajo) |
| `quicksight_namespace` | normalmente `default` |
| `enable_quicksight` | `true` para crear el dashboard |
| `enable_emr_streaming` | `true` para crear EMR y lanzar el job |

Obtener el ARN de tu usuario QuickSight:
```powershell
aws quicksight list-users --aws-account-id <ACCOUNT_ID> --namespace default --region <REGION>
# ARN: arn:aws:quicksight:<REGION>:<ACCOUNT_ID>:user/default/<USERNAME>
```

---

## Despliegue

```powershell
cd terraform
terraform init
terraform validate
terraform plan
terraform apply
```

El `apply`:
1. Crea VPC endpoints, SG, Secrets Manager (password autogenerada), RDS y aplica el DDL.
2. Crea buckets S3, la capa Lambda (pandas/pyarrow/psycopg2) y las dos Lambdas.
3. Crea IoT Core (Thing, cert X.509, Topic Rule), SQS + DLQ.
4. Crea la app EMR Serverless, sube el script Spark + driver JDBC y lanza el job de streaming.
5. Crea SNS + alarmas y los recursos de QuickSight.

### Pasos manuales documentados (no automatizables)
- **Confirmar el email de SNS:** AWS envía un correo a `alert_email`; haz clic en *Confirm subscription*.
- **QuickSight:** debe estar ya activo en la cuenta (lo está, por un proyecto previo).

---

## Ejecutar el pipeline BATCH

1. Genera datos históricos sucios en `oltp.accidentes`:
   ```powershell
   pip install -r src/data_generator/requirements.txt
   python src/data_generator/generar_datos.py `
     --rows 500 `
     --secret-name (terraform -chdir=terraform output -raw db_secret_name) `
     --region us-east-1
   ```
2. Invoca la Lambda de limpieza:
   ```powershell
   aws lambda invoke --function-name (terraform -chdir=terraform output -raw lambda_batch_name) `
     --region us-east-1 out.json ; Get-Content out.json
   ```
3. Verifica:
   - Parquet en `s3://<data_bucket>/curated/...` y `.../failed/...`
   - Filas en `analytics.accidentes_agg`
   - Métrica `Errors` en CloudWatch (namespace `Trafico/Batch`)

> La Lambda es incremental (usa `oltp.ingest_watermark`): invócala de nuevo tras
> generar más filas y solo procesa las nuevas.

---

## Ejecutar el pipeline STREAMING

1. Exporta el certificado/clave del dispositivo y la Root CA:
   ```powershell
   pip install -r src/simulator/requirements.txt
   python scripts/exportar_certs.py --tf-dir terraform
   ```
   Esto escribe `src/simulator/certs/` (ignorado por git).
2. Corre el simulador (usa el endpoint que imprime el script anterior):
   ```powershell
   python src/simulator/simulador.py `
     --endpoint <IOT_ENDPOINT> `
     --cert src/simulator/certs/device.pem.crt `
     --key  src/simulator/certs/private.pem.key `
     --root-ca src/simulator/certs/AmazonRootCA1.pem `
     --topic trafico/lecturas --intervalo 2 --prob-choque 0.08
   ```
3. Verifica:
   - Mensajes consumidos de `LecturasQueue` y JSONL apareciendo en `s3://<data_bucket>/landing/`.
   - En ~1 min, filas agregadas en `analytics.lecturas_trafico` (una avenida con 0 km/h aparece como `choque`).
   - Mensajes mal formados caen en la DLQ → llega correo de alerta.

---

## Verificar la base de datos

```powershell
$h = terraform -chdir=terraform output -raw rds_endpoint
# contraseña desde Secrets Manager:
aws secretsmanager get-secret-value --secret-id (terraform -chdir=terraform output -raw db_secret_name) --query SecretString --output text
psql "host=$h port=5432 dbname=trafico user=trafico_admin sslmode=require"
# \dn  -> schemas oltp y analytics
# SELECT count(*) FROM oltp.accidentes;
# SELECT * FROM analytics.lecturas_trafico ORDER BY ventana_inicio DESC LIMIT 20;
```

---

## QuickSight

Tras el `apply`, abre la URL del dashboard:
```powershell
terraform -chdir=terraform output -raw quicksight_dashboard_url
```
Hoja *Streaming tiempo real* (avenidas por estado) y *Histórico accidentes*
(accidentes por ciudad). Los datasets son DIRECT_QUERY sobre `analytics`.

---

## Destruir (reproducibilidad)

```powershell
cd terraform
terraform destroy
```
Todo es destruible sin pasos manuales:
- Buckets con `force_destroy = true`.
- Secret con `recovery_window_in_days = 0`.
- RDS con `skip_final_snapshot = true` y `deletion_protection = false`.

Para re-desplegar de cero: `terraform apply` otra vez. La password del RDS se
regenera; `exportar_certs.py` vuelve a volcar el nuevo certificado.

> Si quieres parar solo el gasto de EMR sin destruir todo, pon
> `enable_emr_streaming = false` y `terraform apply` (detiene/elimina la app EMR).

---

## Reglas de limpieza del batch (resumen)

Implementadas en `src/lambda_batch/limpieza.py`:
- **ciudad / avenida:** normalización contra un mapa de alias → nombre canónico;
  si no se reconoce, se **rechaza**.
- **fecha:** se prueban varios formatos; si falla, se **rechaza**.
- **vehículos:** entero entre 1 y 10; fuera de rango o no numérico (ej. "30", "0", "varios") → **rechazo**.
- **heridos:** entero 0–20; valor inválido se corrige a 0 (no rechaza).
- **responsable:** nulo/vacío permitido → `DESCONOCIDO`.
- **gravedad:** normalizada a `{leve, grave, fatal}`; desconocida → `desconocida`.

El generador `src/data_generator/generar_datos.py` produce justamente esos casos
sucios (mayúsculas/acentos, alias, tipos mezclados, nulos, valores absurdos).

---

## Costos (proyecto educativo)

Recursos pequeños: RDS `db.t3.micro`, EMR Serverless con auto-stop a 15 min de
inactividad, Lambdas pequeñas, interface VPC endpoints (tienen costo/hora: si no
los necesitas puedes poner `enable_vpc_endpoints=false` en el módulo network, pero
entonces la Lambda/EMR en VPC no alcanzarán las APIs sin NAT). **Destruye cuando
termines** para no acumular cargos.
```

