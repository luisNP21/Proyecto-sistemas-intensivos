variable "name_prefix" {
  type = string
}

variable "runtime" {
  type    = string
  default = "python3.12"
}

variable "source_dir" {
  description = "Directorio con el codigo de la Lambda batch (handler.py, limpieza.py)."
  type        = string
}

variable "build_dir" {
  type = string
}

variable "layer_arn" {
  type = string
}

variable "secret_arn" {
  type = string
}

variable "secret_name" {
  type = string
}

variable "data_bucket" {
  type = string
}

variable "data_bucket_arn" {
  type = string
}

variable "metric_namespace" {
  type    = string
  default = "Trafico/Batch"
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}

variable "subnet_ids" {
  type    = list(string)
  default = []
}
