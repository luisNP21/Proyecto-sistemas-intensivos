variable "name_prefix" {
  type = string
}

variable "max_receive_count" {
  description = "Intentos antes de enviar a la DLQ."
  type        = number
  default     = 3
}
