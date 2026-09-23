# Audiolibro Generator — Contexto del Proyecto

## Objetivo
App que convierte documentos (PDF, DOC/DOCX, TXT) en audiolibros usando TTS (text-to-speech), y una app Android para reproducirlos.

## Alcance fase 1 (idiomas)
- Detectar idioma del documento fuente automaticamente.
- Soporte inicial: **español** e **ingles**.
- Arquitectura pensada para agregar 1 idioma nuevo por vez (no acoplar pipeline a 2 idiomas fijos).

## Pipeline (generacion)
1. Ingesta: PDF / DOC / DOCX / TXT.
2. Extraccion de texto (OCR fallback si PDF es escaneado).
3. Deteccion de idioma.
4. Segmentacion en capitulos/parrafos (usar estructura del documento si existe: titulos, saltos de pagina).
5. TTS por idioma (motor a definir — ver "Decisiones pendientes").
6. Empaquetado en formato audiolibro estandar (ver abajo).

## Formato de salida
Usar estandar existente en lo posible en vez de formato propio. Candidatos:
- **M4B** (audio AAC + capitulos + metadata + portada) — formato de facto mas soportado por reproductores de audiolibros (incluye Android: Smart AudioBook Player, Voice, etc).
- Alternativa simple: MP3 + ID3 chapters, si M4B complica el encoding.

Decision default: **M4B con capitulos embebidos**, fallback MP3+ID3 si hay problemas de tooling.

## App Android (fase 2)
- Reproductor de audiolibros: abre el M4B/MP3 generado.
- Features esperables de un audiobook player: velocidad de reproduccion, marcador de posicion (resume), saltos por capitulo, sleep timer.
- Evaluar: reproductor propio (Kotlin + Media3/ExoPlayer, que soporta M4B y capitulos) vs. simplemente generar el archivo y que el usuario use un player existente (mas rapido, menos control de UX).

## Decisiones tomadas
- Motor TTS: **Piper** (local/offline, gratis). Voces: `es_ES-davefx-medium`, `en_US-lessac-medium`.
- Fase 1: primero validar el pipeline de generacion (CLI/script), recien despues decidir si se envuelve en web app o app de escritorio.
- Android (fase 2): arrancar con **Flutter**, evaluar despues si conviene pasar a nativo.
- Formato salida: **M4B** con capitulos embebidos via ffmpeg (confirmado funcionando).

## Estado actual (implementado)
Pipeline CLI funcional en `src/audiolibro/`:
- `extract.py` — texto desde PDF (pypdf) / DOCX (python-docx) / TXT. OCR para PDF escaneado: pendiente.
- `detect_lang.py` — deteccion de idioma (langdetect), soporta es/en, mapea a voz Piper.
- `chapters.py` — segmentacion en capitulos (detecta "Capitulo/Chapter/Parte N", fallback por longitud).
- `tts_piper.py` — sintesis de audio offline con Piper.
- `build_m4b.py` — empaqueta wavs de capitulos en un M4B con capitulos embebidos (ffmpeg).
- `pipeline.py` — CLI: `python -m audiolibro.pipeline entrada.pdf --out output/libro.m4b`

Probado end-to-end con muestras es/en (`samples/`), capitulos verificados con ffprobe. Voces (~60MB c/u) en `voices/`, no versionadas (`.gitignore`).

## Como correr y probar

### Web (generador)
```
.venv\Scripts\python -m uvicorn web.backend.main:app --host 127.0.0.1 --port 8000
```
Abrir http://localhost:8000, subir PDF/DOCX/TXT, esperar generacion, descargar M4B. Biblioteca de libros generados visible en la misma pagina.

### App Android (reproductor)
Codigo en `android_app/`. En esta PC el build de Gradle desde Windows esta roto (bug de sockets AF_UNIX del propio Windows, no relacionado al proyecto — ver Memory.md). Mientras no se resuelva:
- Build desde WSL2 (ver receta completa en Memory.md, seccion "RESUELTO").
- APK debug ya compilado y probado en emulador (`android14`): conecta al servidor web (poner la URL, `10.0.2.2:8000` en emulador o la IP LAN de la PC en celular fisico), descarga el libro, reproduce con capitulos/resume/velocidad.
- Tambien se puede importar un `.m4b` directo con el boton "Importar" (file picker), sin pasar por el servidor.

## Pendiente / siguientes pasos
- [ ] OCR fallback para PDFs escaneados.
- [ ] Portada / metadata (autor, titulo) embebida en el M4B.
- [ ] Probar con documento largo real (libro completo, no solo texto de prueba).
- [ ] Evaluar calidad de voz Piper vs alternativas si hace falta mas naturalidad.
- [ ] Envolver el pipeline en web app / desktop una vez validado con documentos reales.
- [ ] App Android (Flutter) para reproducir M4B.
- [ ] Hosting/distribucion de audiolibros generados (local only vs cloud storage) — sin decidir.

## Repo
- GitHub: Bocampeon01/audiolibro-generator (privado)
- Working dir local: `D:\Audio Libro`
- Entorno: venv Python 3.14 en `.venv/`, dependencias en `requirements.txt`
