import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Metadata de archivos M4B/M4A leida directamente de las cajas MP4.
///
/// - Libros de este proyecto: el generador embebe un JSON (capitulos + oraciones) en el
///   tag "lyrics" (©lyr). Ruta: moov > udta > meta > ilst > ©lyr > data. Misma logica que
///   tests/test_pipeline_integration.py::read_embedded_sync.
/// - Libros de otras herramientas (bajados de internet): titulo en ©nam y capitulos en la
///   caja Nero `chpl` (ffmpeg, mp4v2) o, si no esta, en la pista de capitulos QuickTime
///   (LibriVox, iTunes).
class Mp4Metadata {
  static Future<String?> readSyncJson(File file) async {
    final moov = await _readTopLevelBox(file, 'moov');
    return moov == null ? null : _ilstText(moov, '©lyr');
  }

  /// `{title, chapters, sentences}` listo para guardar como .chapters.json, o null si el
  /// archivo no es MP4 o no trae nada util.
  static Future<Map<String, dynamic>?> readBookMeta(File file) async {
    final moov = await _readTopLevelBox(file, 'moov');
    if (moov == null) return null;

    final lyrics = _ilstText(moov, '©lyr');
    if (lyrics != null && lyrics.trimLeft().startsWith('{')) {
      try {
        final data = jsonDecode(lyrics);
        if (data is Map<String, dynamic> && data['chapters'] is List) {
          return data;
        }
      } catch (_) {
        // "lyrics" con texto comun (no JSON): se sigue con los capitulos estandar
      }
    }

    final title = _ilstText(moov, '©nam');
    var chapters = _neroChapters(moov);
    if (chapters.isEmpty) chapters = await _quickTimeChapters(file, moov);
    if (title == null && chapters.isEmpty) return null;
    return {'title': ?title, 'chapters': chapters, 'sentences': <dynamic>[]};
  }

  static String? _ilstText(Uint8List moov, String key) {
    final meta =
        _child(_child(moov, 'udta') ?? Uint8List(0), 'meta') ??
        _child(moov, 'meta');
    if (meta == null || meta.length < 4) return null;
    final ilst = _child(
      Uint8List.sublistView(meta, 4),
      'ilst',
    ); // meta es full box
    final item = ilst == null ? null : _child(ilst, key);
    final data = item == null ? null : _child(item, 'data');
    if (data == null || data.length < 8) return null;
    return utf8.decode(
      Uint8List.sublistView(data, 8),
      allowMalformed: true,
    ); // 8 = tipo + locale
  }

  /// chpl: version(1) flags(3) [reservado(4) si version 1] cantidad(1), y por capitulo
  /// inicio(8, en unidades de 100 ns) largo(1) titulo(largo).
  static List<Map<String, dynamic>> _neroChapters(Uint8List moov) {
    final chpl = _child(_child(moov, 'udta') ?? Uint8List(0), 'chpl');
    if (chpl == null || chpl.length < 5) return [];
    final bd = ByteData.sublistView(chpl);
    var pos = chpl[0] == 1 ? 8 : 4;
    if (pos >= chpl.length) return [];
    final count = chpl[pos++];
    final starts = <int>[];
    final titles = <String>[];
    for (var i = 0; i < count; i++) {
      if (pos + 9 > chpl.length) break;
      final start100ns = bd.getUint64(pos);
      final len = chpl[pos + 8];
      pos += 9;
      if (pos + len > chpl.length) break;
      starts.add(start100ns ~/ 10000);
      titles.add(
        utf8.decode(chpl.sublist(pos, pos + len), allowMalformed: true),
      );
      pos += len;
    }
    final totalMs = _durationMs(moov);
    return [
      for (var i = 0; i < starts.length; i++)
        {
          'title': titles[i].isEmpty ? 'Capitulo ${i + 1}' : titles[i],
          'start_ms': starts[i],
          'end_ms': i + 1 < starts.length
              ? starts[i + 1]
              : (totalMs ?? starts[i]),
        },
    ];
  }

  /// Pista de capitulos QuickTime (la mas comun: LibriVox, iTunes). La pista de audio
  /// apunta a una pista de texto via tref > chap; cada muestra de esa pista es un
  /// capitulo (2 bytes de largo + titulo) y su tiempo sale de stts.
  static Future<List<Map<String, dynamic>>> _quickTimeChapters(
    File file,
    Uint8List moov,
  ) async {
    final traks = _children(moov, 'trak');
    final chapterIds = <int>{};
    for (final trak in traks) {
      final chap = _child(_child(trak, 'tref') ?? Uint8List(0), 'chap');
      if (chap == null) continue;
      final bd = ByteData.sublistView(chap);
      for (var i = 0; i + 4 <= chap.length; i += 4) {
        chapterIds.add(bd.getUint32(i));
      }
    }
    final trak = traks
        .where((t) => chapterIds.contains(_trackId(t)))
        .firstOrNull;
    final mdia = trak == null ? null : _child(trak, 'mdia');
    final minf = mdia == null ? null : _child(mdia, 'minf');
    final stbl = minf == null ? null : _child(minf, 'stbl');
    final mdhd = mdia == null ? null : _child(mdia, 'mdhd');
    if (stbl == null || mdhd == null) return [];

    final timescale = ByteData.sublistView(mdhd)
        .getUint32(mdhd[0] == 1 ? 20 : 12);
    final starts = _sampleStarts(stbl);
    final offsets = _sampleOffsets(stbl);
    final sizes = _sampleSizes(stbl);
    if (timescale == 0 || starts.isEmpty || offsets.isEmpty) return [];

    final count = [
      starts.length,
      offsets.length,
      sizes.length,
    ].reduce((a, b) => a < b ? a : b);
    final titles = <String>[];
    final raf = await file.open();
    try {
      for (var i = 0; i < count; i++) {
        await raf.setPosition(offsets[i]);
        final sample = await raf.read(sizes[i].clamp(0, 1024));
        titles.add(_chapterText(sample));
      }
    } finally {
      await raf.close();
    }

    final totalMs = _durationMs(moov);
    final startsMs = [
      for (var i = 0; i < count; i++) starts[i] * 1000 ~/ timescale,
    ];
    return [
      for (var i = 0; i < count; i++)
        {
          'title': titles[i].isEmpty ? 'Capitulo ${i + 1}' : titles[i],
          'start_ms': startsMs[i],
          'end_ms': i + 1 < count ? startsMs[i + 1] : (totalMs ?? startsMs[i]),
        },
    ];
  }

  static String _chapterText(Uint8List sample) {
    if (sample.length < 2) return '';
    final len = ByteData.sublistView(sample).getUint16(0);
    final end = (2 + len).clamp(2, sample.length);
    final text = sample.sublist(2, end);
    if (text.length >= 2 && text[0] == 0xFE && text[1] == 0xFF) {
      // UTF-16 BE con BOM (algunas herramientas de Apple)
      final units = [
        for (var i = 2; i + 1 < text.length; i += 2)
          (text[i] << 8) | text[i + 1],
      ];
      return String.fromCharCodes(units).trim();
    }
    return utf8.decode(text, allowMalformed: true).trim();
  }

  static int? _trackId(Uint8List trak) {
    final tkhd = _child(trak, 'tkhd');
    if (tkhd == null) return null;
    final at = tkhd[0] == 1 ? 20 : 12;
    return tkhd.length < at + 4
        ? null
        : ByteData.sublistView(tkhd).getUint32(at);
  }

  /// Inicio de cada muestra (en unidades de timescale), acumulando stts.
  static List<int> _sampleStarts(Uint8List stbl) {
    final stts = _child(stbl, 'stts');
    if (stts == null || stts.length < 8) return [];
    final bd = ByteData.sublistView(stts);
    final entries = bd.getUint32(4);
    final starts = <int>[];
    var t = 0;
    for (var e = 0; e < entries && 8 + e * 8 + 8 <= stts.length; e++) {
      final count = bd.getUint32(8 + e * 8);
      final delta = bd.getUint32(12 + e * 8);
      for (var i = 0; i < count && starts.length < 10000; i++) {
        starts.add(t);
        t += delta;
      }
    }
    return starts;
  }

  static List<int> _sampleSizes(Uint8List stbl) {
    final stsz = _child(stbl, 'stsz');
    if (stsz == null || stsz.length < 12) return [];
    final bd = ByteData.sublistView(stsz);
    final fixed = bd.getUint32(4);
    final count = bd.getUint32(8);
    if (fixed != 0) return List.filled(count, fixed);
    return [
      for (var i = 0; i < count && 12 + i * 4 + 4 <= stsz.length; i++)
        bd.getUint32(12 + i * 4),
    ];
  }

  /// Offset en el archivo de cada muestra: chunks (stco/co64) x muestras por chunk (stsc).
  static List<int> _sampleOffsets(Uint8List stbl) {
    final stco = _child(stbl, 'stco');
    final co64 = _child(stbl, 'co64');
    final stsc = _child(stbl, 'stsc');
    if (stsc == null || stsc.length < 8 || (stco == null && co64 == null)) {
      return [];
    }
    final chunkOffsets = <int>[];
    if (stco != null) {
      final bd = ByteData.sublistView(stco);
      for (
        var i = 0;
        i < bd.getUint32(4) && 8 + i * 4 + 4 <= stco.length;
        i++
      ) {
        chunkOffsets.add(bd.getUint32(8 + i * 4));
      }
    } else {
      final bd = ByteData.sublistView(co64!);
      for (
        var i = 0;
        i < bd.getUint32(4) && 8 + i * 8 + 8 <= co64.length;
        i++
      ) {
        chunkOffsets.add(bd.getUint64(8 + i * 8));
      }
    }
    final sizes = _sampleSizes(stbl);
    final sc = ByteData.sublistView(stsc);
    final runs = sc.getUint32(4);
    final offsets = <int>[];
    var sample = 0;
    for (var r = 0; r < runs && 8 + r * 12 + 12 <= stsc.length; r++) {
      final firstChunk = sc.getUint32(8 + r * 12);
      final perChunk = sc.getUint32(12 + r * 12);
      final nextFirst = r + 1 < runs && 8 + (r + 1) * 12 + 4 <= stsc.length
          ? sc.getUint32(8 + (r + 1) * 12)
          : chunkOffsets.length + 1;
      for (var c = firstChunk; c < nextFirst && c <= chunkOffsets.length; c++) {
        var pos = chunkOffsets[c - 1];
        for (var s = 0; s < perChunk && sample < sizes.length; s++) {
          offsets.add(pos);
          pos += sizes[sample++];
        }
      }
    }
    return offsets;
  }

  static List<Uint8List> _children(Uint8List data, String type) {
    final found = <Uint8List>[];
    final bd = ByteData.sublistView(data);
    var pos = 0;
    while (pos + 8 <= data.length) {
      var size = bd.getUint32(pos);
      var headerLen = 8;
      if (size == 1) {
        if (pos + 16 > data.length) break;
        size = bd.getUint64(pos + 8);
        headerLen = 16;
      } else if (size == 0) {
        size = data.length - pos;
      }
      if (size < headerLen || pos + size > data.length) break;
      if (latin1.decode(data.sublist(pos + 4, pos + 8)) == type) {
        found.add(Uint8List.sublistView(data, pos + headerLen, pos + size));
      }
      pos += size;
    }
    return found;
  }

  static int? _durationMs(Uint8List moov) {
    final mvhd = _child(moov, 'mvhd');
    if (mvhd == null || mvhd.length < 20) return null;
    final bd = ByteData.sublistView(mvhd);
    final v1 = mvhd[0] == 1;
    if (v1 && mvhd.length < 32) return null;
    final timescale = bd.getUint32(v1 ? 20 : 12);
    final duration = v1 ? bd.getUint64(24) : bd.getUint32(16);
    return timescale == 0 ? null : duration * 1000 ~/ timescale;
  }

  /// El moov puede estar al final del archivo (ffmpeg sin faststart): se recorren
  /// headers de cajas top-level sin leer el audio.
  static Future<Uint8List?> _readTopLevelBox(File file, String type) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      var pos = 0;
      while (pos + 8 <= length) {
        await raf.setPosition(pos);
        final header = await raf.read(16);
        if (header.length < 8) return null;
        final bd = ByteData.sublistView(header);
        var size = bd.getUint32(0);
        var headerLen = 8;
        if (size == 1) {
          if (header.length < 16) return null;
          size = bd.getUint64(8);
          headerLen = 16;
        } else if (size == 0) {
          size = length - pos;
        }
        if (size < headerLen) return null;
        if (latin1.decode(header.sublist(4, 8)) == type) {
          await raf.setPosition(pos + headerLen);
          return await raf.read(size - headerLen);
        }
        pos += size;
      }
      return null;
    } finally {
      await raf.close();
    }
  }

  static Uint8List? _child(Uint8List data, String type) {
    final bd = ByteData.sublistView(data);
    var pos = 0;
    while (pos + 8 <= data.length) {
      var size = bd.getUint32(pos);
      var headerLen = 8;
      if (size == 1) {
        if (pos + 16 > data.length) return null;
        size = bd.getUint64(pos + 8);
        headerLen = 16;
      } else if (size == 0) {
        size = data.length - pos;
      }
      if (size < headerLen || pos + size > data.length) return null;
      if (latin1.decode(data.sublist(pos + 4, pos + 8)) == type) {
        return Uint8List.sublistView(data, pos + headerLen, pos + size);
      }
      pos += size;
    }
    return null;
  }
}
