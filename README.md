# Proyecto-sistemas-intensivos

Pipeline de ingeniería de datos (streaming + batch) sobre AWS, desplegado con
Terraform, para detectar choques en avenidas del Valle de Aburrá.

> **No subir a GitHub.** Todo es local; el `.gitignore` protege estado, `*.tfvars`,
> certificados y claves.

La documentación completa (arquitectura, despliegue, ejecución de ambos pipelines,
QuickSight y `terraform destroy`) está en **[docs/README.md](docs/README.md)**.

## Estructura

```
terraform/                 # IaC (estado local)
  providers.tf versions.tf variables.tf main.tf outputs.tf
  terraform.tfvars.example # plantilla (copiar a terraform.tfvars)
  modules/
    network/        VPC default, Security Groups, VPC endpoints
    secrets/        random_password + Secrets Manager
    rds/            PostgreSQL (schemas oltp + analytics) + DDL bootstrap
    storage/        buckets S3 (landing/curated/failed/checkpoints, artifacts)
    lambda_layer/   capa con pandas/pyarrow/psycopg2
    lambda_batch/   Lambda ProcesarHistorico (Pandas)
    messaging/      SQS LecturasQueue + DLQ
    iot/            IoT Core Thing + cert X.509 + Topic Rule -> SQS
    lambda_stream/  Lambda "mueve datos" (SQS -> S3)
    emr_serverless/ EMR Serverless Spark Structured Streaming
    monitoring/     SNS email + alarmas CloudWatch
    quicksight/     data source + datasets + dashboard
src/
  sql/schema.sql            DDL de oltp + analytics
  data_generator/           genera datos historicos sucios -> oltp
  lambda_batch/             handler.py + limpieza.py
  lambda_stream/            handler.py
  spark/streaming_job.py    job de EMR Serverless
  simulator/                simulador de sensores IoT (mTLS)
scripts/
  exportar_certs.py         vuelca cert/clave IoT desde outputs de Terraform
docs/README.md              guia completa
```

## Inicio rápido

```powershell
# credenciales por entorno
$env:AWS_ACCESS_KEY_ID="..."; $env:AWS_SECRET_ACCESS_KEY="..."; $env:AWS_DEFAULT_REGION="us-east-1"

cd terraform
Copy-Item terraform.tfvars.example terraform.tfvars   # edita tus valores
terraform init
terraform validate
terraform apply
```

Luego sigue docs/README.md para correr el generador batch, el simulador de
streaming y abrir el dashboard de QuickSight.
