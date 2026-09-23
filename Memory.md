# Memory

Bitacora de decisiones y avances del proyecto. Actualizar cada sesion relevante.

## 2026-09-23
- Proyecto creado. Repo GitHub `audiolibro-generator` (privado) bajo cuenta Bocampeon01.
- Definido alcance fase 1: PDF/DOC/TXT -> audiolibro en espanol o ingles, formato M4B (capitulos embebidos) como default.
- Fase 2 planeada: app Android reproductora.
- Decidido: TTS local con Piper, fase 1 arranca como CLI (no web/desktop todavia), Android con Flutter.
- Pipeline CLI implementado y probado end-to-end (extract -> detect_lang -> chapters -> Piper TTS -> M4B). Funciona en es y en con muestras de prueba. Ver `context.md` para detalle de modulos y pendientes.
- Voces Piper descargadas: `es_ES-davefx-medium`, `en_US-lessac-medium` (en `voices/`, no versionadas por tamano).
