##############################################################################
# modulo monitoring -- SNS (email) + alarmas CloudWatch
#  - Streaming: mensajes visibles en la DLQ (lecturas que fallaron 3 intentos).
#  - Batch: metrica custom 'Errors' (filas rechazadas por la Lambda).
# El email requiere confirmacion manual una vez (AWS envia un correo).
##############################################################################

resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ----- Alarma streaming: hay mensajes en la DLQ -----
resource "aws_cloudwatch_metric_alarm" "dlq" {
  alarm_name          = "${var.name_prefix}-dlq-no-vacia"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = var.dlq_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_description   = "Hay lecturas en la DLQ (fallaron 3 intentos de entrega)."
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# ----- Alarma batch: metrica Errors por encima del umbral -----
resource "aws_cloudwatch_metric_alarm" "batch_errors" {
  alarm_name          = "${var.name_prefix}-batch-errors"
  namespace           = var.batch_metric_namespace
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.batch_errors_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_description   = "El batch ProcesarHistorico rechazo filas (datos sucios)."
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
