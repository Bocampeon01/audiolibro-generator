# Memory

Bitacora de decisiones y avances del proyecto. Actualizar cada sesion relevante.

## 2026-09-23
- Proyecto creado. Repo GitHub `audiolibro-generator` (privado) bajo cuenta Bocampeon01.
- Definido alcance fase 1: PDF/DOC/TXT -> audiolibro en espanol o ingles, formato M4B (capitulos embebidos) como default.
- Fase 2 planeada: app Android reproductora.
- Decidido: TTS local con Piper, fase 1 arranca como CLI (no web/desktop todavia), Android con Flutter.
- Pipeline CLI implementado y probado end-to-end (extract -> detect_lang -> chapters -> Piper TTS -> M4B). Funciona en es y en con muestras de prueba. Ver `context.md` para detalle de modulos y pendientes.
- Voces Piper descargadas: `es_ES-davefx-medium`, `en_US-lessac-medium` (en `voices/`, no versionadas por tamano).

## 2026-09-23 (continuacion) — Web app + Android app
- Web app (FastAPI + frontend vanilla) implementada en `web/`: subis PDF/DOCX/TXT, barra de progreso en tiempo real, biblioteca con descarga. Probada end-to-end, funciona perfecto. Se corre con `python -m uvicorn web.backend.main:app` (o via `.claude/launch.json` config `audiolibro-web`).
- `build_m4b.py` ahora genera un sidecar `<libro>.m4b.chapters.json` (titulo + capitulos con start/end ms) al lado del M4B — lo usa la app Android para mostrar capitulos sin tener que parsear atomos MP4.
- App Android (Flutter) creada en `android_app/`: pantalla de biblioteca local, importar .m4b via file picker, descargar libros desde el servidor web (URL configurable, default `10.0.2.2:8000` para emulador), reproductor con resume de posicion (shared_preferences), velocidad variable, capitulos, skip 10s/30s. `flutter analyze` sin errores.
- **Bloqueante grave: no se puede compilar el APK en esta PC con Flutter/Gradle de Windows.** Error: `java.io.IOException: Unable to establish loopback connection` / `UnixDomainSockets.connect... Invalid argument`. Diagnosticado a fondo: es un bug de AF_UNIX sockets roto a nivel Windows en esta maquina (build 10.0.26200, canal Insider/Canary) — confirmado con Java puro (TCP loopback anda, AF_UNIX no) en 3 versiones de JDK distintas (17.0.10, 17.0.20, 25). Se descarto: vEthernet (Default Switch) deshabilitado, antivirus de terceros (no hay, solo Defender), `netsh winsock reset` + reboot (tampoco arreglo).
- **Solucion que funciono: compilar el APK desde dentro de WSL2** (Ubuntu 26.04 instalado), que corre su propio kernel Linux y no sufre el bug de AF_UNIX de Windows. Setup: JDK 17 instalado en WSL (`apt install openjdk-17-jdk-headless`, corrido como root via `wsl -u root` para evitar pedir password interactivo), Android SDK reutilizado desde Windows via `/mnt/c/Android/Sdk` (con `ANDROID_HOME`/`ANDROID_SDK_ROOT` apuntando ahi), proyecto Flutter copiado a filesystem nativo de WSL (`~/audiolibro/android_app`, NO en `/mnt/d/...` — sockets Unix no andan bien sobre NTFS/DrvFs). Flutter de Windows (`/mnt/c/src/flutter`) no sirve desde WSL por line-endings CRLF en los scripts .sh; hubo que instalar un Flutter Linux nativo separado en `~/flutter` dentro de WSL.
- Repo GitHub actualizado con web app + Android app (falta confirmar commit/push de esta sesion, ver git log).
