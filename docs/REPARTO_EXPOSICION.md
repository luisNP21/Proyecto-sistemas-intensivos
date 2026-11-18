# Reparto de la exposición — 3 personas, cargas iguales

La demo completa dura ~25 min. Se divide en 3 bloques de ~8 min cada uno.
Cada persona explica un bloque con sentido propio y hace su parte en vivo.

Orden sugerido de presentación: Persona 1 → Persona 2 → Persona 3.

---

## PERSONA 1 — Contexto, arquitectura e infraestructura (≈8 min)

**Rol:** abre la presentación y da la visión global. Explica el "qué" y el "con qué".

### Qué explica
1. **El problema de negocio** (2 min)
   - Detectar en qué avenidas del Valle de Aburrá hay choques para que las
     autoridades se desplacen.
   - Regla: 0 km/h = choque, ~10 km/h = choque cercano, normal = sin incidente.
   - Las dos necesidades: streaming en tiempo real + carga histórica sucia.
   - Mostrar los **dos diagramas de arquitectura**.
   - Mencionar la decisión: el EventBridge del batch no se usa (ingesta única).

2. **Infraestructura como código con Terraform** (3 min)
   - Abrir `terraform/main.tf` y la carpeta `modules/`.
   - Explicar que todo está modularizado y es reproducible (`apply`/`destroy`).
   - `terraform.tfvars.example`: credenciales y parámetros por variables.

3. **Recorrido por los servicios base en la consola AWS** (3 min)
   - **RDS PostgreSQL**: una instancia con schemas `oltp` y `analytics`.
   - **S3**: buckets con carpetas `landing/ curated/ failed/ checkpoints/`.
   - **Secrets Manager**: contraseña autogenerada del RDS.
   - **IAM / Security Groups**: acceso al RDS restringido por IP.

### Preguntas típicas que debe saber responder
- "¿Por qué una sola RDS con dos schemas y no dos bases?" → sustitución de costo;
  separa origen (oltp) de analítica (analytics) sin pagar dos instancias.
- "¿Qué pasa si cambia una variable?" → `terraform apply` reconcilia el estado.
- "¿Por qué el estado es local?" → decisión del proyecto; para producción iría
  en backend remoto (S3 + DynamoDB lock).

### Lo que ejecuta en vivo
- Nada en terminal (su parte es conceptual + consola). Deja la BD lista para
  la Persona 2 mostrando `python scripts/check_db.py` como transición.

---

## PERSONA 2 — Pipeline BATCH (histórico sucio → limpio) (≈8 min)

**Rol:** demuestra la ingesta histórica: generar datos sucios, limpiarlos, validarlos.

### Qué explica
1. **El concepto del batch** (2 min)
   - Es una ingesta histórica masiva de accidentes con datos erróneos.
   - Tipos de "suciedad": nombres de ciudad/avenida inconsistentes
     (mayúsculas, acentos, alias), fechas en formatos distintos, nulos,
     responsables vacíos, valores absurdos (30 carros en un choque).
   - Abrir `src/data_generator/generar_datos.py` y mostrar cómo se generan.
   - Abrir `src/lambda_batch/limpieza.py` y mostrar las reglas de limpieza
     (mapa de alias → nombre canónico, rangos válidos de vehículos/heridos).

2. **Servicios involucrados en consola** (1 min)
   - **Lambda** `trafico-valle-procesar-historico` (limpia con Pandas).
   - **CloudWatch**: alarma de la métrica `Errors` (filas rechazadas).
   - **SNS**: tema de alertas por correo.

3. **DEMO en vivo** (5 min)
   ```powershell
   # a) Estado inicial
   python scripts/check_db.py

   # b) Generar 500 filas sucias en oltp
   python src/data_generator/generar_datos.py --rows 500 `
     --secret-name trafico-valle-db-20261117034556241200000003 --region us-east-1

   # c) Ejecutar la limpieza (Lambda)
   & $aws lambda invoke --function-name trafico-valle-procesar-historico `
     --region us-east-1 --cli-binary-format raw-in-base64-out salida.json ; Get-Content salida.json

   # d) Verificar resultado
   python scripts/check_db.py
   ```
   - Señalar la respuesta: `"validas": 392, "rechazadas": 108`.
   - Mostrar en **S3** los Parquet en `curated/` y `failed/`.

### Preguntas típicas que debe saber responder
- "¿Por qué Lambda con Pandas y no PySpark?" → el volumen histórico cabe en
  Lambda; Pandas es más simple de empaquetar; sustitución de costo.
- "¿Qué hace con un dato que no reconoce?" → lo rechaza y lo manda a `failed/`,
  no lo descarta en silencio.
- "¿Cómo evita reprocesar?" → usa una marca de agua (watermark) por id en
  `oltp.ingest_watermark`; solo procesa filas nuevas.

### Lo que ejecuta en vivo
Los 4 comandos de arriba (generar, limpiar, verificar).

---

## PERSONA 3 — Pipeline STREAMING + Dashboard (≈8 min)

**Rol:** demuestra el tiempo real (sensores → choques detectados) y cierra con QuickSight.

### Qué explica
1. **El concepto del streaming** (2 min)
   - Flujo: sensor simulado → IoT Core (MQTT mTLS) → SQS → Lambda → S3 landing →
     EMR Serverless (Spark) → RDS analytics → dashboard.
   - La clasificación por velocidad (choque / choque_cercano / sin_incidente).
   - **EMR Serverless vs EMR normal**: no hay clúster que mantener; AWS
     provisiona los workers solo mientras el job corre (sustitución de costo).

2. **Servicios en consola** (2 min)
   - **IoT Core**: el Thing `trafico-valle-sensor` y la regla que manda a SQS.
   - **SQS**: cola `LecturasQueue` + `LecturasDLQ` (3 reintentos).
   - **EMR sin servidor**: app `trafico-valle-streaming`, job en **Running**.
     (Recordar: está en "EMR sin servidor", no en "EMR en EC2 → Clústeres".)

3. **DEMO en vivo** (3 min)
   ```powershell
   # a) Encender el simulador de sensores
   python src/simulator/simulador.py `
     --endpoint a1051pcdpv4k7n-ats.iot.us-east-1.amazonaws.com `
     --cert src/simulator/certs/device.pem.crt `
     --key src/simulator/certs/private.pem.key `
     --root-ca src/simulator/certs/AmazonRootCA1.pem `
     --topic trafico/lecturas --intervalo 2 --prob-choque 0.25 --max-mensajes 200

   # b) (tras ~1-2 min) ver los choques clasificados en la BD
   python scripts/check_db.py
   ```
   - Mostrar las líneas del simulador (ej. "Av El Poblado: 0.3 km/h").
   - Mostrar las filas en `analytics.lecturas_trafico` con el estado clasificado.
   - (Opcional) refrescar el bucket S3 `landing/` para ver los JSON entrando.

4. **Dashboard QuickSight** (1 min)
   - Abrir `https://us-east-1.quicksight.aws.amazon.com/sn/dashboards/trafico-valle-dashboard`
   - Hoja "Histórico accidentes" (datos del batch de la Persona 2).
   - Hoja "Streaming tiempo real" (avenidas por estado).

### Preguntas típicas que debe saber responder
- "¿Qué diferencia hay entre EMR Serverless y un clúster EMR?" → Serverless no
  mantiene servidores encendidos; paga por uso y AWS gestiona los workers.
- "¿Por qué el EMR lee de S3 y no de SQS directo?" → Spark no consume SQS nativo;
  la Lambda deja micro-lotes JSON en S3 y Spark hace file-based streaming.
- "¿Cuánto tarda en detectar un choque?" → ~1 minuto (ventana de agregación).
- "¿Qué es mTLS?" → el sensor se autentica con certificado X.509, no con usuario/clave.

### Lo que ejecuta en vivo
El simulador + la verificación de la BD + abrir el dashboard.

---

## Resumen del reparto

| Persona | Bloque | Servicios que domina | Demo en vivo |
|---|---|---|---|
| **1** | Contexto + Terraform + infra base | RDS, S3, Secrets, IAM/SG, Terraform | — (consola) |
| **2** | Pipeline batch | Lambda Pandas, CloudWatch, SNS, generador | generar + limpiar + verificar |
| **3** | Streaming + dashboard | IoT Core, SQS, EMR Serverless, QuickSight | simulador + verificar + dashboard |

**Equilibrio:** cada quien ~8 min, cada quien una demo en vivo (salvo P1 que abre
con la parte conceptual más pesada), y cada quien un conjunto de servicios propio
sin solaparse.

### Consejo de ensayo
- Que cada persona corra SU parte al menos una vez antes, con la terminal lista.
- Tener la BD ya con datos (del ensayo) como red de seguridad: si la red falla en
  vivo, `check_db.py` y el dashboard ya muestran resultados reales.
- Ensayar juntos el paso de una persona a la siguiente (las transiciones).
