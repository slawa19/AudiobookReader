import 'package:http/http.dart' as http;

import '../library/settings.dart';
import '../tts/engine.dart';
import '../tts/gemini.dart';
import '../tts/voices.dart';

/// The key is captured per request. A request already in flight finishes with the old
/// key; a new one re-reads the settings. The tts client stays pure Dart.
class CurrentKeyEngine implements TtsEngine {
  CurrentKeyEngine(this.settings, this.transport);
  final AppSettings settings;
  final http.Client transport;
  @override
  Future<TtsResult> synthesize(String text, VoiceProfile profile) =>
      GeminiTtsEngine(apiKey: settings.apiKey ?? '', transport: transport).synthesize(text, profile);
}
