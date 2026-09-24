import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/book.dart';
import 'mp4_metadata.dart';
import 'playback_position_service.dart';

class ServerBook {
  final String name;
  final String title;
  final double sizeMb;
  final String downloadUrl;
  final String metaUrl;
  final int chaptersCount;

  ServerBook({
    required this.name,
    required this.title,
    required this.sizeMb,
    required this.downloadUrl,
    required this.metaUrl,
    required this.chaptersCount,
  });

  factory ServerBook.fromJson(Map<String, dynamic> json) {
    return ServerBook(
      name: json['name'] as String,
      title: json['title'] as String,
      sizeMb: (json['size_mb'] as num).toDouble(),
      downloadUrl: json['download_url'] as String,
      metaUrl: json['meta_url'] as String,
      chaptersCount: json['chapters_count'] as int? ?? 0,
    );
  }
}

class VoiceOption {
  final String id;
  final String label;

  VoiceOption({required this.id, required this.label});

  factory VoiceOption.fromJson(Map<String, dynamic> json) {
    return VoiceOption(
      id: json['id'] as String,
      label: json['label'] as String,
    );
  }
}

class VoiceCatalog {
  final Map<String, String> languages; // codigo -> nombre
  final Map<String, List<VoiceOption>> voices; // codigo -> voces

  VoiceCatalog({required this.languages, required this.voices});

  factory VoiceCatalog.fromJson(Map<String, dynamic> json) {
    final languages = (json['languages'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, v as String),
    );
    final voices = (json['voices'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(
        k,
        (v as List<dynamic>)
            .map((e) => VoiceOption.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
    );
    return VoiceCatalog(languages: languages, voices: voices);
  }
}

class LibraryService {
  Future<Directory> libraryDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/audiolibros');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<Book>> listBooks() async {
    final dir = await libraryDir();
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.m4b'))
            .toList()
          ..sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
          );
    final books = <Book>[];
    for (final file in files) {
      await _ensureSidecar(file);
      books.add(await Book.fromFile(file));
    }
    return books;
  }

  /// Si el libro no tiene .chapters.json al lado (importado solo, via WhatsApp/Drive),
  /// lo reconstruye desde el JSON embebido en el propio M4B. Se hace una vez: despues
  /// queda cacheado en disco.
  Future<void> _ensureSidecar(File m4b) async {
    final sidecar = File('${m4b.path}.chapters.json');
    if (await sidecar.exists()) return;
    try {
      final json = await Mp4Metadata.readSyncJson(m4b);
      if (json != null) await sidecar.writeAsString(json);
    } catch (_) {
      // archivo no-MP4 o sin metadata: el libro se reproduce igual, sin capitulos
    }
  }

  /// Descarga en streaming a un .part y renombra al final: un libro de cientos de MB
  /// no entra en memoria, y una descarga cortada no deja un .m4b roto en la biblioteca.
  Future<File> _downloadTo(Uri url, String destPath) async {
    final client = http.Client();
    final part = File('$destPath.part');
    try {
      final res = await client.send(http.Request('GET', url));
      if (res.statusCode != 200) {
        throw Exception('No se pudo descargar (${res.statusCode})');
      }
      final sink = part.openWrite();
      try {
        await res.stream.pipe(sink);
      } finally {
        await sink.close();
      }
      return await part.rename(destPath);
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Nombre de archivo que manda el servidor, sin directorios.
  String _safeName(String name) => name.split(RegExp(r'[/\\]')).last;

  Future<Book?> importFromPicker() async {
    // FileType.any (en vez de custom+allowedExtensions): algunos proveedores
    // (WhatsApp, Drive) no reportan bien la extension/MIME de un .m4b y el
    // filtro estricto los deja afuera del selector. Validamos nosotros.
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.single.path == null) return null;

    final source = File(result.files.single.path!);
    if (!source.path.toLowerCase().endsWith('.m4b')) {
      throw Exception(
        'Elegiste "${source.uri.pathSegments.last}", que no es un .m4b',
      );
    }

    final dir = await libraryDir();
    final destPath = '${dir.path}/${source.uri.pathSegments.last}';
    final dest = await source.copy(destPath);
    // file_picker copia el archivo elegido a la cache de la app: se libera, y el
    // .chapters.json de al lado nunca llega (por eso se lee el embebido).
    await FilePicker.platform.clearTemporaryFiles();
    final staleSidecar = File(
      '$destPath.chapters.json',
    ); // de un import previo con mismo nombre
    if (await staleSidecar.exists()) await staleSidecar.delete();
    await _ensureSidecar(dest);

    return Book.fromFile(dest);
  }

  Future<List<ServerBook>> fetchServerLibrary(String baseUrl) async {
    final res = await http.get(Uri.parse('$baseUrl/api/library'));
    if (res.statusCode != 200) {
      throw Exception('Servidor respondio ${res.statusCode}');
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .map((e) => ServerBook.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Book> downloadFromServer(String baseUrl, ServerBook item) async {
    final dir = await libraryDir();
    final destPath = '${dir.path}/${_safeName(item.name)}';
    final dest = await _downloadTo(
      Uri.parse('$baseUrl${item.downloadUrl}'),
      destPath,
    );
    await _saveServerMeta(Uri.parse('$baseUrl${item.metaUrl}'), dest);
    return Book.fromFile(dest);
  }

  /// Metadata del servidor (necesaria para libros generados antes de que el M4B
  /// trajera el JSON embebido); si falla, se usa el embebido.
  Future<void> _saveServerMeta(Uri metaUrl, File m4b) async {
    final sidecar = File('${m4b.path}.chapters.json');
    if (await sidecar.exists()) await sidecar.delete();
    try {
      final res = await http.get(metaUrl);
      if (res.statusCode == 200) {
        await sidecar.writeAsString(res.body);
        return;
      }
    } catch (_) {}
    await _ensureSidecar(m4b);
  }

  Future<VoiceCatalog> fetchVoices(String baseUrl) async {
    final res = await http.get(Uri.parse('$baseUrl/api/voices'));
    if (res.statusCode != 200) {
      throw Exception('Servidor respondio ${res.statusCode}');
    }
    return VoiceCatalog.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Elige un documento (PDF/DOCX/TXT) del celular para mandarlo al servidor
  /// a generar. Igual que importFromPicker: FileType.any + validacion manual,
  /// asi Drive/WhatsApp no quedan afuera por MIME mal reportado.
  Future<File?> pickDocument() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.single.path == null) return null;
    final file = File(result.files.single.path!);
    final ext = file.path.toLowerCase();
    if (!ext.endsWith('.pdf') &&
        !ext.endsWith('.docx') &&
        !ext.endsWith('.txt')) {
      throw Exception(
        'Elegiste "${file.uri.pathSegments.last}", que no es PDF/DOCX/TXT',
      );
    }
    return file;
  }

  Future<String> generateOnServer(
    String baseUrl,
    File file,
    String lang,
    String voice,
  ) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/api/generate'))
          ..fields['lang'] = lang
          ..fields['voice'] = voice
          ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      throw Exception('El servidor rechazo el archivo (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['job_id'] as String;
  }

  Future<Map<String, dynamic>> fetchJobStatus(
    String baseUrl,
    String jobId,
  ) async {
    final res = await http.get(Uri.parse('$baseUrl/api/jobs/$jobId'));
    if (res.statusCode != 200) {
      throw Exception('No se encontro el trabajo en el servidor');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Book> downloadGeneratedJob(
    String baseUrl,
    String jobId,
    String outName,
  ) async {
    final dir = await libraryDir();
    final name = _safeName(outName);
    final dest = await _downloadTo(
      Uri.parse('$baseUrl/api/jobs/${Uri.encodeComponent(jobId)}/download'),
      '${dir.path}/$name',
    );
    await _saveServerMeta(
      Uri.parse('$baseUrl/api/library/${Uri.encodeComponent(name)}/meta'),
      dest,
    );
    return Book.fromFile(dest);
  }

  Future<void> deleteBook(Book book) async {
    final file = File(book.filePath);
    final sidecar = File('${book.filePath}.chapters.json');
    if (await file.exists()) await file.delete();
    if (await sidecar.exists()) await sidecar.delete();
    await PlaybackPositionService().clear(book.id);
  }
}
