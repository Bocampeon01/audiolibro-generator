"""Deteccion de idioma y mapeo a voz Piper."""

SUPPORTED_LANGS = {"es", "en"}

DEFAULT_VOICES = {
    "es": "es_ES-davefx-medium",
    "en": "en_US-lessac-medium",
}


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
    if lang not in DEFAULT_VOICES:
        raise ValueError(f"No hay voz default para idioma '{lang}'")
    return DEFAULT_VOICES[lang]
