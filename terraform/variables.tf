variable "project_name" {
  description = "Prefijo para nombrar todos los recursos."
  type        = string
  default     = "trafico-valle"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.project_name))
    error_message = "project_name debe ser minusculas, numeros o guiones (3-30 caracteres)."
  }
}

variable "aws_region" {
  description = "Region AWS de despliegue (ej. us-east-1)."
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Correo para recibir alarmas via SNS. Requiere confirmacion manual una vez."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email debe ser una direccion de correo valida."
  }
}

variable "my_ip_cidr" {
  description = "Tu IP publica en formato CIDR /32 para permitir acceso al RDS (ej. 1.2.3.4/32)."
  type        = string

  validation {
    condition     = can(cidrhost(var.my_ip_cidr, 0))
    error_message = "my_ip_cidr debe ser un CIDR valido, ej. 1.2.3.4/32."
  }
}

variable "db_name" {
  description = "Nombre de la base de datos PostgreSQL."
  type        = string
  default     = "trafico"
}

variable "db_username" {
  description = "Usuario administrador de PostgreSQL."
  type        = string
  default     = "trafico_admin"
}

variable "db_instance_class" {
  description = "Clase de instancia RDS (pequena por costo)."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Almacenamiento en GB para RDS."
  type        = number
  default     = 20
}

variable "quicksight_user_arn" {
  description = "ARN del usuario de QuickSight existente que sera propietario de los recursos QuickSight."
  type        = string
  default     = ""
}

variable "quicksight_namespace" {
  description = "Namespace de QuickSight."
  type        = string
  default     = "default"
}

variable "enable_quicksight" {
  description = "Crear recursos de QuickSight (data source, dataset, analisis, dashboard)."
  type        = bool
  default     = true
}

variable "enable_emr_streaming" {
  description = "Crear la aplicacion EMR Serverless y lanzar el job de streaming."
  type        = bool
  default     = true
}

variable "lambda_runtime" {
  description = "Runtime de las funciones Lambda en Python."
  type        = string
  default     = "python3.12"
}

variable "enable_vpc_endpoints" {
  description = "Crear VPC endpoints (S3 gateway + interface para secretsmanager/logs/monitoring) para que el computo en VPC (Lambda/EMR) alcance las APIs sin NAT."
  type        = bool
  default     = true
}
