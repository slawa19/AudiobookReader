import 'dart:io';
import 'dart:typed_data';

import 'audio_encoder.dart';

/// Uncompressed WAV PCM: tests and Linux use the same file contract.
class WavAudioEncoder implements AudioEncoder {
  const WavAudioEncoder();

  @override
  String get formatId => 'wav-pcm16-mono-v1';
  @override
  String get extension => 'wav';

  @override
  Future<void> encode({
    required String pcmPath,
    required String outputPath,
    required int sampleRate,
  }) async {
    if (pcmPath == outputPath) throw ArgumentError('Input and output are the same file');
    final output = File(outputPath);
    try {
      final input = File(pcmPath);
      final length = await input.length();
      if (sampleRate <= 0 ||
          sampleRate > 0x7fffffff ||
          length.isOdd ||
          length > 0xffffffff - 36) {
        throw ArgumentError('Invalid PCM parameters');
      }
      final header = ByteData(44);
      void tag(int offset, String value) {
        header.buffer.asUint8List().setRange(
          offset,
          offset + value.length,
          value.codeUnits,
        );
      }

      tag(0, 'RIFF');
      header.setUint32(4, length + 36, Endian.little);
      tag(8, 'WAVE');
      tag(12, 'fmt ');
      header.setUint32(16, 16, Endian.little);
      header.setUint16(20, 1, Endian.little);
      header.setUint16(22, 1, Endian.little);
      header.setUint32(24, sampleRate, Endian.little);
      header.setUint32(28, sampleRate * 2, Endian.little);
      header.setUint16(32, 2, Endian.little);
      header.setUint16(34, 16, Endian.little);
      tag(36, 'data');
      header.setUint32(40, length, Endian.little);
      final sink = output.openWrite();
      try {
        sink.add(header.buffer.asUint8List());
        await sink.addStream(input.openRead());
        await sink.flush();
      } finally {
        await sink.close();
      }
    } catch (_) {
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }
}
