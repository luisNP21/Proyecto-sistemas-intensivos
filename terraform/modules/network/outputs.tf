output "vpc_id" {
  value = data.aws_vpc.default.id
}

output "subnet_ids" {
  value = data.aws_subnets.default.ids
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}

output "compute_security_group_id" {
  value = aws_security_group.compute.id
}

output "emr_subnet_ids" {
  description = "Subnets en AZ soportadas por EMR Serverless (excluye us-east-1e)."
  value       = local.emr_subnet_ids
}
