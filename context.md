# Audiolibro Generator — Contexto del Proyecto

## Objetivo
App que convierte documentos (PDF, DOC/DOCX, TXT) en audiolibros usando TTS (text-to-speech), y una app Android para reproducirlos.

## Alcance fase 1 (idiomas)
- Detectar idioma del documento fuente automaticamente.
- Soportados: **español, ingles, portugues (BR), frances, italiano, aleman**.
- 2 voces por idioma para elegir (ver `src/audiolibro/detect_lang.py::VOICES`). Agregar idioma nuevo = agregar entradas ahi + bajar los modelos Piper correspondientes.

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
- Motor TTS: **Piper** (local/offline, gratis). 2 voces por idioma (`detect_lang.VOICES`), elegibles en la web y por CLI (`--voice`).
- Fase 1: primero validar el pipeline de generacion (CLI/script), recien despues decidir si se envuelve en web app o app de escritorio.
- Android (fase 2): arrancar con **Flutter**, evaluar despues si conviene pasar a nativo.
- Formato salida: **M4B** con capitulos embebidos via ffmpeg (confirmado funcionando).
- Sincronizacion de texto: por **oracion** (no por palabra) — se sintetiza cada oracion por separado y se mide su duracion real, no se usa alineacion fonema-por-fonema de Piper (mas fragil).

## Estado actual (implementado)
Pipeline CLI funcional en `src/audiolibro/`:
- `extract.py` — texto desde PDF (pypdf) / DOCX (python-docx) / TXT. OCR para PDF escaneado: pendiente.
- `detect_lang.py` — deteccion de idioma (langdetect) + catalogo de voces Piper por idioma (`VOICES`).
- `chapters.py` — segmentacion en capitulos (detecta "Capitulo/Chapter/Chapitre/Capitolo/Kapitel/Parte N", fallback por longitud).
- `sentences.py` — segmentacion en oraciones (regex sobre puntuacion latina, con corte de emergencia para oraciones muy largas).
- `wav_utils.py` — concatenar wavs (copia de frames PCM, sin reencode) y medir duracion.
- `tts_piper.py` — sintesis de audio offline con Piper, una llamada por oracion.
- `build_m4b.py` — concatena oraciones en wav de capitulo, capitulos en M4B (ffmpeg), y escribe el sidecar `<libro>.m4b.chapters.json` con `{title, chapters, sentences}` (sentences en tiempo absoluto del libro, con el texto de cada una — para el "seguir texto" de la app).
- `pipeline.py` — CLI: `python -m audiolibro.pipeline entrada.pdf --out output/libro.m4b [--lang es] [--voice es_AR-daniela-high]`

Probado end-to-end en es/en/fr con voces variadas, sidecar de oraciones verificado (offsets correctos entre capitulos). Voces (~60-100MB c/u) en `voices/`, no versionadas (`.gitignore`).

### App Android — texto sincronizado
`PlayerScreen` tiene un boton (icono de articulo, arriba a la derecha, solo visible si el libro tiene `sentences`) que muestra un panel de texto scrolleable con la oracion actual resaltada, sincronizada con `positionStream` del reproductor. Tocar una oracion salta el audio a ese punto. Probado en emulador: el resaltado avanza en tiempo real con el audio.

## Como correr y probar

### Web (generador)
Doble click en `iniciar_web.bat` (o `.venv\Scripts\python -m uvicorn web.backend.main:app --host 0.0.0.0 --port 8000`).
Abre http://localhost:8000. La pagina muestra la URL para el celular (IP de la PC en la red, ej `http://192.168.0.217:8000`). `--host 0.0.0.0` es obligatorio para que un celular real conecte; Windows pide permiso de firewall la primera vez (aceptar "Redes privadas").

### Tests
- Python: `.venv\Scripts\python -m pytest tests` (texto, capitulos, encoding, seguridad de la web, integracion completa Piper+ffmpeg).
- Flutter (en WSL): `flutter test` (parser MP4 contra `test/fixtures/sample.m4b` generado por el pipeline, smoke test).

### Formato del M4B generado
M4B estandar (AAC + capitulos embebidos, abre en cualquier reproductor). Ademas lleva en el tag `lyrics` (atom `©lyr`) un JSON `{title, chapters, sentences}` con el texto y tiempos de cada oracion: la app lo lee al importar, asi un `.m4b` mandado solo por WhatsApp/Drive conserva capitulos y texto sincronizado. El `.chapters.json` de al lado es el mismo JSON (lo usa el servidor para `/meta`).

### App Android (reproductor)
Codigo en `android_app/`. En esta PC el build de Gradle desde Windows esta roto (bug de sockets AF_UNIX del propio Windows, no relacionado al proyecto — ver Memory.md). Mientras no se resuelva:
- Build desde WSL2 (ver receta completa en Memory.md, seccion "RESUELTO").
- APK debug ya compilado y probado en emulador (`android14`): conecta al servidor web (poner la URL, `10.0.2.2:8000` en emulador o la IP LAN de la PC en celular fisico), descarga el libro, reproduce con capitulos/resume/velocidad.
- Tambien se puede importar un `.m4b` directo con el boton "Importar" (file picker), sin pasar por el servidor.

### App Android — reproduccion en segundo plano
`just_audio_background`: sigue sonando con pantalla apagada o en otra app, notificacion con controles, teclas multimedia/auriculares. El reproductor esta atado a la pantalla del libro: volver a la biblioteca corta el audio (ver pendientes: mini-player).

## Pendiente / siguientes pasos
- [ ] Mini-player persistente (seguir escuchando mientras se navega la biblioteca).
- [ ] Sleep timer (apagar en X minutos / al terminar capitulo).
- [ ] Si se sale de la pantalla "Generar" a mitad, el libro queda en el servidor pero no se baja solo (se puede bajar desde "Descargar").
- [ ] Capitulos con numero en palabras ("Capitulo primero") no se detectan: caen al corte por longitud.
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
