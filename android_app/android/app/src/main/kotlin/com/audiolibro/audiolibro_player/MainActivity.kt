package com.audiolibro.audiolibro_player

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity (en vez de FlutterActivity) comparte el engine de Flutter con el
// servicio de audio en segundo plano de just_audio_background.
class MainActivity : AudioServiceActivity()
