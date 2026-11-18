output "data_bucket" {
  value = aws_s3_bucket.data.bucket
}

output "data_bucket_arn" {
  value = aws_s3_bucket.data.arn
}

output "artifacts_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}

output "artifacts_bucket_arn" {
  value = aws_s3_bucket.artifacts.arn
}

output "prefixes" {
  value = {
    landing     = "landing/"
    curated     = "curated/"
    failed      = "failed/"
    checkpoints = "checkpoints/"
    scripts     = "scripts/"
  }
}
