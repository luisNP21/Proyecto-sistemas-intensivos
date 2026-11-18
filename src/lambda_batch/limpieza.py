"""Reglas de limpieza/normalizacion del batch historico.

Transforma las filas crudas de oltp.accidentes en:
  - validas    -> normalizadas, listas para curated/ y para agregar
  - rechazadas -> con el motivo del rechazo, van a failed/

Reglas explicitas:
  * ciudad/avenida: se normaliza contra un mapa de alias a nombre canonico.
    Si no se reconoce, se rechaza.
  * fecha: se intenta parsear varios formatos; si falla, se rechaza.
  * vehiculos: entero 1..10; fuera de rango o no numerico -> rechazo.
  * heridos: entero 0..20; negativo/no numerico -> se corrige a None/0 segun caso.
  * responsable: nulo/vacio permitido (se marca 'DESCONOCIDO'), no causa rechazo.
  * gravedad: se normaliza a {leve, grave, fatal}; desconocida -> 'desconocida'.
"""
import re
import unicodedata
from datetime import datetime

MAX_VEHICULOS = 10          # mas de esto es un dato absurdo (ej. 30 carros)
MIN_VEHICULOS = 1
MAX_HERIDOS = 20

_FECHA_FORMATS = ["%Y-%m-%d", "%d/%m/%Y", "%m-%d-%Y", "%Y/%m/%d %H:%M", "%d-%b-%Y"]


def _strip_accents(s: str) -> str:
    s = unicodedata.normalize("NFKD", s)
    return "".join(c for c in s if not unicodedata.combining(c))


def _norm_key(s):
    if s is None:
        return ""
    s = _strip_accents(str(s)).lower().strip()
    s = re.sub(r"[\.\-_]", " ", s)
    s = re.sub(r"\s+", " ", s)
    return s


# Alias -> nombre canonico de ciudad
_CIUDAD_MAP = {}
for canon, alias in {
    "Medellin":    ["medellin", "medallo", "mde"],
    "Sabaneta":    ["sabaneta"],
    "Envigado":    ["envigado"],
    "La Estrella": ["la estrella", "estrella"],
    "Caldas":      ["caldas"],
    "Bello":       ["bello"],
}.items():
    for a in alias:
        _CIUDAD_MAP[_norm_key(a)] = canon

# Alias -> nombre canonico de avenida
_AVENIDA_MAP = {}
for canon, alias in {
    "Av Regional":   ["av regional", "avenida regional", "regional", "av reginal"],
    "Av Las Vegas":  ["av vegas", "av las vegas", "avenida las vegas", "las vegas", "vegas"],
    "Av El Poblado": ["av poblado", "av el poblado", "avenida poblado", "poblado"],
    "Av 80":         ["av 80", "av80", "avenida 80", "la 80", "80"],
    "Av San Juan":   ["av san juan", "san juan", "avenida san juan", "sanjuan"],
    "Av Oriental":   ["av oriental", "oriental", "avenida oriental"],
    "Av Guayabal":   ["av guayabal", "guayabal", "avenida guayabal"],
    "Av 33":         ["av 33", "av33", "avenida 33", "la 33", "33"],
}.items():
    for a in alias:
        _AVENIDA_MAP[_norm_key(a)] = canon

_GRAVEDAD_MAP = {
    "leve": "leve", "l": "leve",
    "grave": "grave", "g": "grave",
    "fatal": "fatal", "mortal": "fatal",
}


def parse_fecha(v):
    if v is None:
        return None
    s = str(v).strip()
    if not s:
        return None
    for fmt in _FECHA_FORMATS:
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    return None


def to_int(v):
    if v is None:
        return None
    s = str(v).strip()
    if not re.fullmatch(r"-?\d+", s):
        return None
    return int(s)


def to_float(v):
    if v is None:
        return None
    s = str(v).strip()
    try:
        f = float(s)
    except ValueError:
        return None
    if f != f:  # NaN
        return None
    return f


def limpiar_fila(row: dict):
    """Devuelve (fila_limpia | None, motivo_rechazo | None)."""
    ciudad = _CIUDAD_MAP.get(_norm_key(row.get("ciudad_raw")))
    if not ciudad:
        return None, f"ciudad_desconocida:{row.get('ciudad_raw')!r}"

    avenida = _AVENIDA_MAP.get(_norm_key(row.get("avenida_raw")))
    if not avenida:
        return None, f"avenida_desconocida:{row.get('avenida_raw')!r}"

    fecha = parse_fecha(row.get("fecha_raw"))
    if fecha is None:
        return None, f"fecha_invalida:{row.get('fecha_raw')!r}"

    veh = to_int(row.get("vehiculos_raw"))
    if veh is None or veh < MIN_VEHICULOS or veh > MAX_VEHICULOS:
        return None, f"vehiculos_fuera_de_rango:{row.get('vehiculos_raw')!r}"

    her = to_int(row.get("heridos_raw"))
    if her is None or her < 0 or her > MAX_HERIDOS:
        her = 0  # se corrige, no se rechaza

    responsable = (row.get("responsable") or "").strip() or "DESCONOCIDO"
    gravedad = _GRAVEDAD_MAP.get(_norm_key(row.get("gravedad_raw")), "desconocida")

    limpia = {
        "id": row.get("id"),
        "fecha": fecha.date().isoformat(),
        "anio": fecha.year,
        "mes": fecha.month,
        "ciudad": ciudad,
        "avenida": avenida,
        "vehiculos": veh,
        "heridos": her,
        "responsable": responsable,
        "gravedad": gravedad,
        "lat": to_float(row.get("lat_raw")),
        "lon": to_float(row.get("lon_raw")),
    }
    return limpia, None
