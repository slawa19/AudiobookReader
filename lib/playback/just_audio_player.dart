import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart' as audio;

import 'player.dart';
import 'queued_player.dart';

/// The platform layer does not count generations or the queue: QueuedPlayer does that.
class JustAudioPlayer extends QueuedPlayer {
  JustAudioPlayer({required super.beforePlay}) : super(createEngine: _JustAudioEngine.new, readDuration: _duration);

  static Future<Duration> _duration(File file) async {
    // Measuring does not change the playing list and does not request audio focus.
    final probe = audio.AudioPlayer(handleInterruptions: false, handleAudioSessionActivation: false);
    try {
      final duration = await probe.setFilePath(file.path);
      if (duration == null || duration <= Duration.zero) throw const FormatException('Нет длительности звука');
      return duration;
    } finally {
      await probe.dispose();
    }
  }
}

class _JustAudioEngine implements PlaylistEngine {
  _JustAudioEngine() {
    _subscriptions.addAll([
      _player.playbackEventStream.listen((event) => _emit(event: event)),
      _player.playingStream.listen((_) => _emit()),
      _player.positionStream.listen((_) => _emit(progress: true)),
      _player.errorStream.listen(
        (error) => _events.addError(EngineFailure(_itemAt(error.index ?? _player.currentIndex))),
      ),
    ]);
  }
  final _player = audio.AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
    useProxyForRequestHeaders: false,
  );
  final _events = StreamController<EnginePlayback>.broadcast(sync: true);
  final _subscriptions = <StreamSubscription<dynamic>>[];
  @override
  Stream<EnginePlayback> get events => _events.stream;
  @override
  EnginePlayback get snapshot => _snapshot();

  PlayerItem? _itemAt(int? index) => index != null && index >= 0 && index < _player.sequence.length
      ? _player.sequence[index].tag as PlayerItem?
      : null;

  EnginePlayback _snapshot({audio.PlaybackEvent? event, bool progress = false}) {
    final index = event?.currentIndex ?? _player.currentIndex;
    final sequence = _player.sequence;
    final item = index != null && index < sequence.length ? sequence[index].tag as PlayerItem? : null;
    final processing = event?.processingState ?? _player.processingState;
    return EnginePlayback(
      item: item,
      position: _player.position,
      playing: _player.playing,
      ready: processing == audio.ProcessingState.ready,
      completed: processing == audio.ProcessingState.completed,
      progress: progress,
    );
  }

  void _emit({audio.PlaybackEvent? event, bool progress = false}) =>
      _events.add(_snapshot(event: event, progress: progress));
  @override
  Future<void> load(PlayerItem item) async {
    await _player.setAudioSources([audio.AudioSource.file(item.file.path, tag: item)]);
  }

  @override
  Future<void> append(PlayerItem item) => _player.addAudioSource(audio.AudioSource.file(item.file.path, tag: item));
  @override
  Future<void> seek(int index, {Duration position = Duration.zero}) => _player.seek(position, index: index);
  @override
  Future<void> retain(int count) => _player.removeAudioSourceRange(count, _player.sequence.length);
  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
  @override
  void play() {
    // The just_audio.play Future completes at the end of the file; the command queue does not wait for it.
    unawaited(_player.play().catchError((Object e, StackTrace s) => _events.addError(EngineFailure(snapshot.item))));
  }

  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    await _events.close();
  }
}
