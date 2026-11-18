##############################################################################
# modulo network
# Usa la VPC default de la cuenta y crea un Security Group que abre el puerto
# 5432 (PostgreSQL) SOLO a la IP del usuario (my_ip_cidr).
# Tambien permite, opcionalmente, los rangos de IP publicos de QuickSight.
##############################################################################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Detalle de cada subnet para conocer su AZ (EMR Serverless no soporta todas).
data "aws_subnet" "each" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

locals {
  # AZ NO soportadas por EMR Serverless en us-east-1 (ej. us-east-1e).
  emr_unsupported_azs = ["us-east-1e"]

  emr_subnet_ids = [
    for id, s in data.aws_subnet.each : id
    if !contains(local.emr_unsupported_azs, s.availability_zone)
  ]
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.name_prefix}-rds-"
  description = "Acceso a PostgreSQL restringido por IP"
  vpc_id      = data.aws_vpc.default.id

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.name_prefix}-rds-sg"
  }
}

# Acceso desde la IP del usuario (simulador local, generador, psql, etc.)
resource "aws_vpc_security_group_ingress_rule" "from_my_ip" {
  security_group_id = aws_security_group.rds.id
  description       = "PostgreSQL desde mi IP"
  cidr_ipv4         = var.my_ip_cidr
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

# Acceso desde los rangos de IP de QuickSight de la region (si se proporcionan).
resource "aws_vpc_security_group_ingress_rule" "from_quicksight" {
  for_each          = toset(var.quicksight_cidrs)
  security_group_id = aws_security_group.rds.id
  description       = "PostgreSQL desde QuickSight"
  cidr_ipv4         = each.value
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.rds.id
  description       = "Salida libre"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------------------------------------------------------------------
# Security Group para computo (Lambda / EMR Serverless) que corre dentro de la
# VPC y necesita alcanzar el RDS. El RDS permite trafico entrante desde este SG.
# ---------------------------------------------------------------------------
resource "aws_security_group" "compute" {
  name_prefix = "${var.name_prefix}-compute-"
  description = "Computo (Lambda/EMR) dentro de la VPC"
  vpc_id      = data.aws_vpc.default.id

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.name_prefix}-compute-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "compute_all" {
  security_group_id = aws_security_group.compute.id
  description       = "Salida libre (acceso a AWS APIs y RDS)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# El RDS acepta PostgreSQL desde el SG de computo.
resource "aws_vpc_security_group_ingress_rule" "from_compute" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL desde computo (Lambda/EMR)"
  referenced_security_group_id = aws_security_group.compute.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# ---------------------------------------------------------------------------
# VPC Endpoints: permiten que el computo en VPC (Lambda/EMR) alcance S3 y las
# APIs de AWS sin necesidad de NAT Gateway (que tiene costo por hora).
#  - S3: gateway endpoint (gratis)
#  - Secrets Manager / CloudWatch Logs / CloudWatch Monitoring: interface
# ---------------------------------------------------------------------------
data "aws_route_tables" "default" {
  vpc_id = data.aws_vpc.default.id
}

# SG que permite HTTPS entrante desde el SG de computo hacia los interface endpoints.
resource "aws_security_group" "endpoints" {
  count       = var.enable_vpc_endpoints ? 1 : 0
  name_prefix = "${var.name_prefix}-vpce-"
  description = "HTTPS hacia interface endpoints"
  vpc_id      = data.aws_vpc.default.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpce_https" {
  count                        = var.enable_vpc_endpoints ? 1 : 0
  security_group_id            = aws_security_group.endpoints[0].id
  description                  = "HTTPS desde computo"
  referenced_security_group_id = aws_security_group.compute.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_endpoint" "s3" {
  count             = var.enable_vpc_endpoints ? 1 : 0
  vpc_id            = data.aws_vpc.default.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = data.aws_route_tables.default.ids

  tags = { Name = "${var.name_prefix}-vpce-s3" }
}

locals {
  interface_services = var.enable_vpc_endpoints ? [
    "secretsmanager", "logs", "monitoring",
  ] : []
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(local.interface_services)
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = slice(tolist(data.aws_subnets.default.ids), 0, min(2, length(data.aws_subnets.default.ids)))
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = { Name = "${var.name_prefix}-vpce-${each.value}" }
}
