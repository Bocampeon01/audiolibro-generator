class Sentence {
  final String text;
  final Duration start;
  final Duration end;

  const Sentence({required this.text, required this.start, required this.end});

  factory Sentence.fromJson(Map<String, dynamic> json) {
    return Sentence(
      text: json['text'] as String,
      start: Duration(milliseconds: json['start_ms'] as int),
      end: Duration(milliseconds: json['end_ms'] as int),
    );
  }
}
