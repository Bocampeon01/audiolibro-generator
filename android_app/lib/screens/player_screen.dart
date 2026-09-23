import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/book.dart';
import '../models/chapter.dart';
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
  Timer? _saveTimer;
  double _speed = 1.0;
  bool _ready = false;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.book.title, overflow: TextOverflow.ellipsis)),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  StreamBuilder<Duration?>(
                    stream: _player.durationStream,
                    builder: (context, durationSnap) {
                      final duration = durationSnap.data ?? Duration.zero;
                      return StreamBuilder<Duration>(
                        stream: _player.positionStream,
                        builder: (context, positionSnap) {
                          final position = positionSnap.data ?? Duration.zero;
                          final chapter = _currentChapter(position);
                          return Column(
                            children: [
                              if (chapter != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(chapter.title,
                                      style: const TextStyle(color: Colors.grey)),
                                ),
                              Slider(
                                value: position.inMilliseconds
                                    .clamp(0, duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds)
                                    .toDouble(),
                                max: duration.inMilliseconds == 0
                                    ? 1
                                    : duration.inMilliseconds.toDouble(),
                                onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_fmt(position)),
                                  Text(_fmt(duration)),
                                ],
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 24),
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
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      DropdownButton<double>(
                        value: _speed,
                        items: _speeds
                            .map((s) => DropdownMenuItem(value: s, child: Text('${s}x')))
                            .toList(),
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
              ),
            ),
    );
  }
}
