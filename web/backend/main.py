"""Backend web: subis un documento, generamos el audiolibro M4B."""
import json
import shutil
import sys
import threading
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "src"))

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from audiolibro import detect_lang, pipeline

UPLOADS_DIR = ROOT / "web" / "uploads"
OUTPUT_DIR = ROOT / "output"
FRONTEND_DIR = ROOT / "web" / "frontend"

UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Audiolibro Generator")

jobs: dict[str, dict] = {}
jobs_lock = threading.Lock()


def _update_job(job_id: str, **fields) -> None:
    with jobs_lock:
        jobs[job_id].update(fields)


def _run_job(job_id: str, input_path: Path, out_path: Path, lang: str | None, voice_id: str | None) -> None:
    def on_progress(stage: str, step: int, total: int) -> None:
        _update_job(job_id, stage=stage, step=step, total=total)

    try:
        _update_job(job_id, status="running")
        pipeline.run(input_path, out_path, lang, voice_id, keep_temp=False, on_progress=on_progress)
        _update_job(job_id, status="done", stage="Listo", step=5, total=5)
    except Exception as exc:  # noqa: BLE001 - reportar cualquier fallo al cliente
        _update_job(job_id, status="error", error=str(exc))
    finally:
        shutil.rmtree(input_path.parent, ignore_errors=True)


@app.get("/api/voices")
def voices():
    return {"languages": detect_lang.LANG_NAMES, "voices": detect_lang.VOICES}


@app.post("/api/generate")
async def generate(file: UploadFile = File(...), lang: str = Form("auto"), voice: str = Form("")):
    suffix = Path(file.filename).suffix.lower()
    if suffix not in (".pdf", ".docx", ".txt"):
        raise HTTPException(400, f"Formato no soportado: {suffix}")

    job_id = uuid.uuid4().hex[:12]
    job_upload_dir = UPLOADS_DIR / job_id
    job_upload_dir.mkdir(parents=True, exist_ok=True)
    input_path = job_upload_dir / file.filename
    input_path.write_bytes(await file.read())

    stem = Path(file.filename).stem
    out_path = OUTPUT_DIR / f"{stem}-{job_id}.m4b"
    lang_value = None if lang == "auto" else lang
    voice_value = voice or None

    with jobs_lock:
        jobs[job_id] = {
            "status": "queued",
            "stage": "En cola...",
            "step": 0,
            "total": 5,
            "filename": file.filename,
            "out_name": out_path.name,
        }

    thread = threading.Thread(
        target=_run_job, args=(job_id, input_path, out_path, lang_value, voice_value), daemon=True
    )
    thread.start()

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


@app.get("/api/library")
def library():
    books = []
    for path in sorted(OUTPUT_DIR.glob("*.m4b"), key=lambda p: p.stat().st_mtime, reverse=True):
        sidecar = path.with_suffix(path.suffix + ".chapters.json")
        chapters_count = 0
        title = path.stem
        if sidecar.exists():
            data = json.loads(sidecar.read_text(encoding="utf-8"))
            title = data.get("title", title)
            chapters_count = len(data.get("chapters", []))
        books.append({
            "name": path.name,
            "title": title,
            "size_mb": round(path.stat().st_size / (1024 * 1024), 1),
            "download_url": f"/api/library/{path.name}",
            "meta_url": f"/api/library/{path.name}/meta",
            "chapters_count": chapters_count,
        })
    return books


@app.get("/api/library/{filename}")
def library_download(filename: str):
    out_path = OUTPUT_DIR / filename
    if not out_path.exists() or out_path.suffix != ".m4b":
        raise HTTPException(404, "No encontrado")
    return FileResponse(out_path, media_type="audio/mp4", filename=filename)


@app.get("/api/library/{filename}/meta")
def library_meta(filename: str):
    out_path = OUTPUT_DIR / filename
    sidecar = out_path.with_suffix(out_path.suffix + ".chapters.json")
    if not sidecar.exists():
        raise HTTPException(404, "No hay metadata para este libro")
    return json.loads(sidecar.read_text(encoding="utf-8"))


app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="frontend")
