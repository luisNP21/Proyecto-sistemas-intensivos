output "endpoint_address" {
  description = "Endpoint ATS de IoT Core para publicar por MQTT."
  value       = data.aws_iot_endpoint.ats.endpoint_address
}

output "thing_name" {
  value = aws_iot_thing.sensor.name
}

output "topic" {
  value = var.topic_filter
}

output "certificate_pem" {
  value     = aws_iot_certificate.sensor.certificate_pem
  sensitive = true
}

output "private_key" {
  value     = aws_iot_certificate.sensor.private_key
  sensitive = true
}

output "public_key" {
  value     = aws_iot_certificate.sensor.public_key
  sensitive = true
}
