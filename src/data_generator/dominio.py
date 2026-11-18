"""Dominio compartido: ciudades del Valle de Aburra y avenidas de Medellin.

Se usa tanto por el generador batch (para producir datos sucios) como por el
simulador de streaming (para emitir lecturas limpias).
"""

# Nombres canonicos (como quedan tras la limpieza).
CIUDADES = ["Medellin", "Sabaneta", "Envigado", "La Estrella", "Caldas", "Bello"]

AVENIDAS = [
    "Av Regional",
    "Av Las Vegas",
    "Av El Poblado",
    "Av 80",
    "Av San Juan",
    "Av Oriental",
    "Av Guayabal",
    "Av 33",
]

# Variantes "sucias" de los nombres de ciudad -> para generar datos erroneos.
# El mapa de normalizacion vive en el handler batch (limpieza.py).
CIUDADES_SUCIAS = [
    "medellin", "MEDELLIN", "Medellín", "medellín", "Medallo", "MDE",
    "sabaneta", "SABANETA", "Sabaneta ",
    "envigado", "ENVIGADO", "Envigadó",
    "la estrella", "LA ESTRELLA", "la-estrella", "Estrella",
    "caldas", "CALDAS",
    "bello", "BELLO", " Bello",
]

AVENIDAS_SUCIAS = [
    "av regional", "AV REGINAL", "Avenida Regional", "regional", "Av. Regional",
    "av vegas", "AV LAS VEGAS", "Avenida Las Vegas", "las vegas", "Av. Vegas",
    "av poblado", "AV EL POBLADO", "Avenida Poblado", "poblado", "Av. El Poblado",
    "av 80", "AV80", "Avenida 80", "la 80", "Av. 80",
    "av san juan", "SAN JUAN", "Avenida San Juan", "sanjuan", "Av. San Juan",
    "av oriental", "ORIENTAL", "Avenida Oriental",
    "av guayabal", "GUAYABAL", "Avenida Guayabal",
    "av 33", "AV33", "Avenida 33", "la 33",
]

GRAVEDAD_SUCIA = ["leve", "Leve", "LEVE", "grave", "Grave", "GRAVE",
                  "fatal", "Fatal", "FATAL", "mortal", "l", "g", ""]

RESPONSABLES = ["Conductor A", "Conductor B", "Peaton", "Moto", "Bus", "Taxi", None, ""]
