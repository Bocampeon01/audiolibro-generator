"""Empaquetado de wavs de capitulos en un M4B con capitulos embebidos, via ffmpeg."""
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


def _write_ffmetadata(titles: list[str], wav_paths: list[Path], meta_path: Path, book_title: str) -> None:
    lines = [";FFMETADATA1", f"title={book_title}"]
    cursor = 0
    for title, wav_path in zip(titles, wav_paths):
        duration = _wav_duration_ms(wav_path)
        lines += [
            "[CHAPTER]",
            "TIMEBASE=1/1000",
            f"START={cursor}",
            f"END={cursor + duration}",
            f"title={title}",
        ]
        cursor += duration
    meta_path.write_text("\n".join(lines), encoding="utf-8")


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
    _write_ffmetadata(chapter_titles, chapter_wavs, ffmetadata, book_title)

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
