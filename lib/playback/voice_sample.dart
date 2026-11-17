import 'dart:async';

import 'package:flutter/foundation.dart';

import '../audio/audio_store.dart';
import '../tts/book_language.dart';
import '../tts/voices.dart';

enum SampleState { idle, loading, playing, failed }

/// A voice "probe" (A§6.8): one phrase, a separate short player, the second time — without a request. A permanent error
/// is shown in the voice row with Google's text as is.
abstract class VoiceSampler extends ChangeNotifier {
  /// The voice whose probe is now being prepared, is playing or has failed.
  String? get voice;
  SampleState get state;

  /// The fraction of the probe played.
  double get progress;

  /// Google's text for [SampleState.failed].
  String? get errorMessage;

  /// The probe phrase for the book language (`tts`, a table by book language).
  String phraseFor(String bookLanguage) => samplePhraseFor(bookLanguage);

  /// A probe of the full profile [profile] (voice and model) with the phrase and style in the language of the book
  /// [bookLanguage] (FR-T7). The audio is cached by everything that affects the sound: voice, model, language (phrase
  /// and style) — another profile is synthesized again (A§6.8, logic review item 10).
  void play(VoiceProfile profile, {required String bookLanguage});
  void stop();

  /// Probes deleted by "Clear narration" (A§4): the next probe is synthesized again. Called only by
  /// `NarrationController`.
  void clearCache();
}

/// A fake probe: the first time it is "prepared" for a bit under a second, then "plays" for three seconds. No audio.
class FakeVoiceSampler extends VoiceSampler {
  FakeVoiceSampler({
    this.loading = const Duration(milliseconds: 900),
    this.length = const Duration(seconds: 3),
    this.audio,
  });

  final Duration loading;
  final Duration length;

  /// The fake storage: a new probe takes up space in `samples/`.
  final FakeAudioStore? audio;

  /// Bytes of one probe (≈ 3 s of compressed audio).
  static const sampleBytes = 12000;
  final Set<String> _cached = {};
  String? _voice;
  SampleState _state = SampleState.idle;
  double _progress = 0;
  String? _error;
  Timer? _timer;

  /// For display only: the next probe of this voice will fail with a Google error.
  String? demoFailVoice;

  @override
  String? get voice => _voice;
  @override
  SampleState get state => _state;
  @override
  double get progress => _progress;
  @override
  String? get errorMessage => _error;

  @override
  void play(VoiceProfile profile, {required String bookLanguage}) {
    final voice = profile.voiceId;
    _timer?.cancel();
    _voice = voice;
    _progress = 0;
    _error = null;
    final key = '${profile.key}|$bookLanguage|${phraseFor(bookLanguage)}';
    if (_cached.contains(key)) {
      _playNow();
    } else {
      _state = SampleState.loading;
      _timer = Timer(loading, () {
        if (demoFailVoice == voice) {
          demoFailVoice = null;
          _state = SampleState.failed;
          _error = 'The service is currently unavailable.';
          notifyListeners();
          return;
        }
        _cached.add(key);
        audio?.addSamples(sampleBytes);
        _playNow();
      });
    }
    notifyListeners();
  }

  void _playNow() {
    _state = SampleState.playing;
    const step = Duration(milliseconds: 100);
    _timer = Timer.periodic(step, (_) {
      _progress += step.inMilliseconds / length.inMilliseconds;
      if (_progress >= 1) {
        stop();
        return;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void stop() {
    _timer?.cancel();
    _voice = null;
    _state = SampleState.idle;
    _progress = 0;
    _error = null;
    notifyListeners();
  }

  @override
  void clearCache() {
    stop();
    _cached.clear();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
