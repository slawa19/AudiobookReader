import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('клиент не объявляет неиспользуемые пределы токенов', () {
    final source = File('lib/tts/gemini.dart').readAsStringSync();
    for (final name in ['maximumInputTokens', 'maximumOutputAudioTokens']) {
      expect(source, isNot(contains(RegExp('const $name ='))));
    }
    expect(source, contains('const maximumRequestChars = 4000;'));
  });
}
