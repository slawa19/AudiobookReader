import 'dart:async';

import '../tts/book_language.dart';
import '../tts/voices.dart';
import 'player.dart';
import 'synthesis_queue.dart';
import 'voice_sample.dart';

/// The probe cache is the samples/ files themselves. The registry and retries are shared with listening.
class FileVoiceSampler extends VoiceSampler {
  FileVoiceSampler({required this.queue, required this.player}) {
    _subscription = player.events.listen((event) {
      if (event.generation != _session || _disposed) return;
      if (event.kind == PlayerEventKind.failed) {
        _task?.dispose();
        _task = null;
        player.clear(++_session);
        _state = SampleState.failed;
        _error = 'PlayerError: audio file unreadable';
        notifyListeners();
      } else if (event.kind == PlayerEventKind.drained ||
          event.kind == PlayerEventKind.interrupted) {
        stop();
      } else {
        notifyListeners();
      }
    });
  }
  final SynthesisQueue queue;
  final PlayerPort player;
  late final StreamSubscription<PlayerEvent> _subscription;
  SynthesisTask? _task;
  String? _voice, _error;
  SampleState _state = SampleState.idle;
  int _session = 0;
  bool _disposed = false;
  @override
  String? get voice => _voice;
  @override
  SampleState get state => _state;
  @override
  String? get errorMessage => _error;
  @override
  double get progress => player.current == null
      ? 0
      : (player.position.inMicroseconds /
                player.current!.duration.inMicroseconds)
            .clamp(0, 1);

  @override
  void play(VoiceProfile profile, {required String bookLanguage}) {
    if (!queue.settings.hasApiKey) return;
    stop();
    final session = _session;
    _voice = profile.voiceId;
    _state = SampleState.loading;
    final effective = VoiceProfile(
      model: profile.model,
      voiceId: profile.voiceId,
      style: readingStyleFor(bookLanguage),
    );
    final request = queue.request(
      phraseFor(bookLanguage),
      effective,
    );
    var loading = false;
    Future<void> changed() async {
      if (session != _session ||
          _disposed ||
          loading ||
          _state != SampleState.loading) {
        return;
      }
      final file = queue.audio.file(request.fingerprint);
      if (file == null) {
        _task?.update([request], active: true);
        return;
      }
      loading = true;
      Duration duration;
      try {
        duration = await player.duration(file);
      } catch (_) {
        if (session == _session && !_disposed) {
          _task?.dispose();
          _state = SampleState.failed;
          _error = 'Не удалось прочитать звуковой файл';
          notifyListeners();
        }
        return;
      }
      if (session != _session || _disposed) return;
      _task?.dispose();
      _task = null;
      player.append(PlayerItem(file: file, segment: 0, duration: duration));
      _state = SampleState.playing;
      player.play();
      notifyListeners();
    }

    _task = queue.task(
      changed: () => unawaited(changed()),
      failed: (error) {
        if (session != _session || _disposed) return;
        _state = SampleState.failed;
        _error = error.message;
        notifyListeners();
      },
    );
    notifyListeners();
    unawaited(changed());
  }

  @override
  void stop() {
    _session++;
    _task?.dispose();
    _task = null;
    player.clear(_session);
    _voice = _error = null;
    _state = SampleState.idle;
    notifyListeners();
  }

  @override
  void clearCache() => stop();
  @override
  void dispose() {
    _disposed = true;
    _session++;
    _task?.dispose();
    player.clear(_session);
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
