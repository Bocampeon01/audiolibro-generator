"""Utilidades para concatenar wavs y medir duraciones (todas las voces Piper de
una misma sintesis comparten sample rate/canales, asi que la concatenacion es
una simple copia de frames PCM, sin reencode)."""
import wave
from pathlib import Path


def wav_duration_ms(path: Path) -> int:
    with wave.open(str(path), "rb") as wav_file:
        frames = wav_file.getnframes()
        rate = wav_file.getframerate()
    return int(frames / rate * 1000)


def concat_wavs(wav_paths: list[Path], out_path: Path) -> list[int]:
    """Concatena wavs en out_path. Devuelve el offset (ms) de inicio de cada uno."""
    if not wav_paths:
        raise ValueError("concat_wavs necesita al menos un wav")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    offsets_ms: list[int] = []
    cursor_frames = 0

    with wave.open(str(wav_paths[0]), "rb") as first:
        params = first.getparams()
    rate = params.framerate

    with wave.open(str(out_path), "wb") as out:
        out.setparams(params)
        for p in wav_paths:
            with wave.open(str(p), "rb") as w:
                offsets_ms.append(int(cursor_frames / rate * 1000))
                out.writeframes(w.readframes(w.getnframes()))
                cursor_frames += w.getnframes()

    return offsets_ms
