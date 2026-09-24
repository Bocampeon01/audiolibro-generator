"""Sintesis de voz con Piper (offline)."""
import threading
import wave
from pathlib import Path

from piper import PiperVoice

_voice_cache: dict[str, PiperVoice] = {}
# Piper fonemiza con espeak-ng, que usa estado global en C: dos sintesis en paralelo
# (dos pedidos a la web a la vez) pueden corromperse o crashear el proceso.
_synth_lock = threading.Lock()


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
    out_wav.parent.mkdir(parents=True, exist_ok=True)
    with _synth_lock:
        voice = _load_voice(voices_dir, voice_name)
        with wave.open(str(out_wav), "wb") as wav_file:
            # Formato fijado antes: si el texto no produce audio, queda un wav vacio
            # valido en vez de "wave.Error: # channels not specified".
            wav_file.setnchannels(1)
            wav_file.setsampwidth(2)
            wav_file.setframerate(voice.config.sample_rate)
            voice.synthesize_wav(text, wav_file, set_wav_format=False)
