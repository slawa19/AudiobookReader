import 'dart:io';

import 'package:flutter/services.dart';

import '../audio/audio_encoder.dart';

/// PCM is passed to Android as a file path, without copying the array into the MethodChannel.
class AndroidAudioEncoder implements AudioEncoder {
  const AndroidAudioEncoder();

  static const channel = MethodChannel('audiobook_reader/audio_encoder');

  @override
  String get formatId => 'm4a-aac-lc-mono-48000-v1';
  @override
  String get extension => 'm4a';

  @override
  Future<void> encode({
    required String pcmPath,
    required String outputPath,
    required int sampleRate,
  }) async {
    if (pcmPath == outputPath) throw ArgumentError('Input and output are the same file');
    try {
      await channel.invokeMethod<void>('encode', {
        'pcmPath': pcmPath,
        'outputPath': outputPath,
        'sampleRate': sampleRate,
      });
    } catch (_) {
      final partial = File(outputPath);
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }
}
