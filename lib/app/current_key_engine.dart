import 'package:http/http.dart' as http;

import '../library/settings.dart';
import '../tts/engine.dart';
import '../tts/gemini.dart';
import '../tts/voices.dart';

/// Ключ захватывается на один запрос. Уже идущий запрос заканчивается старым
/// ключом; новый читает настройки заново. Клиент tts остаётся чистым Dart.
class CurrentKeyEngine implements TtsEngine {
  CurrentKeyEngine(this.settings, this.transport);
  final AppSettings settings;
  final http.Client transport;
  @override
  Future<TtsResult> synthesize(String text, VoiceProfile profile) =>
      GeminiTtsEngine(apiKey: settings.apiKey ?? '', transport: transport).synthesize(text, profile);
}
