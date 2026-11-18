output "dashboard_id" {
  value       = var.enabled ? aws_quicksight_dashboard.main[0].dashboard_id : null
  description = "ID del dashboard de QuickSight."
}

output "dashboard_url" {
  value       = var.enabled ? "https://${var.region}.quicksight.aws.amazon.com/sn/dashboards/${aws_quicksight_dashboard.main[0].dashboard_id}" : null
  description = "URL del dashboard de QuickSight."
}
