variable "name_prefix" {
  type = string
}

variable "sqs_queue_url" {
  type = string
}

variable "sqs_queue_arn" {
  type = string
}

variable "topic_filter" {
  description = "Topico MQTT del que la regla toma mensajes."
  type        = string
  default     = "trafico/lecturas"
}
