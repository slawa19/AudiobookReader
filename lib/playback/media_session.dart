import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';

import 'narration.dart';
import 'voice_sample.dart';

class MediaStrings {
  const MediaStrings({
    required this.channel,
    required this.preparing,
    required this.waiting,
    required this.paused,
    required this.ended,
    required this.play,
    required this.pause,
    required this.previous,
    required this.next,
  });
  final String channel, preparing, waiting, paused, ended, play, pause, previous, next;
}

/// Пауза оставляет foreground. При stopped штатный idle завершает службу;
/// карточка может исчезнуть, сообщение остаётся на экране чтения.
class NarrationMediaState {
  const NarrationMediaState(this.session, this.foreground, this.playing, this.processing, this.message);
  final bool session, foreground, playing;
  final AudioProcessingState processing;
  final String? message;
}

NarrationMediaState mediaStateFor(NarrationState state, MediaStrings strings, {StopReason? reason, String? error}) =>
    switch (state) {
      NarrationState.idle => const NarrationMediaState(false, false, false, AudioProcessingState.idle, null),
      NarrationState.preparing => NarrationMediaState(
        true,
        true,
        true,
        AudioProcessingState.loading,
        strings.preparing,
      ),
      NarrationState.playing => const NarrationMediaState(true, true, true, AudioProcessingState.ready, null),
      NarrationState.waiting => NarrationMediaState(true, true, true, AudioProcessingState.buffering, strings.waiting),
      NarrationState.paused => NarrationMediaState(true, true, false, AudioProcessingState.ready, strings.paused),
      NarrationState.stopped => NarrationMediaState(
        false,
        false,
        false,
        AudioProcessingState.idle,
        reason == StopReason.error ? error : strings.ended,
      ),
    };

class MediaCard {
  const MediaCard({required this.id, required this.title, required this.chapter, this.art});
  final String id, title, chapter;
  final Uri? art;
}

/// Порт ожидания подтверждения Android: фокус нельзя просить до startForeground.
abstract interface class MediaServiceLifecycle {
  Future<void> awaitForeground();
}

/// Команды системы идут в тот же контроллер, что и команды экрана.
class NarrationMediaHandler extends BaseAudioHandler {
  NarrationMediaHandler({
    required this.controller,
    required this.strings,
    required this.card,
    required this.lifecycle,
  }) {
    controller.addListener(publish);
    publish();
  }
  final NarrationController controller;
  final MediaStrings Function() strings;
  final MediaCard? Function() card;
  final MediaServiceLifecycle lifecycle;
  bool _disposed = false;
  Object? _mediaKey, _stateKey;

  void publish() {
    if (_disposed) return;
    final text = strings();
    final state = mediaStateFor(
      controller.state,
      text,
      reason: controller.stopReason,
      error: controller.error?.googleMessage,
    );
    final book = card();
    final item = (!state.session && controller.state != NarrationState.stopped) || book == null
        ? null
        : MediaItem(
            id: book.id,
            title: book.title,
            artist: book.chapter,
            artUri: book.art,
            displayTitle: book.title,
            displaySubtitle: book.chapter,
            displayDescription: state.message,
            // Длительности нет: карточка управляет отрезками, а не секундами.
          );
    // MediaItem сравнивается пакетом только по id; глава и статус одной книги
    // тоже должны обновлять карточку.
    final mediaKey = item == null ? null : (item.id, item.title, item.artist, item.artUri, item.displayDescription);
    if (_mediaKey != mediaKey) {
      _mediaKey = mediaKey;
      mediaItem.add(item);
    }
    final stateKey = (
      controller.state,
      controller.stopReason,
      state.message,
      controller.speed,
      text.play,
      text.pause,
      text.previous,
      text.next,
    );
    if (_stateKey == stateKey) return;
    _stateKey = stateKey;
    final stopped = controller.state == NarrationState.stopped;
    final controls = !state.session
        ? <MediaControl>[]
        : [
            if (!stopped)
              MediaControl(
                androidIcon: 'drawable/audio_service_skip_previous',
                label: text.previous,
                action: MediaAction.skipToPrevious,
              ),
            if (state.playing)
              MediaControl(androidIcon: 'drawable/audio_service_pause', label: text.pause, action: MediaAction.pause)
            else if (!stopped || controller.stopReason == StopReason.error)
              MediaControl(
                androidIcon: 'drawable/audio_service_play_arrow',
                label: text.play,
                action: MediaAction.play,
              ),
            if (!stopped)
              MediaControl(
                androidIcon: 'drawable/audio_service_skip_next',
                label: text.next,
                action: MediaAction.skipToNext,
              ),
          ];
    playbackState.add(
      PlaybackState(
        processingState: state.processing,
        playing: state.playing,
        controls: controls,
        androidCompactActionIndices: List.generate(controls.length, (i) => i),
        systemActions: const {},
        speed: controller.speed,
        errorCode: state.processing == AudioProcessingState.error ? 1 : null,
        errorMessage: state.processing == AudioProcessingState.error ? state.message : null,
      ),
    );
  }

  Future<void> readyForFocus() async {
    if (!controller.isActive || controller.state == NarrationState.paused) {
      return;
    }
    await lifecycle.awaitForeground();
  }

  @override
  Future<void> play() async => controller.resume();
  @override
  Future<void> pause() async => controller.pause();
  @override
  Future<void> skipToNext() async {
    if (controller.isActive) controller.next();
  }

  @override
  Future<void> skipToPrevious() async {
    if (controller.isActive) controller.previous();
  }

  @override
  Future<void> stop() async => controller.close();
  @override
  Future<void> onTaskRemoved() async {
    // Смахивание окна не закрывает книгу и не останавливает службу.
  }
  @override
  Future<void> onNotificationDeleted() async {
    if (!controller.isActive) controller.close();
  }

  void dispose() {
    _disposed = true;
    controller.removeListener(publish);
  }
}

/// Аудиофокус принадлежит прослушиванию также во время подготовки и ожидания,
/// поэтому звонок до первого файла тоже снимает намерение играть.
abstract interface class AudioFocusSession {
  Stream<AudioInterruptionEvent> get interruptions;
  Stream<void> get noisy;
  Future<bool> setActive(bool active);
}

class SystemAudioFocusSession implements AudioFocusSession {
  SystemAudioFocusSession(this.session);
  final AudioSession session;
  @override
  Stream<AudioInterruptionEvent> get interruptions => session.interruptionEventStream;
  @override
  Stream<void> get noisy => session.becomingNoisyEventStream;
  @override
  Future<bool> setActive(bool active) => session.setActive(active);
}

class NarrationAudioFocus {
  NarrationAudioFocus({
    required this.controller,
    required this.sampler,
    required this.session,
    required this.media,
    required this.failed,
  }) {
    _interruptions = session.interruptions.listen((event) {
      if (event.begin) _pause();
    });
    _noisy = session.noisy.listen((_) => _pause());
    controller.addListener(_changed);
    sampler.addListener(_sampleChanged);
  }
  final NarrationController controller;
  final VoiceSampler sampler;
  final AudioFocusSession session;
  final NarrationMediaHandler media;
  final void Function(Object, StackTrace) failed;
  late final StreamSubscription<AudioInterruptionEvent> _interruptions;
  late final StreamSubscription<void> _noisy;
  Future<bool>? _activation;
  Future<void> _operations = Future.value();
  int? _activationRevision;
  bool _active = false, _disposed = false;
  int _revision = 0;

  Future<bool> _setActive(bool active, {int? revision}) {
    final result = _operations.then<bool>((_) async {
      if (revision != null && revision != _revision) return false;
      return session.setActive(active);
    });
    // Ошибку получает вызывающий; следующая команда не застревает на ней.
    _operations = result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  void _release() {
    unawaited(
      _setActive(false).catchError((Object error, StackTrace stack) {
        failed(error, stack);
        return false;
      }),
    );
  }

  void _sampleChanged() {
    if ((sampler.state == SampleState.idle || sampler.state == SampleState.failed) &&
        (!controller.isActive || controller.state == NarrationState.paused)) {
      _release();
    }
  }

  void _pause() {
    _revision++;
    _active = false;
    controller.pause();
    sampler.stop();
  }

  void _changed() {
    if (_disposed) return;
    if (controller.isActive && controller.state != NarrationState.paused) {
      final revision = _revision;
      unawaited(
        activateNarration().catchError((Object error, StackTrace stack) {
          if (revision == _revision) failed(error, stack);
          return false;
        }),
      );
    } else {
      _revision++;
      _active = false;
      if (sampler.state != SampleState.playing) _release();
    }
  }

  Future<bool> activateNarration() {
    if (_active) return Future.value(true);
    if (_activationRevision == _revision && _activation != null) return _activation!;
    _activationRevision = _revision;
    return _activation = _activate(_revision);
  }

  Future<bool> _activate(int revision) async {
    await media.readyForFocus();
    if (_disposed || revision != _revision || !controller.isActive || controller.state == NarrationState.paused) {
      return false;
    }
    final allowed = await _setActive(true, revision: revision);
    if (_disposed || revision != _revision) return false;
    _active = allowed;
    if (!allowed) controller.pause();
    return allowed;
  }

  Future<bool> activateSample() => _setActive(true);
  Future<void> dispose() async {
    _disposed = true;
    _revision++;
    controller.removeListener(_changed);
    sampler.removeListener(_sampleChanged);
    await _interruptions.cancel();
    await _noisy.cancel();
    await _setActive(false);
  }
}
