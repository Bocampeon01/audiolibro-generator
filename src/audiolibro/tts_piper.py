"""Sintesis de voz con Piper (offline)."""
import wave
from pathlib import Path

from piper import PiperVoice

_voice_cache: dict[str, PiperVoice] = {}


def _load_voice(voices_dir: Path, voice_name: str) -> PiperVoice:
    if voice_name not in _voice_cache:
        model_path = voices_dir / f"{voice_name}.onnx"
        if not model_path.exists():
            raise FileNotFoundError(
                f"Voz '{voice_name}' no encontrada en {voices_dir}. "
                f"Bajala con: python -m piper.download_voices --download-dir voices {voice_name}"
            )
        _voice_cache[voice_name] = PiperVoice.load(str(model_path))
    return _voice_cache[voice_name]


def synthesize_to_wav(text: str, voice_name: str, voices_dir: Path, out_wav: Path) -> None:
    voice = _load_voice(voices_dir, voice_name)
    out_wav.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(out_wav), "wb") as wav_file:
        voice.synthesize_wav(text, wav_file)
