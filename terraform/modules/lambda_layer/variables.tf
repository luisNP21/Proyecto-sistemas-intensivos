variable "name_prefix" {
  type = string
}

variable "layer_name" {
  type = string
}

variable "requirements_path" {
  description = "Ruta al requirements.txt de la capa."
  type        = string
}

variable "python_version" {
  description = "Version de Python para la etiqueta de compatibilidad (ej. 3.12)."
  type        = string
  default     = "3.12"
}

variable "runtime" {
  type    = string
  default = "python3.12"
}

variable "build_dir" {
  description = "Directorio temporal de build (se crea)."
  type        = string
}

variable "artifacts_bucket" {
  description = "Bucket S3 donde subir el zip de la capa (evita el limite de 70MB de PublishLayerVersion)."
  type        = string
}
