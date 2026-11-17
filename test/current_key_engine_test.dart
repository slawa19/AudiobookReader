import 'package:audiobook_reader/app/current_key_engine.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/tts/engine.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('the wrapper reads the current key for each request; errors are scrubbed', () async {
    final settings = AppSettings(voice: 'Aoede', modelId: TtsModel.flash.id, apiKey: 'first-test-key');
    addTearDown(settings.dispose);
    final keys = <String?>[];
    final transport = MockClient((request) async {
      final key = request.headers['x-goog-api-key'];
      keys.add(key);
      expect(request.url.toString(), isNot(contains(key!)));
      return http.Response('{"error":{"message":"API key not valid: $key"}}', 403);
    });
    addTearDown(transport.close);
    final engine = CurrentKeyEngine(settings, transport);
    final profile = VoiceProfile(voiceId: 'Aoede', model: TtsModel.flash.id);
    for (final key in ['first-test-key', 'replacement-test-key']) {
      settings.apiKey = key;
      await expectLater(
        engine.synthesize('Sample.', profile),
        throwsA(isA<TtsError>().having((e) => e.message, 'secret scrubbed', isNot(contains(key)))),
      );
    }
    expect(keys, ['first-test-key', 'replacement-test-key']);
  });
}
