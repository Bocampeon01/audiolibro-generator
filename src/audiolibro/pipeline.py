"""CLI: documento -> audiolibro M4B.

Uso:
    python -m audiolibro.pipeline entrada.pdf --out output/libro.m4b
    python -m audiolibro.pipeline entrada.pdf --voice en_US-hfc_female-medium
"""
import argparse
import shutil
import tempfile
from pathlib import Path
from typing import Callable, Optional

from . import build_m4b as build_m4b_mod
from . import chapters as chapters_mod
from . import detect_lang as detect_lang_mod
from . import extract as extract_mod
from . import sentences as sentences_mod
from . import tts_piper
from . import wav_utils

VOICES_DIR = Path(__file__).resolve().parent.parent.parent / "voices"

ProgressCallback = Callable[[str, int, int], None]


def _synthesize_chapter(
    chapter_text: str, voice_name: str, work_dir: Path, chapter_index: int
) -> tuple[Path, list[dict]]:
    sentence_texts = sentences_mod.split_into_sentences(chapter_text)

    sentence_wavs = []
    for i, sent in enumerate(sentence_texts):
        wav_path = work_dir / f"ch{chapter_index:03d}_s{i:05d}.wav"
        tts_piper.synthesize_to_wav(sent, voice_name, VOICES_DIR, wav_path)
        sentence_wavs.append(wav_path)

    chapter_wav = work_dir / f"chapter_{chapter_index:03d}.wav"
    offsets_ms = wav_utils.concat_wavs(sentence_wavs, chapter_wav)
    total_ms = wav_utils.wav_duration_ms(chapter_wav)

    sentence_infos = []
    for i, (text, start) in enumerate(zip(sentence_texts, offsets_ms)):
        end = offsets_ms[i + 1] if i + 1 < len(offsets_ms) else total_ms
        sentence_infos.append({"text": text, "start_ms": start, "end_ms": end})

    return chapter_wav, sentence_infos


def run(
    input_path: Path,
    out_path: Path,
    lang: str | None,
    voice_id: str | None,
    keep_temp: bool,
    on_progress: Optional[ProgressCallback] = None,
) -> None:
    def report(stage: str, step: int, total: int) -> None:
        print(f"[{step}/{total}] {stage}")
        if on_progress:
            on_progress(stage, step, total)

    report("Extrayendo texto...", 1, 5)
    text = extract_mod.extract_text(input_path)

    if voice_id is not None:
        voice_name = voice_id
    else:
        if lang is None:
            report("Detectando idioma...", 2, 5)
            lang = detect_lang_mod.detect_language(text)
        print(f"      Idioma: {lang}")
        voice_name = detect_lang_mod.voice_for_lang(lang)
    print(f"      Voz: {voice_name}")

    report("Segmentando en capitulos...", 3, 5)
    chs = chapters_mod.split_into_chapters(text)
    print(f"      {len(chs)} capitulos/partes detectados")

    work_dir = Path(tempfile.mkdtemp(prefix="audiolibro_"))
    chapter_wavs = []
    chapter_sentences = []
    for i, ch in enumerate(chs, start=1):
        report(f"Sintetizando capitulo {i}/{len(chs)}: {ch.title[:60]}", 4, 5)
        chapter_wav, sentence_infos = _synthesize_chapter(ch.text, voice_name, work_dir, i)
        chapter_wavs.append(chapter_wav)
        chapter_sentences.append(sentence_infos)

    report("Empaquetando M4B...", 5, 5)
    build_m4b_mod.build_m4b(
        chapter_titles=[c.title for c in chs],
        chapter_wavs=chapter_wavs,
        chapter_sentences=chapter_sentences,
        out_m4b=out_path,
        book_title=input_path.stem,
        work_dir=work_dir,
    )

    if not keep_temp:
        shutil.rmtree(work_dir, ignore_errors=True)

    print(f"Listo: {out_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Genera un audiolibro M4B a partir de un PDF/DOCX/TXT.")
    parser.add_argument("input", type=Path, help="Archivo de entrada (.pdf, .docx, .txt)")
    parser.add_argument("--out", type=Path, default=None, help="Ruta de salida .m4b")
    parser.add_argument(
        "--lang",
        choices=sorted(detect_lang_mod.SUPPORTED_LANGS),
        default=None,
        help="Forzar idioma (default: autodetectar). Ignorado si se pasa --voice.",
    )
    parser.add_argument(
        "--voice",
        choices=detect_lang_mod.all_voice_ids(),
        default=None,
        help="Forzar una voz especifica (ver detect_lang.VOICES para la lista).",
    )
    parser.add_argument("--keep-temp", action="store_true", help="No borrar wavs temporales (debug)")
    args = parser.parse_args()

    out_path = args.out or Path("output") / f"{args.input.stem}.m4b"
    run(args.input, out_path, args.lang, args.voice, args.keep_temp)


if __name__ == "__main__":
    main()
