##############################################################################
# modulo lambda_stream -- Lambda "mueve datos" (SQS -> S3 landing/failed)
# Solo usa boto3 (incluido en el runtime), no requiere capa.
# No va en VPC: solo habla con S3 y SQS via endpoints publicos de AWS.
##############################################################################

data "archive_file" "code" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${var.build_dir}/lambda_stream.zip"
  excludes    = ["__pycache__"]
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name_prefix        = "${var.name_prefix}-stream-"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "perms" {
  statement {
    sid       = "S3"
    actions   = ["s3:PutObject"]
    resources = ["${var.data_bucket_arn}/*"]
  }
  statement {
    sid       = "SQS"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [var.sqs_queue_arn]
  }
}

resource "aws_iam_role_policy" "perms" {
  name   = "${var.name_prefix}-stream-perms"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.perms.json
}

resource "aws_lambda_function" "this" {
  function_name    = "${var.name_prefix}-mueve-datos"
  role             = aws_iam_role.this.arn
  runtime          = var.runtime
  handler          = "handler.handler"
  filename         = data.archive_file.code.output_path
  source_code_hash = data.archive_file.code.output_base64sha256
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      DATA_BUCKET = var.data_bucket
    }
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${aws_lambda_function.this.function_name}"
  retention_in_days = 14
}

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn                   = var.sqs_queue_arn
  function_name                      = aws_lambda_function.this.arn
  batch_size                         = var.batch_size
  maximum_batching_window_in_seconds = var.batch_window_seconds
  enabled                            = true
}
