import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/book.dart';
import 'playback_position_service.dart';

/// Reproductor unico de la app. Vive fuera de las pantallas: se puede volver a la
/// biblioteca (mini-player) sin cortar el audio. just_audio_background ademas exige
/// una sola instancia de AudioPlayer.
class PlayerController extends ChangeNotifier {
  PlayerController._();
  static final instance = PlayerController._();

  final player = AudioPlayer();
  final _positions = PlaybackPositionService();

  Book? book;
  bool loading = false;
  String? loadError;
  double speed = 1.0;

  /// Temporizador para dormir: tiempo restante (solo corre mientras suena)...
  Duration? sleepRemaining;

  /// ...o pausa al terminar el capitulo en curso.
  bool sleepAtChapterEnd = false;

  Timer? _saveTimer;
  Timer? _sleepTicker;
  StreamSubscription<Duration>? _chapterEndSub;
  StreamSubscription<PlayerState>? _stateSub;
  int _openSeq = 0;

  // Posicion a menos de esto del final = libro terminado: al reabrir arranca de cero.
  static const _finishedThreshold = Duration(seconds: 5);
  static const _fadeOut = Duration(seconds: 10);

  bool get ready => book != null && !loading && loadError == null;

  Future<void> open(Book b) async {
    if (book?.id == b.id && loadError == null) return;
    // Sin esto el libro nuevo hereda el "playing" del anterior y arranca solo.
    if (player.playing) await player.pause();
    await _saveNow();
    cancelSleep();
    final seq = ++_openSeq;
    book = b;
    loading = true;
    loadError = null;
    notifyListeners();

    try {
      await player.setAudioSource(
        AudioSource.file(
          b.filePath,
          tag: MediaItem(id: b.id, title: b.title, album: 'Audiolibro'),
        ),
      );
      speed = await _positions.loadSpeed();
      await player.setSpeed(speed);
      final saved = await _positions.loadPosition(b.id);
      if (saved != null) await player.seek(saved);
    } catch (e) {
      // Si mientras cargaba se abrio otro libro, este error es de la carga cancelada.
      if (seq != _openSeq) return;
      loadError = 'No se pudo abrir el audiolibro: $e';
    }
    if (seq != _openSeq) return;
    loading = false;
    _saveTimer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => _saveNow(),
    );
    _stateSub ??= player.playerStateStream.listen((s) {
      if (!s.playing) _saveNow();
    });
    notifyListeners();
  }

  /// Para y descarga el libro actual (por ejemplo, porque se borro).
  Future<void> close() async {
    _openSeq++;
    cancelSleep();
    book = null;
    loading = false;
    loadError = null;
    await player.stop();
    notifyListeners();
  }

  Future<void> togglePlay() async {
    if (!ready) return;
    if (player.processingState == ProcessingState.completed) {
      await player.seek(Duration.zero);
      await player.play();
    } else if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> setSpeed(double value) async {
    speed = value;
    notifyListeners();
    await player.setSpeed(value);
    await _positions.saveSpeed(value);
  }

  Future<void> _saveNow() async {
    final b = book;
    if (b == null || loading || loadError != null) return;
    final duration = player.duration;
    var position = player.position;
    if (duration != null && duration - position < _finishedThreshold) {
      position = Duration.zero;
    }
    await _positions.savePosition(b.id, position);
  }

  void setSleepTimer(Duration duration) {
    cancelSleep();
    sleepRemaining = duration;
    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = sleepRemaining;
      if (remaining == null || !player.playing) return;
      final next = remaining - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        player.pause();
        cancelSleep();
        return;
      }
      sleepRemaining = next;
      // Baja el volumen de a poco en los ultimos segundos en vez de cortar de golpe.
      if (next < _fadeOut) {
        player.setVolume(next.inMilliseconds / _fadeOut.inMilliseconds);
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void setSleepAtChapterEnd() {
    cancelSleep();
    final chapter = book?.chapterAt(player.position);
    if (chapter == null) return;
    sleepAtChapterEnd = true;
    var previous = player.position;
    _chapterEndSub = player.positionStream.listen((p) {
      // Solo al cruzar el final avanzando: un seek manual mas alla no cuenta.
      final crossed = previous < chapter.end && p >= chapter.end;
      final advancing =
          p > previous && p - previous < const Duration(seconds: 3);
      previous = p;
      if (crossed && advancing) {
        player.pause();
        player.seek(chapter.end);
        cancelSleep();
      }
    });
    notifyListeners();
  }

  void cancelSleep() {
    _sleepTicker?.cancel();
    _sleepTicker = null;
    _chapterEndSub?.cancel();
    _chapterEndSub = null;
    final wasActive = sleepRemaining != null || sleepAtChapterEnd;
    sleepRemaining = null;
    sleepAtChapterEnd = false;
    player.setVolume(1.0);
    if (wasActive) notifyListeners();
  }
}
