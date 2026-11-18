##############################################################################
# modulo emr_serverless
# - Aplicacion EMR Serverless tipo Spark (soporta jobs de streaming de larga
#   duracion).
# - Rol IAM de ejecucion con acceso a S3, Secrets Manager y logs.
# - Sube el script Spark y el driver JDBC de PostgreSQL al bucket de artefactos.
# - Lanza el job de streaming con un null_resource + AWS CLI (idempotente por
#   nombre de job; reproducible).
# Todo condicionado por var.enabled.
##############################################################################

locals {
  count = var.enabled ? 1 : 0
}

# -------------------- Aplicacion EMR Serverless --------------------
resource "aws_emrserverless_application" "this" {
  count         = local.count
  name          = "${var.name_prefix}-streaming"
  release_label = "emr-7.1.0"
  type          = "spark"

  # Red: para alcanzar el RDS en la VPC.
  network_configuration {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  auto_start_configuration {
    enabled = true
  }

  # No auto-stop agresivo: es un job de streaming de larga duracion.
  auto_stop_configuration {
    enabled              = true
    idle_timeout_minutes = 15
  }

  maximum_capacity {
    cpu    = "8 vCPU"
    memory = "32 GB"
  }

  # Capacidad pre-aprovisionada: evita cold-start en cada lanzamiento del job de
  # streaming (de larga duracion). 1 driver + 2 executors pequenos.
  initial_capacity {
    initial_capacity_type = "Driver"
    initial_capacity_config {
      worker_count = 1
      worker_configuration {
        cpu    = "2 vCPU"
        memory = "4 GB"
      }
    }
  }

  initial_capacity {
    initial_capacity_type = "Executor"
    initial_capacity_config {
      worker_count = 2
      worker_configuration {
        cpu    = "2 vCPU"
        memory = "4 GB"
      }
    }
  }
}

# -------------------- Rol de ejecucion del job --------------------
data "aws_iam_policy_document" "job_assume" {
  count = local.count
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["emr-serverless.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "job" {
  count              = local.count
  name_prefix        = "${var.name_prefix}-emr-job-"
  assume_role_policy = data.aws_iam_policy_document.job_assume[0].json
}

data "aws_iam_policy_document" "job_perms" {
  count = local.count
  statement {
    sid     = "S3"
    actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:DeleteObject"]
    resources = [
      var.data_bucket_arn, "${var.data_bucket_arn}/*",
      var.artifacts_bucket_arn, "${var.artifacts_bucket_arn}/*",
    ]
  }
  statement {
    sid       = "Secret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.secret_arn]
  }
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "job" {
  count  = local.count
  name   = "${var.name_prefix}-emr-job-perms"
  role   = aws_iam_role.job[0].id
  policy = data.aws_iam_policy_document.job_perms[0].json
}

# -------------------- Artefactos en S3 --------------------
resource "aws_s3_object" "spark_script" {
  count       = local.count
  bucket      = var.artifacts_bucket
  key         = "scripts/streaming_job.py"
  source      = var.spark_script_path
  source_hash = filemd5(var.spark_script_path)
}

# Descarga del driver JDBC y subida al bucket (reproducible via null_resource).
resource "null_resource" "jdbc_driver" {
  count = local.count
  triggers = {
    url    = var.jdbc_driver_url
    bucket = var.artifacts_bucket
  }

  provisioner "local-exec" {
    interpreter = ["python", "-c"]
    command     = <<-PY
      import urllib.request, boto3, os, tempfile
      url = "${var.jdbc_driver_url}"
      tmp = os.path.join(tempfile.gettempdir(), "postgresql-jdbc.jar")
      print("Descargando driver JDBC...", url)
      urllib.request.urlretrieve(url, tmp)
      boto3.client("s3", region_name="${var.region}").upload_file(
          tmp, "${var.artifacts_bucket}", "jars/postgresql-jdbc.jar")
      print("Driver JDBC subido a s3://${var.artifacts_bucket}/jars/postgresql-jdbc.jar")
    PY
  }
}

# -------------------- Lanzamiento del job de streaming --------------------
resource "null_resource" "start_job" {
  count = local.count
  triggers = {
    app_id      = aws_emrserverless_application.this[0].id
    script_hash = filemd5(var.spark_script_path)
  }

  depends_on = [
    aws_s3_object.spark_script,
    null_resource.jdbc_driver,
    aws_iam_role_policy.job,
  ]

  provisioner "local-exec" {
    interpreter = ["python", "-c"]
    command     = <<-PY
      import boto3, json
      emr = boto3.client("emr-serverless", region_name="${var.region}")
      app_id = "${aws_emrserverless_application.this[0].id}"
      role   = "${aws_iam_role.job[0].arn}"
      script = "s3://${var.artifacts_bucket}/scripts/streaming_job.py"
      jar    = "s3://${var.artifacts_bucket}/jars/postgresql-jdbc.jar"
      resp = emr.start_job_run(
          applicationId=app_id,
          executionRoleArn=role,
          name="${var.name_prefix}-streaming-job",
          jobDriver={"sparkSubmit": {
              "entryPoint": script,
              "entryPointArguments": [
                  "--data-bucket", "${var.data_bucket}",
                  "--secret-name", "${var.secret_name}",
                  "--region", "${var.region}",
              ],
              "sparkSubmitParameters": (
                  "--jars " + jar +
                  " --conf spark.jars.packages=org.postgresql:postgresql:42.7.3" +
                  " --conf spark.executor.cores=2 --conf spark.executor.memory=4g" +
                  " --conf spark.driver.cores=1 --conf spark.driver.memory=2g"
              ),
          }},
          configurationOverrides={"monitoringConfiguration": {
              "s3MonitoringConfiguration": {"logUri": "s3://${var.data_bucket}/emr-logs/"}
          }},
      )
      print("Job EMR lanzado:", json.dumps(resp.get("jobRunId", "")))
    PY
  }
}
