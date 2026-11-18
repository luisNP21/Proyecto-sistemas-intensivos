-- =====================================================================
-- DDL del proyecto: schemas oltp y analytics
-- Idempotente (IF NOT EXISTS) para re-ejecutarse sin error.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS oltp;
CREATE SCHEMA IF NOT EXISTS analytics;

-- ---------------------------------------------------------------------
-- OLTP (origen batch) -- datos historicos "sucios" tal como llegan.
-- Tipos laxos (TEXT) a proposito, para poder insertar datos erroneos.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS oltp.accidentes (
    id              BIGSERIAL PRIMARY KEY,
    fecha_raw       TEXT,          -- fechas en formatos inconsistentes
    ciudad_raw      TEXT,          -- nombres de ciudad inconsistentes
    avenida_raw     TEXT,          -- nombres de avenida inconsistentes
    vehiculos_raw   TEXT,          -- nro de vehiculos (puede venir absurdo o nulo)
    heridos_raw     TEXT,
    responsable     TEXT,          -- puede venir nulo / vacio
    gravedad_raw    TEXT,          -- leve/grave/fatal con variantes
    lat_raw         TEXT,
    lon_raw         TEXT,
    ingestado_en    TIMESTAMPTZ DEFAULT now()
);

-- Marca de agua para lectura incremental del batch.
CREATE TABLE IF NOT EXISTS oltp.ingest_watermark (
    pipeline     TEXT PRIMARY KEY,
    last_id      BIGINT NOT NULL DEFAULT 0,
    actualizado  TIMESTAMPTZ DEFAULT now()
);

INSERT INTO oltp.ingest_watermark (pipeline, last_id)
VALUES ('procesar_historico', 0)
ON CONFLICT (pipeline) DO NOTHING;

-- ---------------------------------------------------------------------
-- ANALYTICS -- agregados limpios (batch historico y streaming).
-- ---------------------------------------------------------------------

-- Agregado historico de accidentes (salida del batch).
CREATE TABLE IF NOT EXISTS analytics.accidentes_agg (
    ciudad          TEXT NOT NULL,
    avenida         TEXT NOT NULL,
    anio            INT  NOT NULL,
    mes             INT  NOT NULL,
    total_accidentes INT NOT NULL,
    total_heridos    INT NOT NULL,
    total_vehiculos  INT NOT NULL,
    actualizado      TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (ciudad, avenida, anio, mes)
);

-- Lecturas de trafico agregadas por ventana de 1 min (salida del streaming).
CREATE TABLE IF NOT EXISTS analytics.lecturas_trafico (
    ventana_inicio  TIMESTAMPTZ NOT NULL,
    ventana_fin     TIMESTAMPTZ NOT NULL,
    ciudad          TEXT NOT NULL,
    avenida         TEXT NOT NULL,
    velocidad_prom  DOUBLE PRECISION NOT NULL,
    lecturas        INT NOT NULL,
    estado          TEXT NOT NULL,  -- 'choque' | 'choque_cercano' | 'sin_incidente'
    actualizado     TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (ventana_inicio, ciudad, avenida)
);

CREATE INDEX IF NOT EXISTS idx_lecturas_estado
    ON analytics.lecturas_trafico (estado);

CREATE INDEX IF NOT EXISTS idx_lecturas_ventana
    ON analytics.lecturas_trafico (ventana_inicio DESC);
