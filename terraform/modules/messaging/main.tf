##############################################################################
# modulo messaging -- SQS LecturasQueue + LecturasDLQ (redrive 3 intentos)
##############################################################################

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-LecturasDLQ"
  message_retention_seconds = 1209600 # 14 dias
}

resource "aws_sqs_queue" "main" {
  name                       = "${var.name_prefix}-LecturasQueue"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}

# Permite que la DLQ reciba solo de la cola principal.
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main.arn]
  })
}
