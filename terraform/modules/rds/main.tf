##############################################################################
# modulo rds
# Una sola instancia PostgreSQL publica, pequena, en el SG del modulo network.
# Tras crearla, un null_resource aplica el DDL (schemas oltp/analytics y tablas)
# ejecutando un script Python con psycopg2 (reproducible, idempotente).
##############################################################################

resource "aws_db_subnet_group" "this" {
  name_prefix = "${var.name_prefix}-"
  subnet_ids  = var.subnet_ids

  tags = {
    Name = "${var.name_prefix}-db-subnets"
  }
}

resource "aws_db_instance" "this" {
  identifier_prefix = "${var.name_prefix}-"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids
  publicly_accessible    = true

  multi_az                  = false
  skip_final_snapshot       = true
  deletion_protection       = false
  apply_immediately         = true
  backup_retention_period   = 0
  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.name_prefix}-postgres"
  }
}

# Bootstrap del DDL. Se re-ejecuta si cambia el SQL o el endpoint.
resource "null_resource" "ddl" {
  triggers = {
    ddl_hash = filemd5(var.ddl_sql_path)
    endpoint = aws_db_instance.this.address
  }

  provisioner "local-exec" {
    interpreter = ["python", "-c"]
    command     = <<-PY
      import os, sys, time
      try:
          import psycopg2
      except ImportError:
          sys.stderr.write("psycopg2 no instalado. Ejecuta: pip install psycopg2-binary\n")
          sys.exit(1)
      host="${aws_db_instance.this.address}"; port=${aws_db_instance.this.port}
      dbname="${var.db_name}"; user="${var.db_username}"
      pwd=os.environ["PGPASSWORD"]
      sql=open(r"${replace(var.ddl_sql_path, "\\", "/")}", encoding="utf-8").read()
      last=None
      for i in range(30):
          try:
              c=psycopg2.connect(host=host,port=port,dbname=dbname,user=user,password=pwd,connect_timeout=10)
              c.autocommit=True
              with c.cursor() as cur: cur.execute(sql)
              c.close(); print("DDL aplicado."); sys.exit(0)
          except Exception as e:
              last=e; print("Esperando RDS... (%d) %s"%(i,e)); time.sleep(10)
      sys.stderr.write("No se pudo aplicar DDL: %s\n"%last); sys.exit(1)
    PY

    environment = {
      PGPASSWORD = var.db_password
    }
  }

  depends_on = [aws_db_instance.this]
}
