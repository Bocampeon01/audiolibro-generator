"""Deteccion de idioma y catalogo de voces Piper disponibles."""

# Cada voz es un modelo Piper (.onnx) que hay que tener descargado en voices/.
# id = nombre de archivo sin extension, tal como lo espera piper.download_voices.
VOICES: dict[str, list[dict[str, str]]] = {
    "es": [
        {"id": "es_ES-davefx-medium", "label": "Espanol (Espana) - Masculina"},
        {"id": "es_AR-daniela-high", "label": "Espanol (Argentina) - Femenina"},
    ],
    "en": [
        {"id": "en_US-hfc_male-medium", "label": "English (US) - Male"},
        {"id": "en_US-hfc_female-medium", "label": "English (US) - Female"},
    ],
    "pt": [
        {"id": "pt_BR-faber-medium", "label": "Portugues (Brasil) - Voz Faber"},
        {"id": "pt_BR-jeff-medium", "label": "Portugues (Brasil) - Voz Jeff"},
    ],
    "fr": [
        {"id": "fr_FR-siwis-medium", "label": "Francais - Femenina"},
        {"id": "fr_FR-tom-medium", "label": "Francais - Masculina"},
    ],
    "it": [
        {"id": "it_IT-paola-medium", "label": "Italiano - Femenina"},
        {"id": "it_IT-riccardo-x_low", "label": "Italiano - Masculina (calidad baja)"},
    ],
    "de": [
        {"id": "de_DE-thorsten-medium", "label": "Deutsch - Masculina"},
        {"id": "de_DE-kerstin-low", "label": "Deutsch - Femenina (calidad baja)"},
    ],
}

LANG_NAMES = {
    "es": "Espanol",
    "en": "English",
    "pt": "Portugues",
    "fr": "Francais",
    "it": "Italiano",
    "de": "Deutsch",
}

SUPPORTED_LANGS = set(VOICES.keys())


def detect_language(text: str) -> str:
    from langdetect import DetectorFactory, detect

    DetectorFactory.seed = 0  # resultados deterministicos
    sample = text[:5000]
    lang = detect(sample)
    lang = lang.split("-")[0]
    if lang not in SUPPORTED_LANGS:
        raise ValueError(
            f"Idioma detectado '{lang}' no soportado todavia. "
            f"Soportados: {sorted(SUPPORTED_LANGS)}"
        )
    return lang


def voice_for_lang(lang: str) -> str:
    voices = VOICES.get(lang)
    if not voices:
        raise ValueError(f"No hay voces para idioma '{lang}'")
    return voices[0]["id"]


def lang_for_voice(voice_id: str) -> str:
    for lang, voices in VOICES.items():
        if any(v["id"] == voice_id for v in voices):
            return lang
    raise ValueError(f"Voz desconocida: '{voice_id}'")


def all_voice_ids() -> list[str]:
    return [v["id"] for voices in VOICES.values() for v in voices]
