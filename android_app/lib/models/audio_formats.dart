/// Formatos de audiolibro que la app acepta (todos los reproduce ExoPlayer).
/// Coincide con AUDIO_TYPES de src/audiolibro/audio_meta.py.
const audioExtensions = ['m4b', 'm4a', 'mp3', 'aac', 'ogg', 'opus', 'flac'];

String extensionOf(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  return dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
}

bool isSupportedAudio(String path) =>
    audioExtensions.contains(extensionOf(path));

/// M4B/M4A son contenedores MP4: se les puede leer titulo y capitulos (Mp4Metadata).
bool isMp4Audio(String path) =>
    const ['m4b', 'm4a'].contains(extensionOf(path));
