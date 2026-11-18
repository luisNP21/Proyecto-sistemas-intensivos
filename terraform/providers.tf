# El provider AWS lee las credenciales de las variables de entorno:
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
# La region se toma de la variable aws_region (que por defecto puede venir de AWS_DEFAULT_REGION).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Env       = "dev"
    }
  }
}

provider "random" {}
provider "archive" {}
provider "tls" {}
provider "null" {}

# Datos de la cuenta/region actuales
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
