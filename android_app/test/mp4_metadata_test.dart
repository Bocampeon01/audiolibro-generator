import 'dart:convert';
import 'dart:io';

import 'package:audiolibro_player/services/mp4_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // sample.m4b lo genera el pipeline Python; sample.expected.json es su sidecar.
  test('lee capitulos y oraciones embebidos en el M4B', () async {
    final json = await Mp4Metadata.readSyncJson(
      File('test/fixtures/sample.m4b'),
    );
    final expected = File('test/fixtures/sample.expected.json')
        .readAsStringSync();
    expect(jsonDecode(json!), jsonDecode(expected));
    final sentences = (jsonDecode(json)['sentences'] as List)
        .map((s) => s['text'])
        .toList();
    expect(sentences, contains('—¿Funciona? —preguntó Ángel.'));
  });

  test('archivo que no es MP4 devuelve null', () async {
    final tmp = File('${Directory.systemTemp.path}/no_mp4.m4b')
      ..writeAsStringSync('hola');
    expect(await Mp4Metadata.readSyncJson(tmp), isNull);
    expect(await Mp4Metadata.readBookMeta(tmp), isNull);
  });

  test(
    'libro propio: readBookMeta devuelve el JSON embebido con oraciones',
    () async {
      final meta = await Mp4Metadata.readBookMeta(
        File('test/fixtures/sample.m4b'),
      );
      expect((meta!['sentences'] as List), isNotEmpty);
    },
  );

  // external.m4b: hecho con ffmpeg sin nuestro JSON, como un audiolibro bajado de internet.
  test('libro externo: titulo (©nam) y capitulos Nero (chpl)', () async {
    final meta = await Mp4Metadata.readBookMeta(
      File('test/fixtures/external.m4b'),
    );
    expect(meta!['title'], 'Libro Externo');
    expect(meta['sentences'], isEmpty);
    final chapters = meta['chapters'] as List;
    expect(chapters.map((c) => c['title']), ['Primera parte', 'Segunda parte']);
    expect(chapters[0]['start_ms'], 0);
    expect(chapters[1]['start_ms'], 1500);
    expect((chapters[1]['end_ms'] as int), closeTo(3000, 100));
  });

  // external_qt.m4b: el mismo libro sin chpl, solo la pista de capitulos QuickTime,
  // que es como vienen los LibriVox.
  test('libro externo: capitulos de la pista QuickTime', () async {
    final meta = await Mp4Metadata.readBookMeta(
      File('test/fixtures/external_qt.m4b'),
    );
    expect(meta!['title'], 'Libro Externo');
    final chapters = meta['chapters'] as List;
    expect(chapters.map((c) => c['title']), ['Primera parte', 'Segunda parte']);
    expect(chapters[1]['start_ms'], 1500);
    expect((chapters[1]['end_ms'] as int), closeTo(3000, 100));
  });
}
