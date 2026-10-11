"""Empaquetado de wavs de capitulos en un M4B con capitulos embebidos, via ffmpeg."""
import json
import subprocess
import wave
from pathlib import Path

from . import wav_utils


# Volumen parejo entre voces (cada modelo Piper sale a un nivel distinto, medido
# -15 a -19 LUFS). -16 LUFS es el nivel habitual para voz en celulares.
LOUDNORM = "loudnorm=I=-16:TP=-1.5:LRA=11"


def _write_concat_list(wav_paths: list[Path], list_path: Path) -> None:
    lines = [f"file '{p.resolve().as_posix()}'" for p in wav_paths]
    list_path.write_text("\n".join(lines), encoding="utf-8")


def _chapter_offsets(titles: list[str], wav_paths: list[Path]) -> list[dict]:
    chapters = []
    cursor = 0
    for title, wav_path in zip(titles, wav_paths):
        duration = wav_utils.wav_duration_ms(wav_path)
        chapters.append({"title": title, "start_ms": cursor, "end_ms": cursor + duration})
        cursor += duration
    return chapters


def _ffmeta_escape(value: str) -> str:
    # Formato FFMETADATA1: '=', ';', '#', '\' y saltos de linea se escapan con '\'.
    out = []
    for ch in value:
        if ch in "=;#\\\n":
            out.append("\\")
        out.append(ch)
    return "".join(out)


def _write_ffmetadata(chapters: list[dict], meta_path: Path, book_title: str, sync_json: str) -> None:
    # sync_json (capitulos + oraciones) viaja dentro del M4B en el tag "lyrics" (atom
    # ©lyr): texto sincronizado con el audio, que es lo que ese tag representa. Asi el
    # archivo sigue siendo autosuficiente aunque se mande solo por WhatsApp/Drive.
    lines = [
        ";FFMETADATA1",
        f"title={_ffmeta_escape(book_title)}",
        f"lyrics={_ffmeta_escape(sync_json)}",
    ]
    for ch in chapters:
        lines += [
            "[CHAPTER]",
            "TIMEBASE=1/1000",
            f"START={ch['start_ms']}",
            f"END={ch['end_ms']}",
            f"title={_ffmeta_escape(ch['title'])}",
        ]
    meta_path.write_text("\n".join(lines), encoding="utf-8")


def build_m4b(
    chapter_titles: list[str],
    chapter_wavs: list[Path],
    chapter_sentences: list[list[dict]],
    out_m4b: Path,
    book_title: str,
    work_dir: Path,
) -> None:
    """chapter_sentences[i] = lista de {text, start_ms, end_ms} relativos al
    inicio del capitulo i (tal como devuelve wav_utils.concat_wavs mas duracion).
    Se reproyectan a tiempo absoluto del libro antes de escribir el sidecar."""
    if not (len(chapter_titles) == len(chapter_wavs) == len(chapter_sentences)):
        raise ValueError("chapter_titles, chapter_wavs y chapter_sentences deben tener el mismo largo")

    work_dir.mkdir(parents=True, exist_ok=True)
    out_m4b.parent.mkdir(parents=True, exist_ok=True)

    chapters = _chapter_offsets(chapter_titles, chapter_wavs)
    sentences_abs = []
    for chapter, sentences in zip(chapters, chapter_sentences):
        base = chapter["start_ms"]
        for s in sentences:
            sentences_abs.append({
                "text": s["text"],
                "start_ms": base + s["start_ms"],
                "end_ms": base + s["end_ms"],
            })
    sync_json = json.dumps(
        {"title": book_title, "chapters": chapters, "sentences": sentences_abs},
        ensure_ascii=False,
        separators=(",", ":"),
    )

    concat_list = work_dir / "concat_list.txt"
    ffmetadata = work_dir / "ffmetadata.txt"
    _write_concat_list(chapter_wavs, concat_list)
    _write_ffmetadata(chapters, ffmetadata, book_title, sync_json)

    with wave.open(str(chapter_wavs[0]), "rb") as first:
        sample_rate = first.getframerate()

    cmd = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-f", "concat", "-safe", "0", "-i", str(concat_list),
        "-i", str(ffmetadata),
        "-map_metadata", "1",
        "-map", "0:a",
        # loudnorm trabaja a 192 kHz por dentro: sin -ar el M4B saldria a 192 kHz.
        "-af", LOUDNORM, "-ar", str(sample_rate),
        "-c:a", "aac", "-b:a", "64k",
        "-f", "mp4",
        str(out_m4b),
    ]
    # utf-8 explicito: en Windows text=True decodifica con cp1252 y revienta con
    # bytes UTF-8 de acentos que ffmpeg imprime (titulos, metadata).
    result = subprocess.run(cmd, capture_output=True, encoding="utf-8", errors="replace")
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg fallo:\n{result.stderr}")

    sidecar_path = out_m4b.with_suffix(out_m4b.suffix + ".chapters.json")
    sidecar_path.write_text(sync_json, encoding="utf-8")
