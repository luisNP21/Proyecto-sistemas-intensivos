##############################################################################
# modulo storage
# Dos buckets:
#  - data: landing/, curated/, failed/, checkpoints/  (datos del pipeline)
#  - artifacts: scripts/ y artefactos (script Spark, drivers, etc.)
# force_destroy=true para poder destruir el stack de forma reproducible.
##############################################################################

resource "aws_s3_bucket" "data" {
  bucket        = "${var.name_prefix}-data-${var.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.name_prefix}-artifacts-${var.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Crea los "prefijos" como objetos marcador (0 bytes) para que la estructura exista.
resource "aws_s3_object" "prefixes" {
  for_each = toset(["landing/", "curated/", "failed/", "checkpoints/"])
  bucket   = aws_s3_bucket.data.id
  key      = each.value
  content  = ""
}
