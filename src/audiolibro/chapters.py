"""Segmentacion de texto en capitulos."""
import re
from dataclasses import dataclass

# Numero arabigo seguido de cualquier cosa ("Capitulo 3 El regreso"), o romano seguido
# de fin de linea / separador ("Chapter IV: ..."). Con romanos no se acepta otra palabra
# despues: "Parte di questa storia" (it) usa letras que parecen romanos.
CHAPTER_PATTERN = re.compile(
    r"^\s*(cap[ií]tulo|chapter|parte|part|chapitre|capitolo|kapitel)\s+"
    r"(?:[0-9]+\b|[ivxlcdm]+(?=\s*$|\s*[.:\-—–]))",
    re.IGNORECASE,
)

MAX_CHUNK_CHARS = 12000  # fallback si no hay capitulos detectables
MAX_HEADING_CHARS = 80  # "Parte di questa storia..." (it) no es un titulo: es una oracion


@dataclass
class Chapter:
    title: str
    text: str


def _is_heading(line: str) -> bool:
    return len(line.strip()) <= MAX_HEADING_CHARS and bool(CHAPTER_PATTERN.match(line))


def split_into_chapters(text: str) -> list[Chapter]:
    lines = text.splitlines()
    matches = [i for i, line in enumerate(lines) if _is_heading(line)]

    if matches:
        chapters = []
        preface = "\n".join(lines[: matches[0]]).strip()
        if preface:
            chapters.append(Chapter(title="Inicio", text=preface))
        for idx, start in enumerate(matches):
            end = matches[idx + 1] if idx + 1 < len(matches) else len(lines)
            title = lines[start].strip()
            body = "\n".join(lines[start + 1 : end]).strip()
            if body:
                chapters.append(Chapter(title=title, text=body))
        if chapters:
            return chapters

    return _split_by_length(text)


def _split_by_length(text: str) -> list[Chapter]:
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    chunks: list[Chapter] = []
    current = []
    current_len = 0
    for para in paragraphs:
        if current_len + len(para) > MAX_CHUNK_CHARS and current:
            chunks.append(Chapter(title=f"Parte {len(chunks) + 1}", text="\n\n".join(current)))
            current = []
            current_len = 0
        current.append(para)
        current_len += len(para)
    if current:
        chunks.append(Chapter(title=f"Parte {len(chunks) + 1}", text="\n\n".join(current)))
    return chunks
