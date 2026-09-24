import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../screens/player_screen.dart';
import '../services/player_controller.dart';

/// Barra inferior de la biblioteca con el libro que esta sonando: el audio sigue
/// mientras se navega, y un toque vuelve al reproductor completo.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = PlayerController.instance;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final book = controller.book;
        if (book == null || controller.loadError != null) {
          return const SizedBox.shrink();
        }
        final player = controller.player;
        return Material(
          color: const Color(0xFF171A21),
          child: SafeArea(
            top: false,
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PlayerScreen(book: book)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StreamBuilder<Duration>(
                    stream: player.positionStream,
                    builder: (context, snap) {
                      final total = player.duration?.inMilliseconds ?? 0;
                      final pos = snap.data?.inMilliseconds ?? 0;
                      return LinearProgressIndicator(
                        value: total > 0 ? (pos / total).clamp(0.0, 1.0) : 0,
                        minHeight: 2,
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.headphones),
                    title: Text(
                      book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle:
                        controller.sleepRemaining != null ||
                            controller.sleepAtChapterEnd
                        ? Text(
                            controller.sleepAtChapterEnd
                                ? 'Se detiene al final del capitulo'
                                : 'Se detiene en ${_mmss(controller.sleepRemaining!)}',
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                    trailing: StreamBuilder<PlayerState>(
                      stream: player.playerStateStream,
                      builder: (context, snap) {
                        final playing = snap.data?.playing ?? false;
                        return IconButton(
                          tooltip: playing ? 'Pausar' : 'Reproducir',
                          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                          onPressed: controller.togglePlay,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String _mmss(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
