# Guion de la demo — Pipeline de tráfico y accidentes (Valle de Aburrá)

Guía paso a paso para presentar el proyecto y demostrar que ambos pipelines
(batch e histórico + streaming en tiempo real) funcionan sobre AWS.

> **Antes de empezar**, ten abiertos en pestañas del navegador (región **N. Virginia / us-east-1**):
> 1. La consola de AWS con tu usuario.
> 2. El dashboard de QuickSight.
> 3. Esta guía.
>
> Y en tu equipo: una terminal de PowerShell en la carpeta del proyecto, con las variables de entorno puestas.

---

## 0. Preparar la terminal (una sola vez, antes de la demo)

```powershell
# En la carpeta del proyecto
$env:AWS_ACCESS_KEY_ID="<TU_ACCESS_KEY>"
$env:AWS_SECRET_ACCESS_KEY="<TU_SECRET>"
$env:AWS_DEFAULT_REGION="us-east-1"
$aws="C:\Program Files\Amazon\AWSCLIV2\aws.exe"
```

> Si tu IP pública cambió desde el último despliegue, actualiza `my_ip_cidr` en
> `terraform/terraform.tfvars` y corre:
> `terraform -chdir=terraform apply -auto-approve -refresh=false -target=module.network.aws_vpc_security_group_ingress_rule.from_my_ip`

---

## 1. Introducción (2 min) — el problema de negocio

Explica el caso en voz alta:

> "El problema es saber en qué avenidas del Valle de Aburrá (Medellín, Sabaneta,
> Envigado, La Estrella, Caldas, Bello) hay un choque, para que las autoridades
> se desplacen. Montamos dos pipelines de datos en AWS con Terraform:
> - **Streaming:** sensores IoT simulados reportan la velocidad promedio por
>   avenida. Si una avenida reporta **0 km/h hay un choque**; ~**10 km/h es un
>   choque cercano**; velocidad normal, sin incidente.
> - **Batch:** una carga histórica de accidentes que vienen con datos sucios
>   (nombres inconsistentes, nulos, valores absurdos como 30 carros), que
>   limpiamos y validamos antes de ingestarlos."

Muestra los **dos diagramas de arquitectura** (los que ya tienes).

Menciona la decisión de diseño: *"El EventBridge del diagrama batch no se usa
porque es una sola ingesta histórica masiva, no una programada."*

---

## 2. Mostrar la infraestructura como código (2 min)

Abre el editor en la carpeta `terraform/` y enseña:
- `main.tf` → "Todo está orquestado en módulos: red, RDS, S3, IoT, SQS, Lambdas, EMR, monitoreo, QuickSight."
- La carpeta `modules/` → "Cada servicio es un módulo reutilizable."
- `terraform.tfvars.example` → "Las credenciales y parámetros van por variables; nada quemado en el código."

Frase clave:
> "Todo el despliegue es reproducible: con `terraform apply` se levanta de cero,
> y con `terraform destroy` se elimina todo."

(Opcional, si quieres impresionar) Muestra que valida:
```powershell
terraform -chdir=terraform validate
```

---

## 3. Mostrar los servicios desplegados en la consola AWS (5 min)

Recorre cada servicio en la consola. Región **us-east-1**.

| Servicio | Dónde | Qué decir |
|---|---|---|
| **RDS** | RDS → Databases | "Una instancia PostgreSQL con dos schemas: `oltp` (origen sucio) y `analytics` (datos limpios)." |
| **S3** | S3 → buckets | Abre `trafico-valle-data-...` → muestra las carpetas `landing/`, `curated/`, `failed/`, `checkpoints/`. "Aquí caen los datos crudos del streaming y los Parquet del batch." |
| **IoT Core** | IoT Core → Administrar → Objetos | Muestra `trafico-valle-sensor` → "El sensor simulado se autentica con certificado X.509 (mTLS)." Y en **Enrutamiento de mensajes → Reglas**, la regla que manda a SQS. |
| **SQS** | Amazon SQS | `trafico-valle-LecturasQueue` y `-LecturasDLQ`. "Cola principal más cola de mensajes muertos tras 3 reintentos." |
| **Lambda** | Lambda → Funciones | `trafico-valle-mueve-datos` (streaming) y `trafico-valle-procesar-historico` (batch con Pandas). |
| **EMR Serverless** | EMR → **EMR sin servidor** | App `trafico-valle-streaming` → pestaña **Ejecuciones de trabajos** → el job en **Running**. "Spark Structured Streaming lee S3 y agrega por ventanas de 1 minuto." |
| **CloudWatch** | CloudWatch → Alarmas | Las dos alarmas: DLQ no vacía y métrica `Errors` del batch. |
| **SNS** | SNS → Temas | `trafico-valle-alerts` con la suscripción de correo. |
| **Secrets Manager** | Secrets Manager | `trafico-valle-db-...` → "La contraseña del RDS se autogenera y se guarda aquí; nadie la ve en el código." |

> **Para llegar a EMR sin servidor:** consola EMR → menú lateral izquierdo, enlace
> "EMR sin servidor" (NO "EMR en EC2 → Clústeres"). Si redirige a SageMaker Studio,
> usa el buscador de arriba y escribe "EMR Serverless".

---

## 4. DEMO del pipeline BATCH (4 min)

Narrativa: *"Primero el histórico sucio. Genero datos erróneos, los inserto, y
la Lambda los limpia."*

### 4.1 Mostrar la base vacía / estado inicial
```powershell
python scripts/check_db.py
```
Muestra los conteos actuales de `oltp.accidentes`, `analytics.accidentes_agg`.

### 4.2 Generar datos sucios
```powershell
python src/data_generator/generar_datos.py --rows 500 `
  --secret-name trafico-valle-db-20261117034556241200000003 --region us-east-1
```
> Di: "Acabo de insertar 500 accidentes con datos deliberadamente sucios:
> nombres de ciudad en mayúsculas/con acentos/alias, fechas en formatos distintos,
> hasta 30 vehículos en un choque, responsables nulos."

(Opcional) Abre el archivo `src/data_generator/generar_datos.py` y muestra cómo
se generan los datos sucios.

### 4.3 Ejecutar la limpieza (Lambda)
```powershell
& $aws lambda invoke --function-name trafico-valle-procesar-historico `
  --region us-east-1 --cli-binary-format raw-in-base64-out salida.json ; Get-Content salida.json
```
> La respuesta muestra algo como:
> `{"leidas": 500, "validas": 392, "rechazadas": 108, ...}`
> Di: "De 500 filas, 392 pasaron la validación y 108 se rechazaron por datos
> imposibles. Las válidas van a `curated/` y a la tabla analytics; las rechazadas
> a `failed/`, y se emite la métrica Errors a CloudWatch."

### 4.4 Comprobar el resultado
```powershell
python scripts/check_db.py
```
> "`analytics.accidentes_agg` ya tiene los agregados limpios por ciudad/avenida/mes."

Muestra en **S3** los Parquet nuevos en `curated/` y `failed/`.

---

## 5. DEMO del pipeline STREAMING (6 min) — el plato fuerte

Narrativa: *"Ahora el tiempo real. Enciendo los sensores y vemos aparecer los
choques en la base de datos."*

### 5.1 Verificar que el job EMR está corriendo
En la consola: EMR sin servidor → la app → Ejecuciones de trabajos → **Running**.

### 5.2 Encender el simulador de sensores
```powershell
python src/simulator/simulador.py `
  --endpoint a1051pcdpv4k7n-ats.iot.us-east-1.amazonaws.com `
  --cert src/simulator/certs/device.pem.crt `
  --key src/simulator/certs/private.pem.key `
  --root-ca src/simulator/certs/AmazonRootCA1.pem `
  --topic trafico/lecturas --intervalo 2 --prob-choque 0.25 --max-mensajes 200
```
> Verás en pantalla líneas como:
> `[12] Av El Poblado Medellin: 0.3 km/h`
> Di: "Cada línea es un sensor publicando por MQTT con mTLS a IoT Core. Los que
> salen con ~0 km/h son choques."

### 5.3 Mostrar el flujo intermedio (opcional, mientras corre)
- **S3 landing/**: refresca el bucket y muestra los micro-lotes JSON que va
  escribiendo la Lambda.
- **SQS**: en la cola, métrica de mensajes recibidos.

### 5.4 Ver los choques detectados en la base de datos
Espera ~1-2 minutos (el EMR agrega por ventanas de 1 min) y corre:
```powershell
python scripts/check_db.py
```
> Verás filas reales, por ejemplo:
> ```
> ('Medellin', 'Av El Poblado', 0.3, 'choque')
> ('Medellin', 'Av 33', 11.3, 'choque_cercano')
> ('Envigado', 'Av Las Vegas', 56.4, 'sin_incidente')
> ```
> Di: "El sistema clasificó solo: velocidad casi nula = choque, velocidad baja =
> choque cercano, velocidad normal = sin incidente. Esto es lo que verían las
> autoridades para decidir a dónde desplazarse."

---

## 6. DASHBOARD en QuickSight (3 min)

Abre el dashboard:
`https://us-east-1.quicksight.aws.amazon.com/sn/dashboards/trafico-valle-dashboard`

- **Hoja "Histórico accidentes":** gráfica de accidentes por ciudad (datos del batch).
- **Hoja "Streaming tiempo real":** avenidas por estado (choque / choque_cercano / sin_incidente).

> Si una gráfica no muestra datos recientes, en QuickSight entra al dataset y pulsa
> **Refresh** (actualizar) — es DIRECT_QUERY, lee en vivo del RDS, pero a veces
> cachea la primera vez.

Cierre:
> "El dashboard es la vista final para las autoridades: de un vistazo ven qué
> avenidas tienen choques ahora y el histórico de accidentalidad por zona."

---

## 7. Cierre y preguntas (2 min)

Puntos para rematar:
- "Todo está desplegado con Terraform, es reproducible y versionado."
- "El streaming detecta choques en ~1 minuto desde que el sensor reporta."
- "El batch limpia datos sucios y separa válidos de rechazados, con alertas por correo."
- "La seguridad: RDS con acceso restringido por IP, contraseñas en Secrets Manager, mTLS en IoT."

---

## Checklist rápido (lo mínimo si vas con prisa)

1. [ ] `python scripts/check_db.py` → muestra conteos.
2. [ ] `generar_datos.py` → inserta 500 sucios.
3. [ ] `lambda invoke` → limpia (muestra validas/rechazadas).
4. [ ] `check_db.py` → analytics con datos.
5. [ ] `simulador.py` → sensores publicando choques.
6. [ ] `check_db.py` → lecturas_trafico con choques clasificados.
7. [ ] QuickSight → dashboard con las gráficas.

---

## Datos del despliegue (para copiar/pegar)

| Dato | Valor |
|---|---|
| Región | `us-east-1` |
| Cuenta | `609789571098` |
| Endpoint IoT | `a1051pcdpv4k7n-ats.iot.us-east-1.amazonaws.com` |
| App EMR Serverless | `00gacmrbnn0rsc09` (nombre `trafico-valle-streaming`) |
| Secreto RDS | `trafico-valle-db-20261117034556241200000003` |
| Bucket datos | `trafico-valle-data-609789571098` |
| Bucket artefactos | `trafico-valle-artifacts-609789571098` |
| Dashboard | `https://us-east-1.quicksight.aws.amazon.com/sn/dashboards/trafico-valle-dashboard` |

---

## IMPORTANTE: después de la demo

**Para dejar de gastar** (EMR y RDS cobran por hora):
```powershell
# Opción A: apagar todo
terraform -chdir=terraform destroy -auto-approve

# Opción B: parar solo el EMR (el más caro), conservando lo demás
# (pon enable_emr_streaming = false en terraform.tfvars y aplica)
```
