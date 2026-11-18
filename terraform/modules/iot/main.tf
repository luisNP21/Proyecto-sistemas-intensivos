##############################################################################
# modulo iot -- Thing + Policy + Certificado X.509 + Topic Rule -> SQS
# El simulador usa el certificado/clave (outputs sensibles) para mTLS.
##############################################################################

data "aws_iot_endpoint" "ats" {
  endpoint_type = "iot:Data-ATS"
}

resource "aws_iot_thing" "sensor" {
  name = "${var.name_prefix}-sensor"
}

resource "aws_iot_certificate" "sensor" {
  active = true
}

# Policy que permite al dispositivo conectarse y publicar en el topico.
resource "aws_iot_policy" "sensor" {
  name = "${var.name_prefix}-sensor-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iot:Connect"]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Action   = ["iot:Publish"]
        Resource = ["arn:aws:iot:*:*:topic/${var.topic_filter}"]
      }
    ]
  })
}

resource "aws_iot_policy_attachment" "sensor" {
  policy = aws_iot_policy.sensor.name
  target = aws_iot_certificate.sensor.arn
}

resource "aws_iot_thing_principal_attachment" "sensor" {
  principal = aws_iot_certificate.sensor.arn
  thing     = aws_iot_thing.sensor.name
}

# Rol que la Topic Rule asume para escribir en SQS.
data "aws_iam_policy_document" "rule_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["iot.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rule" {
  name_prefix        = "${var.name_prefix}-iot-rule-"
  assume_role_policy = data.aws_iam_policy_document.rule_assume.json
}

resource "aws_iam_role_policy" "rule" {
  name = "${var.name_prefix}-iot-rule-sqs"
  role = aws_iam_role.rule.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage"]
      Resource = [var.sqs_queue_arn]
    }]
  })
}

# Topic Rule: reenvia cada mensaje del topico a SQS.
resource "aws_iot_topic_rule" "to_sqs" {
  name        = replace("${var.name_prefix}_lecturas_to_sqs", "-", "_")
  enabled     = true
  sql         = "SELECT * FROM '${var.topic_filter}'"
  sql_version = "2016-03-23"

  sqs {
    queue_url  = var.sqs_queue_url
    role_arn   = aws_iam_role.rule.arn
    use_base64 = false
  }
}
