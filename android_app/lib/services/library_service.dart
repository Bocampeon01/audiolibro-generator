import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/book.dart';

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
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.m4b'))
        .toList();
    final books = <Book>[];
    for (final file in files) {
      books.add(await Book.fromFile(file));
    }
    return books;
  }

  Future<Book?> importFromPicker() async {
    // FileType.any (en vez de custom+allowedExtensions): algunos proveedores
    // (WhatsApp, Drive) no reportan bien la extension/MIME de un .m4b y el
    // filtro estricto los deja afuera del selector. Validamos nosotros.
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.single.path == null) return null;

    final source = File(result.files.single.path!);
    if (!source.path.toLowerCase().endsWith('.m4b')) {
      throw Exception('Elegiste "${source.uri.pathSegments.last}", que no es un .m4b');
    }

    final dir = await libraryDir();
    final destPath = '${dir.path}/${source.uri.pathSegments.last}';
    final dest = await source.copy(destPath);

    // copiar sidecar de capitulos si esta al lado del original
    final sourceSidecar = File('${source.path}.chapters.json');
    if (await sourceSidecar.exists()) {
      await sourceSidecar.copy('$destPath.chapters.json');
    }

    return Book.fromFile(dest);
  }

  Future<List<ServerBook>> fetchServerLibrary(String baseUrl) async {
    final res = await http.get(Uri.parse('$baseUrl/api/library'));
    if (res.statusCode != 200) {
      throw Exception('Servidor respondio ${res.statusCode}');
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    return list.map((e) => ServerBook.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Book> downloadFromServer(String baseUrl, ServerBook item) async {
    final dir = await libraryDir();
    final destPath = '${dir.path}/${item.name}';

    final res = await http.get(Uri.parse('$baseUrl${item.downloadUrl}'));
    if (res.statusCode != 200) {
      throw Exception('No se pudo descargar (${res.statusCode})');
    }
    final dest = File(destPath);
    await dest.writeAsBytes(res.bodyBytes);

    final metaRes = await http.get(Uri.parse('$baseUrl${item.metaUrl}'));
    if (metaRes.statusCode == 200) {
      final sidecar = File('$destPath.chapters.json');
      await sidecar.writeAsString(metaRes.body);
    }

    return Book.fromFile(dest);
  }

  Future<void> deleteBook(Book book) async {
    final file = File(book.filePath);
    final sidecar = File('${book.filePath}.chapters.json');
    if (await file.exists()) await file.delete();
    if (await sidecar.exists()) await sidecar.delete();
  }
}
