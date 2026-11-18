variable "name_prefix" {
  type = string
}

variable "my_ip_cidr" {
  type = string
}

variable "quicksight_cidrs" {
  description = "Rangos CIDR publicos de QuickSight de la region (opcional)."
  type        = list(string)
  default     = []
}

variable "region" {
  type    = string
  default = ""
}

variable "enable_vpc_endpoints" {
  description = "Crear VPC endpoints (S3 gateway + interface para secretsmanager/logs/monitoring) para que el computo en VPC alcance las APIs sin NAT."
  type        = bool
  default     = true
}
