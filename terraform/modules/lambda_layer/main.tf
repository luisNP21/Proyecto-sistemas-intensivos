##############################################################################
# modulo lambda_layer
# Construye una capa Lambda instalando requirements.txt para manylinux x86_64
# (compatible con el runtime Lambda) y la empaqueta en un zip.
# Requiere 'pip' disponible en la maquina que ejecuta terraform.
##############################################################################

locals {
  layer_build   = "${var.build_dir}/${var.layer_name}"
  layer_python  = "${local.layer_build}/python"
  layer_zip     = "${var.build_dir}/${var.layer_name}.zip"
}

resource "null_resource" "build" {
  triggers = {
    requirements = filemd5(var.requirements_path)
    runtime      = var.runtime
  }

  provisioner "local-exec" {
    interpreter = ["python", "-c"]
    command     = <<-PY
      import os, shutil, subprocess, sys
      build = r"${replace(local.layer_python, "\\", "/")}"
      req   = r"${replace(var.requirements_path, "\\", "/")}"
      if os.path.isdir(build):
          shutil.rmtree(build)
      os.makedirs(build, exist_ok=True)
      cmd = [sys.executable, "-m", "pip", "install",
             "-r", req,
             "--platform", "manylinux2014_x86_64",
             "--implementation", "cp",
             "--python-version", "${var.python_version}",
             "--only-binary=:all:",
             "--upgrade",
             "-t", build]
      print("Ejecutando:", " ".join(cmd))
      subprocess.check_call(cmd)
      print("Capa construida en", build)
    PY
  }
}

data "archive_file" "layer" {
  type        = "zip"
  source_dir  = local.layer_build
  output_path = local.layer_zip
  depends_on  = [null_resource.build]
}

# La capa (pandas+pyarrow+psycopg2) supera el limite de 70MB de subida directa
# de PublishLayerVersion, por lo que se sube a S3 y se referencia desde ahi.
resource "aws_s3_object" "layer" {
  bucket = var.artifacts_bucket
  key    = "layers/${var.layer_name}.zip"
  source = data.archive_file.layer.output_path
  etag   = data.archive_file.layer.output_md5
}

resource "aws_lambda_layer_version" "this" {
  layer_name          = "${var.name_prefix}-${var.layer_name}"
  s3_bucket           = var.artifacts_bucket
  s3_key              = aws_s3_object.layer.key
  source_code_hash    = data.archive_file.layer.output_base64sha256
  compatible_runtimes = [var.runtime]
}
