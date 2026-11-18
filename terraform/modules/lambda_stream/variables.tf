variable "name_prefix" {
  type = string
}

variable "runtime" {
  type    = string
  default = "python3.12"
}

variable "source_dir" {
  type = string
}

variable "build_dir" {
  type = string
}

variable "data_bucket" {
  type = string
}

variable "data_bucket_arn" {
  type = string
}

variable "sqs_queue_arn" {
  type = string
}

variable "batch_size" {
  type    = number
  default = 25
}

variable "batch_window_seconds" {
  type    = number
  default = 30
}
