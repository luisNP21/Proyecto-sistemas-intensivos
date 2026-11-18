##############################################################################
# main.tf - orquesta todos los modulos.
# Se va completando por tareas. En Task 1 solo contiene locals base.
##############################################################################

locals {
  name_prefix = var.project_name
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.name

  ddl_sql_path = "${path.module}/../src/sql/schema.sql"

  common_tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# Valida que, si QuickSight esta habilitado, se haya dado el ARN del usuario.
check "quicksight_user_arn_requerido" {
  assert {
    condition     = var.enable_quicksight == false || length(var.quicksight_user_arn) > 0
    error_message = "Si enable_quicksight=true debes definir quicksight_user_arn en terraform.tfvars."
  }
}

##############################################################################
# Red base (VPC default + Security Group del RDS)
##############################################################################
module "network" {
  source = "./modules/network"

  name_prefix          = local.name_prefix
  my_ip_cidr           = var.my_ip_cidr
  region               = local.region
  enable_vpc_endpoints = var.enable_vpc_endpoints

  # Rango de IP publicas de QuickSight en us-east-1, para que el dashboard
  # conecte al RDS publico por la ruta publica.
  quicksight_cidrs = var.enable_quicksight && var.aws_region == "us-east-1" ? ["52.23.63.224/27"] : []
}

##############################################################################
# Secretos (password autogenerada + Secrets Manager)
##############################################################################
module "secrets" {
  source = "./modules/secrets"

  name_prefix = local.name_prefix
  db_username = var.db_username
  db_name     = var.db_name
}

##############################################################################
# RDS PostgreSQL (una instancia, schemas oltp + analytics)
##############################################################################
module "rds" {
  source = "./modules/rds"

  name_prefix        = local.name_prefix
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = module.secrets.db_password
  instance_class     = var.db_instance_class
  allocated_storage  = var.db_allocated_storage
  security_group_ids = [module.network.rds_security_group_id]
  subnet_ids         = module.network.subnet_ids
  ddl_sql_path       = local.ddl_sql_path
}

##############################################################################
# Almacenamiento S3 (data + artifacts)
##############################################################################
module "storage" {
  source = "./modules/storage"

  name_prefix = local.name_prefix
  account_id  = local.account_id
}

# Rellena el secreto con la cadena de conexion completa (host/puerto incluidos).
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = module.secrets.secret_arn
  secret_string = jsonencode({
    username = var.db_username
    password = module.secrets.db_password
    engine   = "postgres"
    host     = module.rds.endpoint
    port     = module.rds.port
    dbname   = var.db_name
    jdbc_url = module.rds.jdbc_url
  })
}

##############################################################################
# Capa Lambda con dependencias del batch (pandas, pyarrow, psycopg2)
##############################################################################
module "batch_layer" {
  source = "./modules/lambda_layer"

  name_prefix       = local.name_prefix
  layer_name        = "batch-deps"
  requirements_path = "${path.module}/../src/lambda_batch/requirements.txt"
  python_version    = "3.12"
  runtime           = var.lambda_runtime
  build_dir         = "${path.module}/.build"
  artifacts_bucket  = module.storage.artifacts_bucket
}

##############################################################################
# Lambda batch ProcesarHistorico (corre en VPC para alcanzar el RDS privado)
##############################################################################
module "lambda_batch" {
  source = "./modules/lambda_batch"

  name_prefix        = local.name_prefix
  runtime            = var.lambda_runtime
  source_dir         = "${path.module}/../src/lambda_batch"
  build_dir          = "${path.module}/.build"
  layer_arn          = module.batch_layer.layer_arn
  secret_arn         = module.secrets.secret_arn
  secret_name        = module.secrets.secret_name
  data_bucket        = module.storage.data_bucket
  data_bucket_arn    = module.storage.data_bucket_arn
  metric_namespace   = "Trafico/Batch"
  security_group_ids = [module.network.compute_security_group_id]
  subnet_ids         = module.network.subnet_ids
}

##############################################################################
# Mensajeria streaming: SQS LecturasQueue + DLQ
##############################################################################
module "messaging" {
  source = "./modules/messaging"

  name_prefix       = local.name_prefix
  max_receive_count = 3
}

##############################################################################
# IoT Core: Thing + cert X.509 + Topic Rule -> SQS
##############################################################################
module "iot" {
  source = "./modules/iot"

  name_prefix   = local.name_prefix
  sqs_queue_url = module.messaging.queue_url
  sqs_queue_arn = module.messaging.queue_arn
  topic_filter  = "trafico/lecturas"
}

##############################################################################
# Lambda streaming "mueve datos": SQS -> S3 landing/failed
##############################################################################
module "lambda_stream" {
  source = "./modules/lambda_stream"

  name_prefix     = local.name_prefix
  runtime         = var.lambda_runtime
  source_dir      = "${path.module}/../src/lambda_stream"
  build_dir       = "${path.module}/.build"
  data_bucket     = module.storage.data_bucket
  data_bucket_arn = module.storage.data_bucket_arn
  sqs_queue_arn   = module.messaging.queue_arn
}

##############################################################################
# EMR Serverless: Spark Structured Streaming (landing/ -> analytics)
##############################################################################
module "emr_serverless" {
  source = "./modules/emr_serverless"

  enabled              = var.enable_emr_streaming
  name_prefix          = local.name_prefix
  region               = local.region
  data_bucket          = module.storage.data_bucket
  data_bucket_arn      = module.storage.data_bucket_arn
  artifacts_bucket     = module.storage.artifacts_bucket
  artifacts_bucket_arn = module.storage.artifacts_bucket_arn
  secret_arn           = module.secrets.secret_arn
  secret_name          = module.secrets.secret_name
  spark_script_path    = "${path.module}/../src/spark/streaming_job.py"
  subnet_ids           = module.network.emr_subnet_ids
  security_group_ids   = [module.network.compute_security_group_id]
}

##############################################################################
# Monitoreo: SNS email + alarmas CloudWatch (DLQ y Errors del batch)
##############################################################################
module "monitoring" {
  source = "./modules/monitoring"

  name_prefix            = local.name_prefix
  alert_email            = var.alert_email
  dlq_name               = module.messaging.dlq_name
  batch_metric_namespace = module.lambda_batch.metric_namespace
}

##############################################################################
# QuickSight: data source + datasets + dashboard
# Reutiliza el SG de computo para la VPC connection (ya autorizado en el RDS).
##############################################################################
module "quicksight" {
  source = "./modules/quicksight"

  enabled             = var.enable_quicksight
  name_prefix         = local.name_prefix
  account_id          = local.account_id
  region              = local.region
  quicksight_user_arn = var.quicksight_user_arn
  namespace           = var.quicksight_namespace

  rds_host    = module.rds.endpoint
  rds_port    = module.rds.port
  db_name     = var.db_name
  db_username = var.db_username
  db_password = module.secrets.db_password

  vpc_connection_subnet_ids         = module.network.subnet_ids
  vpc_connection_security_group_ids = [module.network.compute_security_group_id]
}
