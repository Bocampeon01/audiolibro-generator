import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

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
  final _currentSentenceKey = GlobalKey();
  Timer? _saveTimer;
  double _speed = 1.0;
  bool _ready = false;
  bool _showText = false;
  int? _lastHighlightedIndex;

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _player.setFilePath(widget.book.filePath);
    _speed = await _positionService.loadSpeed();
    await _player.setSpeed(_speed);

    final savedPosition = await _positionService.loadPosition(widget.book.id);
    if (savedPosition != null) {
      await _player.seek(savedPosition);
    }

    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _positionService.savePosition(widget.book.id, _player.position);
    });

    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _positionService.savePosition(widget.book.id, _player.position);
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
    if (chapter == null) return widget.book.sentences;
    return widget.book.sentences
        .where((s) => s.start >= chapter.start && s.start < chapter.end)
        .toList();
  }

  int _currentSentenceIndex(List<Sentence> sentences, Duration position) {
    for (var i = 0; i < sentences.length; i++) {
      if (position >= sentences[i].start && position < sentences[i].end) return i;
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
    if (currentIndex != -1 && currentIndex != _lastHighlightedIndex) {
      _lastHighlightedIndex = currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _currentSentenceKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 300));
        }
      });
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: sentences.length,
      itemBuilder: (context, i) {
        final isCurrent = i == currentIndex;
        return Container(
          key: isCurrent ? _currentSentenceKey : null,
          margin: const EdgeInsets.only(bottom: 14),
          child: GestureDetector(
            onTap: () => _player.seek(sentences[i].start),
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
                final playing = snap.data?.playing ?? false;
                return IconButton(
                  iconSize: 64,
                  icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                  onPressed: () => playing ? _player.pause() : _player.play(),
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
                label: Text('${widget.book.chapters.length} capitulos'),
              ),
          ],
        ),
      ],
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
              onPressed: () => setState(() => _showText = !_showText),
            ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<Duration?>(
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
            ),
    );
  }
}
