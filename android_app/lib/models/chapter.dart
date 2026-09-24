String chaptersLabel(int count) => count == 1 ? '1 capitulo' : '$count capitulos';

class Chapter {
  final String title;
  final Duration start;
  final Duration end;

  const Chapter({required this.title, required this.start, required this.end});

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      title: json['title'] as String,
      start: Duration(milliseconds: json['start_ms'] as int),
      end: Duration(milliseconds: json['end_ms'] as int),
    );
  }
}
