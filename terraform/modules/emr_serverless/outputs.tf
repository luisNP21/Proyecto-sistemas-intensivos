output "application_id" {
  value       = var.enabled ? aws_emrserverless_application.this[0].id : null
  description = "ID de la aplicacion EMR Serverless."
}

output "job_role_arn" {
  value       = var.enabled ? aws_iam_role.job[0].arn : null
  description = "ARN del rol de ejecucion del job."
}

output "spark_script_s3" {
  value       = var.enabled ? "s3://${var.artifacts_bucket}/scripts/streaming_job.py" : null
  description = "Ubicacion S3 del script Spark."
}
