import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/book.dart';
import 'library_service.dart';

/// Generacion en el servidor + descarga del resultado. Vive fuera de la pantalla
/// "Generar": si el usuario sale mientras se sintetiza, igual se baja a la biblioteca.
class GenerationService extends ChangeNotifier {
  GenerationService._();
  static final instance = GenerationService._();

  final _library = LibraryService();

  bool running = false;
  String? stage;
  int step = 0;
  int total = 5;
  String? error;

  /// Aumenta con cada libro generado y descargado; la biblioteca lo escucha para
  /// refrescarse y avisar.
  int completedCount = 0;
  Book? lastCompleted;

  Future<void> start(
    String baseUrl,
    File file,
    String lang,
    String voice,
  ) async {
    if (running) return;
    running = true;
    error = null;
    stage = 'Subiendo archivo...';
    step = 0;
    notifyListeners();
    try {
      final jobId = await _library.generateOnServer(baseUrl, file, lang, voice);
      final outName = await _waitForJob(baseUrl, jobId);
      _update(stage: 'Descargando audiolibro al celular...');
      lastCompleted = await _library.downloadGeneratedJob(
        baseUrl,
        jobId,
        outName,
      );
      completedCount++;
    } catch (e) {
      error = e is _JobFailed ? e.message : 'Error: $e';
    } finally {
      running = false;
      notifyListeners();
    }
  }

  void _update({String? stage, int? step, int? total}) {
    if (stage != null) this.stage = stage;
    if (step != null) this.step = step;
    if (total != null) this.total = total;
    notifyListeners();
  }

  /// Consulta el job de a una por vez (nunca dos pedidos en vuelo) y tolera cortes
  /// breves de red. Devuelve el nombre del M4B generado.
  Future<String> _waitForJob(String baseUrl, String jobId) async {
    var consecutiveErrors = 0;
    while (true) {
      await Future.delayed(const Duration(seconds: 1));
      final Map<String, dynamic> job;
      try {
        job = await _library.fetchJobStatus(baseUrl, jobId);
        consecutiveErrors = 0;
      } catch (_) {
        if (++consecutiveErrors >= 10) {
          throw _JobFailed('Se perdio la conexion con el servidor');
        }
        continue;
      }
      _update(
        stage: job['stage'] as String?,
        step: job['step'] as int? ?? 0,
        total: job['total'] as int? ?? 5,
      );
      if (job['status'] == 'done') return job['out_name'] as String;
      if (job['status'] == 'error') {
        throw _JobFailed(job['error'] as String? ?? 'Fallo la generacion');
      }
    }
  }
}

class _JobFailed implements Exception {
  final String message;
  _JobFailed(this.message);
}
