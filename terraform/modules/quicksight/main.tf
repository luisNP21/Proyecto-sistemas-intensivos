##############################################################################
# modulo quicksight
# Crea (si enabled):
#  - Rol IAM para la VPC connection de QuickSight (crear ENIs).
#  - VPC connection hacia la VPC donde esta el RDS.
#  - Data source PostgreSQL (via VPC connection).
#  - Datasets sobre analytics.lecturas_trafico y analytics.accidentes_agg.
#  - Un analisis/dashboard con visuales de streaming e historico.
# Requiere que la cuenta ya tenga QuickSight activo (suscripcion existente).
##############################################################################

locals {
  count = var.enabled ? 1 : 0
}

# ---------- Rol IAM para la VPC connection ----------
data "aws_iam_policy_document" "qs_assume" {
  count = local.count
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["quicksight.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vpc" {
  count              = local.count
  name_prefix        = "${var.name_prefix}-qs-"
  assume_role_policy = data.aws_iam_policy_document.qs_assume[0].json
}

resource "aws_iam_role_policy" "vpc" {
  count = local.count
  name  = "${var.name_prefix}-qs-eni"
  role  = aws_iam_role.vpc[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:CreateNetworkInterface",
        "ec2:ModifyNetworkInterfaceAttribute",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
      ]
      Resource = ["*"]
    }]
  })
}

# ---------- VPC connection ----------
resource "aws_quicksight_vpc_connection" "this" {
  count              = local.count
  vpc_connection_id  = "${var.name_prefix}-vpc-conn"
  name               = "${var.name_prefix}-vpc-conn"
  role_arn           = aws_iam_role.vpc[0].arn
  security_group_ids = var.vpc_connection_security_group_ids
  subnet_ids         = var.vpc_connection_subnet_ids
}

# ---------- Data source PostgreSQL ----------
resource "aws_quicksight_data_source" "pg" {
  count          = local.count
  data_source_id = "${var.name_prefix}-pg"
  name           = "${var.name_prefix}-postgres"
  aws_account_id = var.account_id
  type           = "POSTGRESQL"

  parameters {
    postgresql {
      host     = var.rds_host
      port     = var.rds_port
      database = var.db_name
    }
  }

  credentials {
    credential_pair {
      username = var.db_username
      password = var.db_password
    }
  }

  # El RDS es publico; QuickSight conecta por la ruta publica (sus rangos de IP
  # estan permitidos en el SG del RDS). No se usa VPC connection para el data
  # source porque, con RDS publico, el endpoint resuelve a IP publica y la ruta
  # privada de la VPC connection no la alcanza (GENERIC_SQL_FAILURE).

  ssl_properties {
    disable_ssl = false
  }

  permission {
    principal = var.quicksight_user_arn
    actions = [
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource",
      "quicksight:UpdateDataSource",
      "quicksight:DeleteDataSource",
      "quicksight:UpdateDataSourcePermissions",
    ]
  }
}

# ---------- Datasets ----------
resource "aws_quicksight_data_set" "lecturas" {
  count          = local.count
  data_set_id    = "${var.name_prefix}-lecturas"
  name           = "lecturas_trafico"
  aws_account_id = var.account_id
  import_mode    = "DIRECT_QUERY"

  physical_table_map {
    physical_table_map_id = "lecturas"
    relational_table {
      data_source_arn = aws_quicksight_data_source.pg[0].arn
      schema          = "analytics"
      name            = "lecturas_trafico"
      input_columns {
        name = "ventana_inicio"
        type = "DATETIME"
      }
      input_columns {
        name = "ciudad"
        type = "STRING"
      }
      input_columns {
        name = "avenida"
        type = "STRING"
      }
      input_columns {
        name = "velocidad_prom"
        type = "DECIMAL"
      }
      input_columns {
        name = "lecturas"
        type = "INTEGER"
      }
      input_columns {
        name = "estado"
        type = "STRING"
      }
    }
  }

  permissions {
    principal = var.quicksight_user_arn
    actions = [
      "quicksight:DescribeDataSet",
      "quicksight:DescribeDataSetPermissions",
      "quicksight:PassDataSet",
      "quicksight:DescribeIngestion",
      "quicksight:ListIngestions",
      "quicksight:UpdateDataSet",
      "quicksight:DeleteDataSet",
      "quicksight:CreateIngestion",
      "quicksight:CancelIngestion",
      "quicksight:UpdateDataSetPermissions",
    ]
  }
}

resource "aws_quicksight_data_set" "accidentes" {
  count          = local.count
  data_set_id    = "${var.name_prefix}-accidentes"
  name           = "accidentes_agg"
  aws_account_id = var.account_id
  import_mode    = "DIRECT_QUERY"

  physical_table_map {
    physical_table_map_id = "accidentes"
    relational_table {
      data_source_arn = aws_quicksight_data_source.pg[0].arn
      schema          = "analytics"
      name            = "accidentes_agg"
      input_columns {
        name = "ciudad"
        type = "STRING"
      }
      input_columns {
        name = "avenida"
        type = "STRING"
      }
      input_columns {
        name = "anio"
        type = "INTEGER"
      }
      input_columns {
        name = "mes"
        type = "INTEGER"
      }
      input_columns {
        name = "total_accidentes"
        type = "INTEGER"
      }
      input_columns {
        name = "total_heridos"
        type = "INTEGER"
      }
      input_columns {
        name = "total_vehiculos"
        type = "INTEGER"
      }
    }
  }

  permissions {
    principal = var.quicksight_user_arn
    actions = [
      "quicksight:DescribeDataSet",
      "quicksight:DescribeDataSetPermissions",
      "quicksight:PassDataSet",
      "quicksight:DescribeIngestion",
      "quicksight:ListIngestions",
      "quicksight:UpdateDataSet",
      "quicksight:DeleteDataSet",
      "quicksight:CreateIngestion",
      "quicksight:CancelIngestion",
      "quicksight:UpdateDataSetPermissions",
    ]
  }
}

# ---------- Dashboard ----------
resource "aws_quicksight_dashboard" "main" {
  count             = local.count
  dashboard_id      = "${var.name_prefix}-dashboard"
  name              = "${var.name_prefix} - Trafico y Accidentes"
  aws_account_id    = var.account_id
  version_description = "v1"

  definition {
    data_set_identifiers_declarations {
      data_set_arn = aws_quicksight_data_set.lecturas[0].arn
      identifier   = "lecturas"
    }
    data_set_identifiers_declarations {
      data_set_arn = aws_quicksight_data_set.accidentes[0].arn
      identifier   = "accidentes"
    }

    # --- Hoja 1: streaming en tiempo real ---
    sheets {
      sheet_id = "streaming"
      name     = "Streaming tiempo real"

      visuals {
        bar_chart_visual {
          visual_id = "choques_por_avenida"
          title {
            format_text {
              plain_text = "Avenidas por estado (ultimas lecturas)"
            }
          }
          chart_configuration {
            field_wells {
              bar_chart_aggregated_field_wells {
                category {
                  categorical_dimension_field {
                    field_id = "avenida"
                    column {
                      data_set_identifier = "lecturas"
                      column_name         = "avenida"
                    }
                  }
                }
                colors {
                  categorical_dimension_field {
                    field_id = "estado"
                    column {
                      data_set_identifier = "lecturas"
                      column_name         = "estado"
                    }
                  }
                }
                values {
                  numerical_measure_field {
                    field_id = "lecturas_count"
                    column {
                      data_set_identifier = "lecturas"
                      column_name         = "lecturas"
                    }
                    aggregation_function {
                      simple_numerical_aggregation = "SUM"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    # --- Hoja 2: historico ---
    sheets {
      sheet_id = "historico"
      name     = "Historico accidentes"

      visuals {
        bar_chart_visual {
          visual_id = "accidentes_por_ciudad"
          title {
            format_text {
              plain_text = "Accidentes por ciudad"
            }
          }
          chart_configuration {
            field_wells {
              bar_chart_aggregated_field_wells {
                category {
                  categorical_dimension_field {
                    field_id = "ciudad"
                    column {
                      data_set_identifier = "accidentes"
                      column_name         = "ciudad"
                    }
                  }
                }
                values {
                  numerical_measure_field {
                    field_id = "tot_acc"
                    column {
                      data_set_identifier = "accidentes"
                      column_name         = "total_accidentes"
                    }
                    aggregation_function {
                      simple_numerical_aggregation = "SUM"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  permissions {
    principal = var.quicksight_user_arn
    actions = [
      "quicksight:DescribeDashboard",
      "quicksight:ListDashboardVersions",
      "quicksight:UpdateDashboardPermissions",
      "quicksight:QueryDashboard",
      "quicksight:UpdateDashboard",
      "quicksight:DeleteDashboard",
      "quicksight:DescribeDashboardPermissions",
      "quicksight:UpdateDashboardPublishedVersion",
    ]
  }
}
