variable "name_prefix" {
  type = string
}

variable "alert_email" {
  type = string
}

variable "dlq_name" {
  description = "Nombre de la cola DLQ a vigilar."
  type        = string
}

variable "batch_metric_namespace" {
  type    = string
  default = "Trafico/Batch"
}

variable "batch_errors_threshold" {
  description = "Umbral de la metrica Errors del batch para disparar la alarma."
  type        = number
  default     = 1
}
