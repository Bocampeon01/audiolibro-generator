import 'dart:convert';
import 'dart:io';

import 'chapter.dart';

class Book {
  final String filePath;
  final String title;
  final List<Chapter> chapters;

  const Book({required this.filePath, required this.title, required this.chapters});

  String get id => filePath;

  static Future<Book> fromFile(File file) async {
    final sidecar = File('${file.path}.chapters.json');
    var title = file.uri.pathSegments.last.replaceAll('.m4b', '');
    var chapters = <Chapter>[];

    if (await sidecar.exists()) {
      try {
        final data = jsonDecode(await sidecar.readAsString()) as Map<String, dynamic>;
        title = (data['title'] as String?) ?? title;
        chapters = (data['chapters'] as List<dynamic>? ?? [])
            .map((c) => Chapter.fromJson(c as Map<String, dynamic>))
            .toList();
      } catch (_) {
        // sidecar corrupto o ausente: seguimos sin capitulos
      }
    }

    return Book(filePath: file.path, title: title, chapters: chapters);
  }
}
