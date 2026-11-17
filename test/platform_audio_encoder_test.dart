import 'dart:io';

import 'package:audiobook_reader/platform/audio_encoder.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('aac-channel-'));
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidAudioEncoder.channel, null);
    root.deleteSync(recursive: true);
  });

  test(
    'the AAC channel passes paths and sample rate and waits for a successful result',
    () async {
      final input = File('${root.path}/input.pcm')
        ..writeAsBytesSync([0, 0, 1, 0]);
      final output = File('${root.path}/out.m4a');
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidAudioEncoder.channel, (call) async {
            received = call;
            await output.writeAsBytes([1, 2, 3]);
            return null;
          });
      const encoder = AndroidAudioEncoder();
      await encoder.encode(
        pcmPath: input.path,
        outputPath: output.path,
        sampleRate: 24000,
      );
      expect(received!.method, 'encode');
      expect(received!.arguments, {
        'pcmPath': input.path,
        'outputPath': output.path,
        'sampleRate': 24000,
      });
      expect(encoder.extension, 'm4a');
      expect(encoder.formatId, contains('48000'));
      expect(output.readAsBytesSync(), [1, 2, 3]);
      expect(input.readAsBytesSync(), [0, 0, 1, 0]);
    },
  );

  test(
    'a codec error reaches the queue, partial output is removed, the PCM stays',
    () async {
      final input = File('${root.path}/input.pcm')..writeAsBytesSync([1, 0]);
      final output = File('${root.path}/out.m4a');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidAudioEncoder.channel, (call) async {
            await output.writeAsBytes([1, 2, 3]);
            throw PlatformException(
              code: 'audio_encode_failed',
              message: 'codec failed',
            );
          });
      await expectLater(
        const AndroidAudioEncoder().encode(
          pcmPath: input.path,
          outputPath: output.path,
          sampleRate: 24000,
        ),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', 'audio_encode_failed')
              .having((e) => e.message, 'message', 'codec failed'),
        ),
      );
      expect(output.existsSync(), isFalse);
      expect(input.readAsBytesSync(), [1, 0]);
    },
  );
}
