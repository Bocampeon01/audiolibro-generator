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

## Decisiones pendientes (a resolver con el usuario)
- [ ] Motor TTS: cloud (Google Cloud TTS, Azure, ElevenLabs, Amazon Polly — mejor calidad, requiere API key/costo) vs local/offline (Coqui TTS, Piper — gratis, offline, calidad variable).
- [ ] Plataforma de la app generadora fase 1: script/CLI, app de escritorio, o web app.
- [ ] Stack Android: Kotlin nativo (Media3/ExoPlayer) vs Flutter (dart-flutter skills disponibles en este entorno).
- [ ] Hosting/distribucion de audiolibros generados (local only vs cloud storage).

## Repo
- GitHub: Bocampeon01/audiolibro-generator (privado)
- Working dir local: `D:\Audio Libro`
