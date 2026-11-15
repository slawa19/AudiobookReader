import 'dart:io';
import 'dart:typed_data';

import 'package:audiobook_reader/audio/wav_audio_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('wav-encoder-'));
  tearDown(() => root.deleteSync(recursive: true));

  for (final rate in [16000, 24000, 44100]) {
    test(
      'WAV читается обратно: PCM16 mono, частота $rate, число отсчётов и значения',
      () async {
        final pcm = Uint8List(rate * 2 + 6);
        final values = ByteData.sublistView(pcm);
        for (var i = 0; i < pcm.length ~/ 2; i++) {
          values.setInt16(i * 2, i.isEven ? -32768 : 32767, Endian.little);
        }
        final input = File('${root.path}/input.pcm')..writeAsBytesSync(pcm);
        final output = File('${root.path}/output.wav');
        await const WavAudioEncoder().encode(
          pcmPath: input.path,
          outputPath: output.path,
          sampleRate: rate,
        );
        final wav = output.readAsBytesSync();
        final header = ByteData.sublistView(wav);
        String tag(int start) =>
            String.fromCharCodes(wav.sublist(start, start + 4));
        expect(tag(0), 'RIFF');
        expect(header.getUint32(4, Endian.little), wav.length - 8);
        expect(tag(8), 'WAVE');
        expect(tag(12), 'fmt ');
        expect(header.getUint32(16, Endian.little), 16);
        expect(header.getUint16(20, Endian.little), 1);
        expect(header.getUint16(22, Endian.little), 1);
        expect(header.getUint32(24, Endian.little), rate);
        expect(header.getUint32(28, Endian.little), rate * 2);
        expect(header.getUint16(32, Endian.little), 2);
        expect(header.getUint16(34, Endian.little), 16);
        expect(tag(36), 'data');
        expect(header.getUint32(40, Endian.little) ~/ 2, rate + 3);
        expect(wav.sublist(44), pcm);
        expect(input.readAsBytesSync(), pcm);
      },
    );
  }

  test(
    'нечётный PCM и неверная частота не оставляют выход, вход не меняется',
    () async {
      final input = File('${root.path}/input.pcm');
      final output = File('${root.path}/output.wav');
      for (final (bytes, rate) in [(Uint8List(3), 24000), (Uint8List(4), 0)]) {
        input.writeAsBytesSync(bytes);
        output.writeAsStringSync('частичный');
        await expectLater(
          const WavAudioEncoder().encode(
            pcmPath: input.path,
            outputPath: output.path,
            sampleRate: rate,
          ),
          throwsArgumentError,
        );
        expect(output.existsSync(), isFalse);
        expect(input.readAsBytesSync(), bytes);
      }
    },
  );
}
