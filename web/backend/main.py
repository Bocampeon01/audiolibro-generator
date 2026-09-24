"""Backend web: subis un documento, generamos el audiolibro M4B."""
import json
import re
import shutil
import socket
import sys
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path, PureWindowsPath
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "src"))

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from audiolibro import audio_meta, detect_lang, pipeline

UPLOADS_DIR = ROOT / "web" / "uploads"
OUTPUT_DIR = ROOT / "output"
FRONTEND_DIR = ROOT / "web" / "frontend"

META_CACHE_DIR = ROOT / "web" / "cache" / "meta"

UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
META_CACHE_DIR.mkdir(parents=True, exist_ok=True)

ALLOWED_SUFFIXES = (".pdf", ".docx", ".txt")

app = FastAPI(title="Audiolibro Generator")

jobs: dict[str, dict] = {}
jobs_lock = threading.Lock()
# Un solo worker: los pedidos concurrentes (web + celular) quedan "En cola..." en vez
# de sintetizar en paralelo y competir por CPU.
executor = ThreadPoolExecutor(max_workers=1)


def _update_job(job_id: str, **fields) -> None:
    with jobs_lock:
        jobs[job_id].update(fields)


def _safe_stem(filename: str) -> str:
    # PureWindowsPath corta por "/" y por "\", sea cual sea el SO del cliente.
    stem = PureWindowsPath(filename).stem
    stem = re.sub(r'[<>:"/\\|?*\x00-\x1f#%]', "", stem).strip(" .")
    return stem[:80] or "audiolibro"


def _library_file(filename: str) -> Path:
    # Solo archivos directamente dentro de OUTPUT_DIR: nada de "..\" ni subcarpetas.
    if filename != PureWindowsPath(filename).name or filename in ("", ".", ".."):
        raise HTTPException(404, "No encontrado")
    return OUTPUT_DIR / filename


def _run_job(
    job_id: str, input_path: Path, out_path: Path, lang: str | None, voice_id: str | None, title: str
) -> None:
    def on_progress(stage: str, step: int, total: int) -> None:
        _update_job(job_id, stage=stage, step=step, total=total)

    try:
        _update_job(job_id, status="running")
        pipeline.run(
            input_path, out_path, lang, voice_id,
            keep_temp=False, on_progress=on_progress, title=title,
        )
        _update_job(job_id, status="done", stage="Listo", step=5, total=5)
    except Exception as exc:  # noqa: BLE001 - reportar cualquier fallo al cliente
        _update_job(job_id, status="error", error=str(exc))
    finally:
        shutil.rmtree(input_path.parent, ignore_errors=True)


def _lan_ip() -> str | None:
    # UDP connect no manda paquetes: solo resuelve que interfaz usaria el SO.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
        except OSError:
            return None


@app.get("/api/server-info")
def server_info(request: Request):
    ip = _lan_ip()
    port = request.url.port or 8000
    return {"phone_url": f"http://{ip}:{port}" if ip else None, "library_dir": str(OUTPUT_DIR)}


@app.get("/api/voices")
def voices():
    return {"languages": detect_lang.LANG_NAMES, "voices": detect_lang.VOICES}


@app.post("/api/generate")
async def generate(file: UploadFile = File(...), lang: str = Form("auto"), voice: str = Form("")):
    original_name = file.filename or ""
    suffix = PureWindowsPath(original_name).suffix.lower()
    if suffix not in ALLOWED_SUFFIXES:
        raise HTTPException(400, f"Formato no soportado: {suffix or '(sin extension)'}")
    if lang != "auto" and lang not in detect_lang.SUPPORTED_LANGS:
        raise HTTPException(400, f"Idioma no soportado: {lang}")
    if voice and voice not in detect_lang.all_voice_ids():
        raise HTTPException(400, f"Voz desconocida: {voice}")

    job_id = uuid.uuid4().hex[:12]
    job_upload_dir = UPLOADS_DIR / job_id
    job_upload_dir.mkdir(parents=True, exist_ok=True)
    # Nunca usar el nombre que manda el cliente como ruta en disco.
    input_path = job_upload_dir / f"input{suffix}"
    input_path.write_bytes(await file.read())

    title = _safe_stem(original_name)
    out_path = OUTPUT_DIR / f"{title}-{job_id}.m4b"

    with jobs_lock:
        jobs[job_id] = {
            "status": "queued",
            "stage": "En cola...",
            "step": 0,
            "total": 5,
            "filename": original_name,
            "out_name": out_path.name,
        }

    executor.submit(
        _run_job, job_id, input_path, out_path,
        None if lang == "auto" else lang, voice or None, title,
    )
    return {"job_id": job_id}


@app.get("/api/jobs/{job_id}")
def job_status(job_id: str):
    with jobs_lock:
        job = jobs.get(job_id)
    if job is None:
        raise HTTPException(404, "Job no encontrado")
    return job


@app.get("/api/jobs/{job_id}/download")
def job_download(job_id: str):
    with jobs_lock:
        job = jobs.get(job_id)
    if job is None or job.get("status") != "done":
        raise HTTPException(404, "Audiolibro no disponible todavia")
    out_path = OUTPUT_DIR / job["out_name"]
    if not out_path.exists():
        raise HTTPException(404, "Archivo no encontrado")
    return FileResponse(out_path, media_type="audio/mp4", filename=out_path.name)


def _book_meta(path: Path) -> dict:
    """Metadata del libro: el .chapters.json de los libros generados aca; para los que el
    usuario copio a mano (bajados de internet) se lee con ffprobe y se cachea FUERA de su
    carpeta, para no llenarsela de archivos extra."""
    sidecar = path.with_suffix(path.suffix + ".chapters.json")
    if sidecar.exists():
        return json.loads(sidecar.read_text(encoding="utf-8"))

    stat = path.stat()
    cache = META_CACHE_DIR / f"{path.name}.json"
    if cache.exists():
        cached = json.loads(cache.read_text(encoding="utf-8"))
        if cached.get("mtime") == stat.st_mtime and cached.get("size") == stat.st_size:
            return cached["meta"]

    meta = audio_meta.probe(path)
    if meta is None:  # no se cachea: puede ser un archivo que se esta copiando
        return {"title": path.stem, "chapters": [], "sentences": []}
    cache.write_text(
        json.dumps({"mtime": stat.st_mtime, "size": stat.st_size, "meta": meta}, ensure_ascii=False),
        encoding="utf-8",
    )
    return meta


def _library_books() -> list[Path]:
    files = [p for p in OUTPUT_DIR.iterdir() if p.is_file() and p.suffix.lower() in audio_meta.AUDIO_TYPES]
    return sorted(files, key=lambda p: p.stat().st_mtime, reverse=True)


@app.get("/api/library")
def library():
    books = []
    for path in _library_books():
        meta = _book_meta(path)
        url_name = quote(path.name)
        books.append({
            "name": path.name,
            "title": meta.get("title") or path.stem,
            "size_mb": round(path.stat().st_size / (1024 * 1024), 1),
            "download_url": f"/api/library/{url_name}",
            "meta_url": f"/api/library/{url_name}/meta",
            "chapters_count": len(meta.get("chapters", [])),
        })
    return books


@app.get("/api/library/{filename}")
def library_download(filename: str):
    out_path = _library_file(filename)
    media_type = audio_meta.AUDIO_TYPES.get(out_path.suffix.lower())
    if media_type is None or not out_path.exists():
        raise HTTPException(404, "No encontrado")
    return FileResponse(out_path, media_type=media_type, filename=filename)


@app.get("/api/library/{filename}/meta")
def library_meta(filename: str):
    out_path = _library_file(filename)
    if out_path.suffix.lower() not in audio_meta.AUDIO_TYPES or not out_path.exists():
        raise HTTPException(404, "No hay metadata para este libro")
    return _book_meta(out_path)


app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="frontend")
