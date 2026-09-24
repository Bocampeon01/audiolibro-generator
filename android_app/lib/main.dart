import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'screens/library_screen.dart';

Future<void> main() async {
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.audiolibro.audiolibro_player.audio',
    androidNotificationChannelName: 'Reproduccion de audiolibros',
    androidNotificationOngoing: true,
  );
  runApp(const AudiolibroApp());
}

class AudiolibroApp extends StatelessWidget {
  const AudiolibroApp({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF6C5CE7);
    return MaterialApp(
      title: 'Audiolibro Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF171A21),
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF171A21),
        ),
      ),
      home: const LibraryScreen(),
    );
  }
}
