variable "name_prefix" {
  type = string
}

variable "enabled" {
  type    = bool
  default = true
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "quicksight_user_arn" {
  description = "ARN del usuario QuickSight propietario de los recursos."
  type        = string
}

variable "namespace" {
  type    = string
  default = "default"
}

variable "rds_host" {
  type = string
}

variable "rds_port" {
  type = number
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "vpc_connection_subnet_ids" {
  type = list(string)
}

variable "vpc_connection_security_group_ids" {
  type = list(string)
}
