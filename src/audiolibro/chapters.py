"""Segmentacion de texto en capitulos."""
import re
from dataclasses import dataclass

CHAPTER_PATTERN = re.compile(
    r"^\s*(cap[ií]tulo|chapter|parte|part)\s+([0-9]+|[ivxlcdm]+)\b.*$",
    re.IGNORECASE,
)

MAX_CHUNK_CHARS = 12000  # fallback si no hay capitulos detectables


@dataclass
class Chapter:
    title: str
    text: str


def split_into_chapters(text: str) -> list[Chapter]:
    lines = text.splitlines()
    matches = [i for i, line in enumerate(lines) if CHAPTER_PATTERN.match(line)]

    if matches:
        chapters = []
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
