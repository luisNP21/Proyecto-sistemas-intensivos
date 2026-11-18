"""Lanza (o relanza) el job de streaming en EMR Serverless con el script actual."""
import json
import os
import boto3

REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
APP_ID = "00gacmrbnn0rsc09"
ARTIFACTS = "trafico-valle-artifacts-609789571098"
DATA = "trafico-valle-data-609789571098"
SECRET = "trafico-valle-db-20261117034556241200000003"

emr = boto3.client("emr-serverless", region_name=REGION)
iam = boto3.client("iam", region_name=REGION)

# Buscar el rol de ejecucion del job (prefijo trafico-valle-emr-job-)
roles = iam.list_roles(MaxItems=200)["Roles"]
role = next(r["Arn"] for r in roles if r["RoleName"].startswith("trafico-valle-emr-job-"))

script = f"s3://{ARTIFACTS}/scripts/streaming_job.py"
jar = f"s3://{ARTIFACTS}/jars/postgresql-jdbc.jar"

resp = emr.start_job_run(
    applicationId=APP_ID,
    executionRoleArn=role,
    name="trafico-valle-streaming-job",
    jobDriver={"sparkSubmit": {
        "entryPoint": script,
        "entryPointArguments": ["--data-bucket", DATA, "--secret-name", SECRET, "--region", REGION],
        "sparkSubmitParameters": (
            "--jars " + jar +
            " --conf spark.jars.packages=org.postgresql:postgresql:42.7.3" +
            " --conf spark.executor.cores=2 --conf spark.executor.memory=4g" +
            " --conf spark.driver.cores=1 --conf spark.driver.memory=2g" +
            " --conf spark.dynamicAllocation.enabled=false" +
            " --conf spark.executor.instances=1"
        ),
    }},
    configurationOverrides={"monitoringConfiguration": {
        "s3MonitoringConfiguration": {"logUri": f"s3://{DATA}/emr-logs/"}
    }},
)
jid = resp["jobRunId"]
with open("terraform/_newjob.txt", "w", encoding="utf-8") as f:
    f.write(f"role={role}\njobRunId={jid}")
print("role=", role)
print("jobRunId=", jid)
