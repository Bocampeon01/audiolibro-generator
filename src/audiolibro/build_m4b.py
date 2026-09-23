"""Empaquetado de wavs de capitulos en un M4B con capitulos embebidos, via ffmpeg."""
import json
import subprocess
import wave
from pathlib import Path


def _wav_duration_ms(path: Path) -> int:
    with wave.open(str(path), "rb") as wav_file:
        frames = wav_file.getnframes()
        rate = wav_file.getframerate()
    return int(frames / rate * 1000)


def _write_concat_list(wav_paths: list[Path], list_path: Path) -> None:
    lines = [f"file '{p.resolve().as_posix()}'" for p in wav_paths]
    list_path.write_text("\n".join(lines), encoding="utf-8")


def _chapter_offsets(titles: list[str], wav_paths: list[Path]) -> list[dict]:
    chapters = []
    cursor = 0
    for title, wav_path in zip(titles, wav_paths):
        duration = _wav_duration_ms(wav_path)
        chapters.append({"title": title, "start_ms": cursor, "end_ms": cursor + duration})
        cursor += duration
    return chapters


def _write_ffmetadata(chapters: list[dict], meta_path: Path, book_title: str) -> None:
    lines = [";FFMETADATA1", f"title={book_title}"]
    for ch in chapters:
        lines += [
            "[CHAPTER]",
            "TIMEBASE=1/1000",
            f"START={ch['start_ms']}",
            f"END={ch['end_ms']}",
            f"title={ch['title']}",
        ]
    meta_path.write_text("\n".join(lines), encoding="utf-8")


def _write_chapters_sidecar(chapters: list[dict], book_title: str, sidecar_path: Path) -> None:
    sidecar_path.write_text(
        json.dumps({"title": book_title, "chapters": chapters}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def build_m4b(
    chapter_titles: list[str],
    chapter_wavs: list[Path],
    out_m4b: Path,
    book_title: str,
    work_dir: Path,
) -> None:
    if len(chapter_titles) != len(chapter_wavs):
        raise ValueError("chapter_titles y chapter_wavs deben tener el mismo largo")

    work_dir.mkdir(parents=True, exist_ok=True)
    out_m4b.parent.mkdir(parents=True, exist_ok=True)

    concat_list = work_dir / "concat_list.txt"
    ffmetadata = work_dir / "ffmetadata.txt"
    _write_concat_list(chapter_wavs, concat_list)
    chapters = _chapter_offsets(chapter_titles, chapter_wavs)
    _write_ffmetadata(chapters, ffmetadata, book_title)

    cmd = [
        "ffmpeg", "-y",
        "-f", "concat", "-safe", "0", "-i", str(concat_list),
        "-i", str(ffmetadata),
        "-map_metadata", "1",
        "-map", "0:a",
        "-c:a", "aac", "-b:a", "64k",
        "-f", "mp4",
        str(out_m4b),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg fallo:\n{result.stderr}")

    sidecar_path = out_m4b.with_suffix(out_m4b.suffix + ".chapters.json")
    _write_chapters_sidecar(chapters, book_title, sidecar_path)
