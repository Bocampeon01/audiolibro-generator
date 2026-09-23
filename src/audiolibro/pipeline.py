"""CLI: documento -> audiolibro M4B.

Uso:
    python -m audiolibro.pipeline entrada.pdf --out output/libro.m4b
"""
import argparse
import shutil
import tempfile
from pathlib import Path

from . import build_m4b as build_m4b_mod
from . import chapters as chapters_mod
from . import detect_lang as detect_lang_mod
from . import extract as extract_mod
from . import tts_piper

VOICES_DIR = Path(__file__).resolve().parent.parent.parent / "voices"


def run(input_path: Path, out_path: Path, lang: str | None, keep_temp: bool) -> None:
    print(f"[1/5] Extrayendo texto de {input_path.name}...")
    text = extract_mod.extract_text(input_path)

    if lang is None:
        print("[2/5] Detectando idioma...")
        lang = detect_lang_mod.detect_language(text)
    print(f"      Idioma: {lang}")
    voice_name = detect_lang_mod.voice_for_lang(lang)

    print("[3/5] Segmentando en capitulos...")
    chs = chapters_mod.split_into_chapters(text)
    print(f"      {len(chs)} capitulos/partes detectados")

    work_dir = Path(tempfile.mkdtemp(prefix="audiolibro_"))
    wav_paths = []
    print(f"[4/5] Sintetizando audio (voz: {voice_name})...")
    for i, ch in enumerate(chs, start=1):
        wav_path = work_dir / f"chapter_{i:03d}.wav"
        print(f"      Capitulo {i}/{len(chs)}: {ch.title[:60]}")
        tts_piper.synthesize_to_wav(ch.text, voice_name, VOICES_DIR, wav_path)
        wav_paths.append(wav_path)

    print("[5/5] Empaquetando M4B...")
    build_m4b_mod.build_m4b(
        chapter_titles=[c.title for c in chs],
        chapter_wavs=wav_paths,
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
    parser.add_argument("--lang", choices=["es", "en"], default=None, help="Forzar idioma (default: autodetectar)")
    parser.add_argument("--keep-temp", action="store_true", help="No borrar wavs temporales (debug)")
    args = parser.parse_args()

    out_path = args.out or Path("output") / f"{args.input.stem}.m4b"
    run(args.input, out_path, args.lang, args.keep_temp)


if __name__ == "__main__":
    main()
