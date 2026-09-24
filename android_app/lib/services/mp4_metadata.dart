import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Lee el JSON de sincronizacion (capitulos + oraciones) que el generador embebe en
/// el tag "lyrics" (atom ©lyr) del M4B. Permite que un .m4b importado solo (WhatsApp,
/// Drive) conserve capitulos y texto sin el .chapters.json de al lado.
/// Ruta: moov > udta > meta > ilst > ©lyr > data. Misma logica que
/// tests/test_pipeline_integration.py::read_embedded_sync.
class Mp4Metadata {
  static Future<String?> readSyncJson(File file) async {
    final moov = await _readTopLevelBox(file, 'moov');
    if (moov == null) return null;
    final meta =
        _child(_child(moov, 'udta') ?? Uint8List(0), 'meta') ??
        _child(moov, 'meta');
    if (meta == null || meta.length < 4) return null;
    final ilst = _child(
      Uint8List.sublistView(meta, 4),
      'ilst',
    ); // meta es full box
    final lyr = ilst == null ? null : _child(ilst, '©lyr');
    final data = lyr == null ? null : _child(lyr, 'data');
    if (data == null || data.length < 8) return null;
    return utf8.decode(
      Uint8List.sublistView(data, 8),
      allowMalformed: true,
    ); // 8 = tipo + locale
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
