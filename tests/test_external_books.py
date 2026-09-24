"""Audiolibros no generados por el proyecto (bajados de internet) copiados a output/."""
import subprocess
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from audiolibro import audio_meta
from web.backend import main

FFMETA = """;FFMETADATA1
title=Libro Externo
artist=Autor X
[CHAPTER]
TIMEBASE=1/1000
START=0
END=1500
title=Primera parte
[CHAPTER]
TIMEBASE=1/1000
START=1500
END=3000
title=Segunda parte
"""


def _make_book(tmp: Path, name: str, fmt_args: list[str]) -> Path:
    meta = tmp / "meta.txt"
    meta.write_text(FFMETA, encoding="utf-8")
    out = tmp / name
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=3",
         "-i", str(meta), "-map_metadata", "1", "-map_chapters", "1", *fmt_args, str(out)],
        check=True,
    )
    return out


@pytest.fixture
def m4b(tmp_path):
    return _make_book(tmp_path, "externo.m4b", ["-c:a", "aac", "-f", "mp4"])


@pytest.fixture
def mp3(tmp_path):
    return _make_book(tmp_path, "externo.mp3", ["-c:a", "libmp3lame", "-id3v2_version", "3"])


@pytest.mark.parametrize("fixture", ["m4b", "mp3"])
def test_probe_reads_title_and_chapters(fixture, request):
    meta = audio_meta.probe(request.getfixturevalue(fixture))
    assert meta["title"] == "Libro Externo"
    assert [c["title"] for c in meta["chapters"]] == ["Primera parte", "Segunda parte"]
    assert meta["chapters"][1]["start_ms"] == 1500
    assert meta["sentences"] == []


def test_probe_prefers_our_embedded_json():
    meta = audio_meta.probe(Path("android_app/test/fixtures/sample.m4b"))
    assert meta["sentences"], "el M4B generado trae las oraciones embebidas"


def test_probe_not_audio_returns_none(tmp_path):
    f = tmp_path / "roto.m4b"
    f.write_text("no soy audio")
    assert audio_meta.probe(f) is None


def test_library_lists_external_books(tmp_path, monkeypatch, m4b, mp3):
    out = tmp_path / "output"
    out.mkdir()
    m4b.rename(out / m4b.name)
    mp3.rename(out / mp3.name)
    (out / "notas.txt").write_text("no es audio")
    cache = tmp_path / "cache"
    cache.mkdir()
    monkeypatch.setattr(main, "OUTPUT_DIR", out)
    monkeypatch.setattr(main, "META_CACHE_DIR", cache)
    client = TestClient(main.app)

    books = {b["name"]: b for b in client.get("/api/library").json()}
    assert set(books) == {"externo.m4b", "externo.mp3"}
    assert books["externo.m4b"]["title"] == "Libro Externo"
    assert books["externo.m4b"]["chapters_count"] == 2
    # cacheado fuera de la carpeta del usuario: ahi solo quedan sus archivos
    assert (cache / "externo.m4b.json").exists()
    assert sorted(p.name for p in out.iterdir()) == ["externo.m4b", "externo.mp3", "notas.txt"]

    meta = client.get(books["externo.mp3"]["meta_url"]).json()
    assert [c["title"] for c in meta["chapters"]] == ["Primera parte", "Segunda parte"]
    res = client.get(books["externo.mp3"]["download_url"])
    assert res.status_code == 200 and res.headers["content-type"] == "audio/mpeg"
