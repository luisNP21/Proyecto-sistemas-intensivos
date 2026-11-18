variable "name_prefix" {
  type = string
}

variable "enabled" {
  description = "Crear la aplicacion EMR Serverless y lanzar el job."
  type        = bool
  default     = true
}

variable "region" {
  type = string
}

variable "data_bucket" {
  type = string
}

variable "data_bucket_arn" {
  type = string
}

variable "artifacts_bucket" {
  type = string
}

variable "artifacts_bucket_arn" {
  type = string
}

variable "secret_arn" {
  type = string
}

variable "secret_name" {
  type = string
}

variable "spark_script_path" {
  description = "Ruta local al script streaming_job.py."
  type        = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "jdbc_driver_url" {
  description = "URL del jar del driver JDBC de PostgreSQL."
  type        = string
  default     = "https://jdbc.postgresql.org/download/postgresql-42.7.3.jar"
}
