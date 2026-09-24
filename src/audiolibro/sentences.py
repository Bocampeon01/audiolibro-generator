"""Segmentacion de texto en oraciones, para sincronizar texto con audio."""
import re

# Punto/exclamacion/interrogacion/puntos suspensivos + espacio + mayuscula (o
# apertura de exclamacion/interrogacion en es) marca el corte. Funciona razonablemente
# para es/en/pt/fr/it/de, que comparten puntuacion latina.
_SENTENCE_END = re.compile(r"(?<=[.!?…])\s+(?=[A-ZÀ-ÖØ-Þ¿¡])")

MAX_SENTENCE_CHARS = 300  # oraciones sin puntuacion (raro) se cortan igual


def split_into_sentences(text: str) -> list[str]:
    paragraphs = [p.strip() for p in text.split("\n") if p.strip()]
    sentences: list[str] = []
    for para in paragraphs:
        for chunk in _SENTENCE_END.split(para):
            chunk = chunk.strip()
            if not chunk:
                continue
            sentences.extend(_cap_length(chunk))
    return sentences or [text.strip()]


def _cap_length(sentence: str) -> list[str]:
    if len(sentence) <= MAX_SENTENCE_CHARS:
        return [sentence]
    parts = []
    remaining = sentence
    while len(remaining) > MAX_SENTENCE_CHARS:
        cut = remaining.rfind(", ", 0, MAX_SENTENCE_CHARS)
        if cut == -1:
            cut = MAX_SENTENCE_CHARS
        parts.append(remaining[:cut].strip())
        remaining = remaining[cut:].strip()
    if remaining:
        parts.append(remaining)
    return parts
