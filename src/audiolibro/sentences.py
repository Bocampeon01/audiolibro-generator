"""Segmentacion de texto en oraciones, para sincronizar texto con audio."""
import re

# Fin de oracion: . ! ? … seguido de espacio y de algo que abre oracion (mayuscula,
# digito, comillas, apertura ¿¡). Una raya de dialogo solo abre oracion si sigue
# mayuscula: "—¿Quien? —pregunto" es una sola (la acotacion va en minuscula).
_OPENER = r"[\"'«“‘(\[¿¡0-9A-ZÀ-ÖØ-Þ]"
_SENTENCE_END = re.compile(rf"(?<=[.!?…])\s+(?={_OPENER}|[—–\-]\s*{_OPENER})")

# Parrafos = bloques separados por linea en blanco. Dentro de un parrafo, los saltos
# de linea simples son wraps visuales (tipico de PDF) y se unen con espacio.
_PARAGRAPH_BREAK = re.compile(r"\n\s*\n")
_HYPHEN_WRAP = re.compile(r"(\w)-\n(\w)")

MAX_SENTENCE_CHARS = 300


def split_into_sentences(text: str) -> list[str]:
    sentences: list[str] = []
    for para in _PARAGRAPH_BREAK.split(text):
        para = _HYPHEN_WRAP.sub(r"\1\2", para)
        para = " ".join(para.split())
        if not para:
            continue
        for chunk in _SENTENCE_END.split(para):
            for part in _cap_length(chunk.strip()):
                if _is_speakable(part):
                    sentences.append(part)
    return sentences


def _is_speakable(text: str) -> bool:
    # Piper no genera audio para texto sin letras/digitos ("—", "...", comillas sueltas).
    return any(ch.isalnum() for ch in text)


def _cap_length(sentence: str) -> list[str]:
    parts = []
    remaining = sentence
    while len(remaining) > MAX_SENTENCE_CHARS:
        cut = remaining.rfind(", ", 1, MAX_SENTENCE_CHARS)
        if cut != -1:
            cut += 1  # la coma queda en la primera parte
        else:
            cut = remaining.rfind(" ", 1, MAX_SENTENCE_CHARS)
            if cut == -1:
                cut = MAX_SENTENCE_CHARS
        parts.append(remaining[:cut].strip())
        remaining = remaining[cut:].strip()
    if remaining:
        parts.append(remaining)
    return parts
