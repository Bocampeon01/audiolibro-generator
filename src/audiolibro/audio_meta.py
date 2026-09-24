"""Titulo y capitulos de audiolibros que no genero este proyecto (bajados de internet,
copiados a mano), leidos con ffprobe: entiende capitulos de M4B/M4A (Nero y QuickTime)
y de MP3 (ID3 CHAP)."""
import json
import subprocess
from pathlib import Path

# Formatos de audiolibro que el reproductor Android puede reproducir.
AUDIO_TYPES = {
    ".m4b": "audio/mp4",
    ".m4a": "audio/mp4",
    ".mp3": "audio/mpeg",
    ".aac": "audio/aac",
    ".ogg": "audio/ogg",
    ".opus": "audio/ogg",
    ".flac": "audio/flac",
}


def probe(path: Path) -> dict | None:
    """{title, chapters, sentences}; None si ffprobe no puede leer el archivo."""
    cmd = [
        "ffprobe", "-v", "error", "-print_format", "json",
        "-show_chapters", "-show_format", str(path),
    ]
    result = subprocess.run(cmd, capture_output=True, encoding="utf-8", errors="replace")
    if result.returncode != 0:
        return None
    data = json.loads(result.stdout or "{}")
    tags = {k.lower(): v for k, v in data.get("format", {}).get("tags", {}).items()}

    # Un M4B generado por este proyecto trae todo (incluidas las oraciones) en "lyrics".
    embedded = _embedded_sync(tags.get("lyrics"))
    if embedded is not None:
        return embedded

    chapters = []
    for i, ch in enumerate(data.get("chapters", []), start=1):
        ch_tags = {k.lower(): v for k, v in ch.get("tags", {}).items()}
        chapters.append({
            "title": ch_tags.get("title") or f"Capitulo {i}",
            "start_ms": round(float(ch["start_time"]) * 1000),
            "end_ms": round(float(ch["end_time"]) * 1000),
        })
    return {"title": tags.get("title") or path.stem, "chapters": chapters, "sentences": []}


def _embedded_sync(lyrics: str | None) -> dict | None:
    if not lyrics or not lyrics.lstrip().startswith("{"):
        return None
    try:
        data = json.loads(lyrics)
    except ValueError:
        return None
    return data if isinstance(data, dict) and "chapters" in data else None
