import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/book.dart';
import '../models/chapter.dart';
import '../models/sentence.dart';
import '../services/player_controller.dart';

class PlayerScreen extends StatefulWidget {
  final Book book;

  const PlayerScreen({super.key, required this.book});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _controller = PlayerController.instance;
  final _itemScrollController = ItemScrollController();
  final Map<Chapter?, List<Sentence>> _sentencesByChapter = {};
  bool _showText = false;
  Duration? _highlightedStart;

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  AudioPlayer get _player => _controller.player;

  @override
  void initState() {
    super.initState();
    // Si este libro ya estaba sonando (se volvio desde el mini-player) no se recarga.
    _controller.open(widget.book);
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
              title: Text(
                ch.title,
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                _fmt(ch.start),
                style: const TextStyle(color: Colors.grey),
              ),
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

  void _showBoost() {
    const names = ['Normal', 'Alto', 'Muy alto', 'Maximo'];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF171A21),
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Refuerzo de volumen',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Para audiolibros grabados muy bajo. Se recuerda por libro.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              for (final (i, db) in PlayerController.boostLevels.indexed)
                ListTile(
                  leading: Icon(
                    db == _controller.boostDb
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(
                    db == 0 ? names[i] : '${names[i]} (+${db.toInt()} dB)',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    _controller.setBoost(db);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showSleepTimer() {
    final active =
        _controller.sleepRemaining != null || _controller.sleepAtChapterEnd;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF171A21),
      // Sin esto la hoja se corta a media pantalla y esconde las ultimas opciones.
      isScrollControlled: true,
      builder: (ctx) {
        void pick(VoidCallback action) {
          action();
          Navigator.pop(ctx);
        }

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Temporizador para dormir',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Pausa sola (bajando el volumen al final) y deja que el celular '
                  'se apague y bloquee. Solo cuenta mientras suena.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              for (final minutes in const [5, 15, 30, 45, 60, 90, 120])
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text(
                    '$minutes minutos',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => pick(
                    () => _controller.setSleepTimer(Duration(minutes: minutes)),
                  ),
                ),
              if (widget.book.chapters.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.bookmark_outline),
                  title: const Text(
                    'Al terminar este capitulo',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () => pick(_controller.setSleepAtChapterEnd),
                ),
              if (active)
                ListTile(
                  leading: const Icon(
                    Icons.timer_off_outlined,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    'Cancelar temporizador',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () => pick(_controller.cancelSleep),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTextPanel(Duration position, Chapter? chapter) {
    final sentences = _sentencesForChapter(chapter);
    if (sentences.isEmpty) {
      return const Center(
        child: Text(
          'Sin texto para este capitulo',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final currentIndex = _currentSentenceIndex(sentences, position);
    final currentStart = currentIndex == -1
        ? null
        : sentences[currentIndex].start;
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

  Widget _buildControls(
    Duration position,
    Duration duration,
    Chapter? chapter,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (chapter != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              chapter.title,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        Slider(
          value: position.inMilliseconds
              .clamp(
                0,
                duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds,
              )
              .toDouble(),
          max: duration.inMilliseconds == 0
              ? 1
              : duration.inMilliseconds.toDouble(),
          onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(_fmt(position)), Text(_fmt(duration))],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 36,
              tooltip: 'Atrasar 10 segundos',
              icon: const Icon(Icons.replay_10),
              onPressed: () =>
                  _player.seek(_player.position - const Duration(seconds: 10)),
            ),
            const SizedBox(width: 16),
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snap) {
                final state = snap.data;
                final playing = state?.playing ?? false;
                final completed =
                    state?.processingState == ProcessingState.completed;
                return IconButton(
                  iconSize: 64,
                  tooltip: completed
                      ? 'Volver a empezar'
                      : (playing ? 'Pausar' : 'Reproducir'),
                  icon: Icon(
                    completed
                        ? Icons.replay_circle_filled
                        : playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
                  onPressed: _controller.togglePlay,
                );
              },
            ),
            const SizedBox(width: 16),
            IconButton(
              iconSize: 36,
              tooltip: 'Adelantar 30 segundos',
              icon: const Icon(Icons.forward_30),
              onPressed: () =>
                  _player.seek(_player.position + const Duration(seconds: 30)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            DropdownButton<double>(
              value: _controller.speed,
              items: _speeds
                  .map((s) => DropdownMenuItem(value: s, child: Text('${s}x')))
                  .toList(),
              onChanged: (v) {
                if (v != null) _controller.setSpeed(v);
              },
            ),
            _SleepButton(onPressed: _showSleepTimer),
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
    if (_controller.book?.id != widget.book.id || _controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _controller.loadError!,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      );
    }

    return StreamBuilder<Duration?>(
      stream: _player.durationStream,
      builder: (context, durationSnap) {
        final duration = durationSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: _player.positionStream,
          builder: (context, positionSnap) {
            final position = positionSnap.data ?? Duration.zero;
            final chapter = widget.book.chapterAt(position);
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
              child: SingleChildScrollView(
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
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(widget.book.title, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              icon: Icon(
                _controller.boostDb > 0
                    ? Icons.volume_up
                    : Icons.volume_up_outlined,
                color: _controller.boostDb > 0
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: 'Refuerzo de volumen',
              onPressed: _showBoost,
            ),
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
      ),
    );
  }
}

/// Icono de temporizador; muestra el tiempo restante cuando esta activo.
class _SleepButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _SleepButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    final remaining = c.sleepRemaining;
    final String? label;
    if (c.sleepAtChapterEnd) {
      label = 'Fin cap.';
    } else if (remaining != null) {
      final m = remaining.inMinutes.toString().padLeft(2, '0');
      final s = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
      label = '$m:$s';
    } else {
      label = null;
    }
    if (label == null) {
      return IconButton(
        tooltip: 'Temporizador para dormir',
        icon: const Icon(Icons.bedtime_outlined),
        onPressed: onPressed,
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.bedtime),
      label: Text(label),
    );
  }
}
