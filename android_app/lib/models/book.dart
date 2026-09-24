import 'dart:convert';
import 'dart:io';

import 'chapter.dart';
import 'sentence.dart';

class Book {
  final String filePath;
  final String title;
  final List<Chapter> chapters;
  final List<Sentence> sentences;

  const Book({
    required this.filePath,
    required this.title,
    required this.chapters,
    required this.sentences,
  });

  String get id => filePath;

  Chapter? chapterAt(Duration position) {
    for (final ch in chapters) {
      if (position >= ch.start && position < ch.end) return ch;
    }
    return null;
  }

  static Future<Book> fromFile(File file) async {
    final sidecar = File('${file.path}.chapters.json');
    var title = Uri.decodeComponent(file.uri.pathSegments.last)
        .replaceFirst(RegExp(r'\.[^.]+$'), '');
    var chapters = <Chapter>[];
    var sentences = <Sentence>[];

    if (await sidecar.exists()) {
      try {
        final data =
            jsonDecode(await sidecar.readAsString()) as Map<String, dynamic>;
        title = (data['title'] as String?) ?? title;
        chapters = (data['chapters'] as List<dynamic>? ?? [])
            .map((c) => Chapter.fromJson(c as Map<String, dynamic>))
            .toList();
        sentences = (data['sentences'] as List<dynamic>? ?? [])
            .map((s) => Sentence.fromJson(s as Map<String, dynamic>))
            .toList();
      } catch (_) {
        // sidecar corrupto o ausente: seguimos sin capitulos/texto
      }
    }

    return Book(
      filePath: file.path,
      title: title,
      chapters: chapters,
      sentences: sentences,
    );
  }
}
