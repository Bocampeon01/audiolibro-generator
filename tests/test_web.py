import pytest
from fastapi.testclient import TestClient

from web.backend import main


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(main, "UPLOADS_DIR", tmp_path / "uploads")
    monkeypatch.setattr(main, "OUTPUT_DIR", tmp_path / "output")
    (tmp_path / "output").mkdir()
    submitted = []
    monkeypatch.setattr(main.executor, "submit", lambda *args: submitted.append(args))
    c = TestClient(main.app)
    c.submitted = submitted
    return c


def test_upload_name_with_traversal_stays_inside_uploads(client, tmp_path):
    res = client.post(
        "/api/generate",
        files={"file": ("..\\..\\..\\evil.txt", b"Hola mundo.", "text/plain")},
    )
    assert res.status_code == 200
    _, input_path, out_path, *_ = client.submitted[0][1:]
    assert input_path.parent.parent == tmp_path / "uploads"
    assert input_path.name == "input.txt"
    assert out_path.parent == tmp_path / "output"
    assert not (tmp_path / "evil.txt").exists()


def test_rejects_unknown_voice_and_lang(client):
    f = {"file": ("a.txt", b"Hola.", "text/plain")}
    assert client.post("/api/generate", files=f, data={"voice": "..\\x"}).status_code == 400
    assert client.post("/api/generate", files=f, data={"lang": "xx"}).status_code == 400
    assert client.post("/api/generate", files=f, data={"lang": "es", "voice": "es_ES-davefx-medium"}).status_code == 200


def test_rejects_unsupported_extension(client):
    res = client.post("/api/generate", files={"file": ("a.exe", b"MZ", "application/octet-stream")})
    assert res.status_code == 400


def test_library_download_blocks_traversal(client, tmp_path):
    (tmp_path / "secret.m4b").write_bytes(b"x")
    assert client.get("/api/library/..%5Csecret.m4b").status_code == 404
    assert client.get("/api/library/..%5Csecret.m4b/meta").status_code == 404


def test_library_urls_are_encoded(client, tmp_path):
    (tmp_path / "output" / "Mi libro #1-abc.m4b").write_bytes(b"x")
    book = client.get("/api/library").json()[0]
    assert book["download_url"] == "/api/library/Mi%20libro%20%231-abc.m4b"
    assert client.get(book["download_url"]).status_code == 200
