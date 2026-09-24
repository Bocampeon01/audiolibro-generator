import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/book.dart';
import '../models/chapter.dart';
import '../models/sentence.dart';
import '../services/playback_position_service.dart';

class PlayerScreen extends StatefulWidget {
  final Book book;

  const PlayerScreen({super.key, required this.book});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _player = AudioPlayer();
  final _positionService = PlaybackPositionService();
  final _itemScrollController = ItemScrollController();
  final Map<Chapter?, List<Sentence>> _sentencesByChapter = {};
  Timer? _saveTimer;
  double _speed = 1.0;
  bool _ready = false;
  String? _loadError;
  bool _showText = false;
  Duration? _highlightedStart;

  // Guardar una posicion a menos de esto del final = libro terminado: al reabrir
  // arranca de cero en vez de "reproducir" los ultimos segundos.
  static const _finishedThreshold = Duration(seconds: 5);
  static const _speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // tag MediaItem: lo usa just_audio_background para la notificacion y la
      // pantalla de bloqueo; el audio sigue con la pantalla apagada o en otra app.
      await _player.setAudioSource(AudioSource.file(
        widget.book.filePath,
        tag: MediaItem(id: widget.book.id, title: widget.book.title, album: 'Audiolibro'),
      ));
    } catch (e) {
      if (mounted) setState(() => _loadError = 'No se pudo abrir el audiolibro: $e');
      return;
    }
    _speed = await _positionService.loadSpeed();
    await _player.setSpeed(_speed);

    final savedPosition = await _positionService.loadPosition(widget.book.id);
    if (savedPosition != null) {
      await _player.seek(savedPosition);
    }

    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _savePosition());
    if (mounted) setState(() => _ready = true);
  }

  void _savePosition() {
    if (!_ready) return;
    final duration = _player.duration;
    var position = _player.position;
    if (duration != null && duration - position < _finishedThreshold) {
      position = Duration.zero;
    }
    _positionService.savePosition(widget.book.id, position);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _savePosition();
    _player.dispose();
    super.dispose();
  }

  Chapter? _currentChapter(Duration position) {
    for (final ch in widget.book.chapters) {
      if (position >= ch.start && position < ch.end) return ch;
    }
    return null;
  }

  List<Sentence> _sentencesForChapter(Chapter? chapter) {
    return _sentencesByChapter.putIfAbsent(chapter, () {
      if (chapter == null) return widget.book.sentences;
      return widget.book.sentences
          .where((s) => s.start >= chapter.start && s.start < chapter.end)
          .toList();
    });
  }

  int _currentSentenceIndex(List<Sentence> sentences, Duration position) {
    // Busqueda binaria: las oraciones estan ordenadas y son contiguas.
    var lo = 0, hi = sentences.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (position < sentences[mid].start) {
        hi = mid - 1;
      } else if (position >= sentences[mid].end) {
        lo = mid + 1;
      } else {
        return mid;
      }
    }
    return -1;
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _showChapters() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF171A21),
      builder: (ctx) {
        return ListView(
          shrinkWrap: true,
          children: widget.book.chapters.map((ch) {
            return ListTile(
              title: Text(ch.title, style: const TextStyle(color: Colors.white)),
              subtitle: Text(_fmt(ch.start), style: const TextStyle(color: Colors.grey)),
              onTap: () {
                _player.seek(ch.start);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildTextPanel(Duration position, Chapter? chapter) {
    final sentences = _sentencesForChapter(chapter);
    if (sentences.isEmpty) {
      return const Center(
        child: Text('Sin texto para este capitulo', style: TextStyle(color: Colors.grey)),
      );
    }

    final currentIndex = _currentSentenceIndex(sentences, position);
    final currentStart = currentIndex == -1 ? null : sentences[currentIndex].start;
    if (currentStart != null && currentStart != _highlightedStart) {
      _highlightedStart = currentStart;
      // ItemScrollController llega a items que la lista todavia no construyo
      // (saltos de capitulo o del slider), cosa que ensureVisible no podia.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_itemScrollController.isAttached) {
          _itemScrollController.scrollTo(
            index: currentIndex,
            alignment: 0.3,
            duration: const Duration(milliseconds: 300),
          );
        }
      });
    }

    return ScrollablePositionedList.builder(
      key: ValueKey(chapter?.start),
      itemScrollController: _itemScrollController,
      initialScrollIndex: currentIndex == -1 ? 0 : currentIndex,
      initialAlignment: 0.3,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: sentences.length,
      itemBuilder: (context, i) {
        final isCurrent = i == currentIndex;
        return GestureDetector(
          onTap: () => _player.seek(sentences[i].start),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              sentences[i].text,
              style: TextStyle(
                fontSize: 17,
                height: 1.5,
                color: isCurrent ? Colors.white : Colors.grey,
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControls(Duration position, Duration duration, Chapter? chapter) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (chapter != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(chapter.title, style: const TextStyle(color: Colors.grey)),
          ),
        Slider(
          value: position.inMilliseconds
              .clamp(0, duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds)
              .toDouble(),
          max: duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds.toDouble(),
          onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_fmt(position)),
            Text(_fmt(duration)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.replay_10),
              onPressed: () => _player.seek(_player.position - const Duration(seconds: 10)),
            ),
            const SizedBox(width: 16),
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snap) {
                final state = snap.data;
                final playing = state?.playing ?? false;
                final completed = state?.processingState == ProcessingState.completed;
                return IconButton(
                  iconSize: 64,
                  icon: Icon(
                    completed
                        ? Icons.replay_circle_filled
                        : playing
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                  ),
                  onPressed: () async {
                    if (completed) {
                      await _player.seek(Duration.zero);
                      await _player.play();
                    } else if (playing) {
                      await _player.pause();
                    } else {
                      await _player.play();
                    }
                  },
                );
              },
            ),
            const SizedBox(width: 16),
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.forward_30),
              onPressed: () => _player.seek(_player.position + const Duration(seconds: 30)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            DropdownButton<double>(
              value: _speed,
              items: _speeds.map((s) => DropdownMenuItem(value: s, child: Text('${s}x'))).toList(),
              onChanged: (v) async {
                if (v == null) return;
                setState(() => _speed = v);
                await _player.setSpeed(v);
                await _positionService.saveSpeed(v);
              },
            ),
            if (widget.book.chapters.isNotEmpty)
              TextButton.icon(
                onPressed: _showChapters,
                icon: const Icon(Icons.list),
                label: Text(chaptersLabel(widget.book.chapters.length)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_loadError!, style: const TextStyle(color: Colors.redAccent)),
        ),
      );
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());

    return StreamBuilder<Duration?>(
      stream: _player.durationStream,
      builder: (context, durationSnap) {
        final duration = durationSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: _player.positionStream,
          builder: (context, positionSnap) {
            final position = positionSnap.data ?? Duration.zero;
            final chapter = _currentChapter(position);
            if (_showText) {
              return Column(
                children: [
                  Expanded(child: _buildTextPanel(position, chapter)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: _buildControls(position, duration, chapter),
                  ),
                ],
              );
            }
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _buildControls(position, duration, chapter),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.book.sentences.isNotEmpty)
            IconButton(
              icon: Icon(_showText ? Icons.article : Icons.article_outlined),
              tooltip: 'Seguir el texto mientras escuchas',
              onPressed: () => setState(() {
                _showText = !_showText;
                _highlightedStart = null;
              }),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }
}
