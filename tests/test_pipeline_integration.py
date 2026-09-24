"""Genera un M4B real con Piper + ffmpeg. Requiere la voz es_ES-davefx-medium en voices/."""
import json
import struct
from pathlib import Path

import pytest

from audiolibro import pipeline

VOICE = "es_ES-davefx-medium"


def _boxes(data: bytes):
    pos = 0
    while pos + 8 <= len(data):
        size, kind = struct.unpack(">I4s", data[pos : pos + 8])
        header = 8
        if size == 1:
            size = struct.unpack(">Q", data[pos + 8 : pos + 16])[0]
            header = 16
        elif size == 0:
            size = len(data) - pos
        if size < header or pos + size > len(data):
            return
        yield kind, data[pos + header : pos + size]
        pos += size


def _child(data: bytes, kind: bytes) -> bytes | None:
    return next((body for k, body in _boxes(data) if k == kind), None)


def read_embedded_sync(m4b: Path) -> dict | None:
    """Misma logica que android_app/lib/services/mp4_metadata.dart."""
    moov = _child(m4b.read_bytes(), b"moov")
    udta = _child(moov, b"udta") if moov else None
    meta = _child(udta, b"meta") if udta else (_child(moov, b"meta") if moov else None)
    ilst = _child(meta[4:], b"ilst") if meta else None  # meta es full box: 4 bytes version/flags
    lyr = _child(ilst, b"\xa9lyr") if ilst else None
    data = _child(lyr, b"data") if lyr else None
    return json.loads(data[8:].decode("utf-8")) if data else None  # 8 = tipo + locale


@pytest.fixture(scope="module")
def generated(tmp_path_factory):
    if not (pipeline.VOICES_DIR / f"{VOICE}.onnx").exists():
        pytest.skip("voz no descargada")
    tmp = tmp_path_factory.mktemp("gen")
    src = tmp / "libro.txt"
    src.write_text(
        "Un prologo antes de todo.\n\n"
        "Capítulo 1\n\n"
        "El perro corria por el\ncampo verde. —¿Quién anda ahí? —preguntó Ángel.\n\n"
        "* * *\n\n—\n\n"
        "Capítulo 2: Título con = y ; raros\n\n"
        "Última oración del libro.",
        encoding="utf-8",
    )
    out = tmp / "libro.m4b"
    pipeline.run(src, out, None, VOICE, keep_temp=False, title="Mi libro; con #raros=")
    return out


def test_sidecar_and_embedded_metadata_match(generated):
    sidecar = json.loads(generated.with_suffix(".m4b.chapters.json").read_text(encoding="utf-8"))
    embedded = read_embedded_sync(generated)
    assert embedded == sidecar
    assert embedded["title"] == "Mi libro; con #raros="
    assert [c["title"] for c in embedded["chapters"]] == [
        "Inicio", "Capítulo 1", "Capítulo 2: Título con = y ; raros",
    ]
    texts = [s["text"] for s in embedded["sentences"]]
    assert "El perro corria por el campo verde." in texts
    assert "—¿Quién anda ahí? —preguntó Ángel." in texts
    assert not any(t in ("* * *", "—") for t in texts)


def test_sentence_timings_are_contiguous(generated):
    sync = read_embedded_sync(generated)
    sents = sync["sentences"]
    assert sents[0]["start_ms"] == 0
    for a, b in zip(sents, sents[1:]):
        assert a["end_ms"] == b["start_ms"]
    assert sents[-1]["end_ms"] == sync["chapters"][-1]["end_ms"]
