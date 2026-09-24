import 'dart:convert';
import 'dart:io';

import 'package:audiolibro_player/services/mp4_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // sample.m4b lo genera el pipeline Python; sample.expected.json es su sidecar.
  test('lee capitulos y oraciones embebidos en el M4B', () async {
    final json = await Mp4Metadata.readSyncJson(File('test/fixtures/sample.m4b'));
    final expected = File('test/fixtures/sample.expected.json').readAsStringSync();
    expect(jsonDecode(json!), jsonDecode(expected));
    final sentences = (jsonDecode(json)['sentences'] as List).map((s) => s['text']).toList();
    expect(sentences, contains('—¿Funciona? —preguntó Ángel.'));
  });

  test('archivo que no es MP4 devuelve null', () async {
    final tmp = File('${Directory.systemTemp.path}/no_mp4.m4b')..writeAsStringSync('hola');
    expect(await Mp4Metadata.readSyncJson(tmp), isNull);
  });
}
