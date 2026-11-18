##############################################################################
# outputs.tf - se completa por tareas.
##############################################################################

output "aws_account_id" {
  description = "Cuenta AWS activa."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "Region AWS activa."
  value       = data.aws_region.current.name
}

output "rds_endpoint" {
  description = "Host del RDS PostgreSQL."
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "Puerto del RDS."
  value       = module.rds.port
}

output "rds_jdbc_url" {
  description = "URL JDBC del RDS."
  value       = module.rds.jdbc_url
}

output "db_secret_name" {
  description = "Nombre del secreto en Secrets Manager con las credenciales del RDS."
  value       = module.secrets.secret_name
}

output "db_secret_arn" {
  description = "ARN del secreto con credenciales del RDS."
  value       = module.secrets.secret_arn
}

output "data_bucket" {
  description = "Bucket S3 de datos (landing/curated/failed/checkpoints)."
  value       = module.storage.data_bucket
}

output "artifacts_bucket" {
  description = "Bucket S3 de artefactos (scripts Spark, drivers)."
  value       = module.storage.artifacts_bucket
}

output "lambda_batch_name" {
  description = "Nombre de la Lambda ProcesarHistorico."
  value       = module.lambda_batch.function_name
}

output "iot_endpoint" {
  description = "Endpoint ATS de IoT Core para el simulador."
  value       = module.iot.endpoint_address
}

output "iot_topic" {
  description = "Topico MQTT donde publica el simulador."
  value       = module.iot.topic
}

output "iot_certificate_pem" {
  description = "Certificado X.509 del dispositivo (para el simulador)."
  value       = module.iot.certificate_pem
  sensitive   = true
}

output "iot_private_key" {
  description = "Clave privada del dispositivo (para el simulador)."
  value       = module.iot.private_key
  sensitive   = true
}

output "sqs_queue_url" {
  description = "URL de la cola LecturasQueue."
  value       = module.messaging.queue_url
}

output "sqs_dlq_name" {
  description = "Nombre de la DLQ."
  value       = module.messaging.dlq_name
}

output "lambda_stream_name" {
  description = "Nombre de la Lambda que mueve datos."
  value       = module.lambda_stream.function_name
}

output "emr_application_id" {
  description = "ID de la aplicacion EMR Serverless (null si deshabilitado)."
  value       = module.emr_serverless.application_id
}

output "sns_topic_arn" {
  description = "ARN del topic SNS de alertas (confirma la suscripcion por email)."
  value       = module.monitoring.sns_topic_arn
}

output "quicksight_dashboard_url" {
  description = "URL del dashboard de QuickSight (null si deshabilitado)."
  value       = module.quicksight.dashboard_url
}
