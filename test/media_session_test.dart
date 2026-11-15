import 'package:audio_service/audio_service.dart';
import 'package:audiobook_reader/playback/media_session.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:flutter_test/flutter_test.dart';

const strings = MediaStrings(
  channel: 'Books',
  preparing: 'Preparing',
  waiting: 'Waiting',
  paused: 'Paused',
  ended: 'Ended',
  play: 'Listen',
  pause: 'Pause',
  previous: 'Previous',
  next: 'Next',
);

class RecordingNarration extends NarrationController {
  @override
  NarrationState state = NarrationState.playing;
  @override
  StopReason? stopReason;
  @override
  NarrationError? error;
  @override
  double get speed => 1;
  final calls = <String>[];
  @override
  void resume() => calls.add('resume');
  @override
  void pause() => calls.add('pause');
  @override
  void next() => calls.add('next');
  @override
  void previous() => calls.add('previous');
  @override
  void close({dynamic screenPosition}) => calls.add('close');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RecordingLifecycle implements MediaServiceLifecycle {
  int calls = 0;
  @override
  Future<void> awaitForeground() async {
    calls++;
  }
}

void main() {
  final rows = [
    (NarrationState.idle, false, false, false, AudioProcessingState.idle, null),
    (NarrationState.preparing, true, true, true, AudioProcessingState.loading, 'Preparing'),
    (NarrationState.playing, true, true, true, AudioProcessingState.ready, null),
    (NarrationState.waiting, true, true, true, AudioProcessingState.buffering, 'Waiting'),
    (NarrationState.paused, true, true, false, AudioProcessingState.ready, 'Paused'),
    (NarrationState.stopped, false, false, false, AudioProcessingState.idle, 'Ended'),
  ];
  for (final row in rows) {
    test('А§6.6: ${row.$1.name}', () {
      final actual = mediaStateFor(row.$1, strings, reason: StopReason.endOfBook);
      expect(
        (actual.session, actual.foreground, actual.playing, actual.processing, actual.message),
        (row.$2, row.$3, row.$4, row.$5, row.$6),
      );
    });
  }
  test('stopped по ошибке сохраняет ответ без замены на конец книги', () {
    final state = mediaStateFor(NarrationState.stopped, strings, reason: StopReason.error, error: 'Google error');
    expect(state.message, 'Google error');
    expect(state.foreground, isFalse);
    expect(state.processing, AudioProcessingState.idle);
  });

  test('карточка без абзаца и шкалы времени; команды вызывают контроллер', () async {
    final controller = RecordingNarration();
    final lifecycle = RecordingLifecycle();
    final handler = NarrationMediaHandler(
      controller: controller,
      strings: () => strings,
      card: () => MediaCard(id: 'book', title: 'Title', chapter: 'Chapter', art: Uri.file('/cover.jpg')),
      lifecycle: lifecycle,
    );
    addTearDown(handler.dispose);
    addTearDown(controller.dispose);
    expect(handler.mediaItem.value!.title, 'Title');
    expect(handler.mediaItem.value!.artist, 'Chapter');
    expect(handler.mediaItem.value!.artUri, Uri.file('/cover.jpg'));
    expect(handler.mediaItem.value!.duration, isNull);
    expect(handler.playbackState.value.systemActions, isEmpty);
    await handler.play();
    await handler.pause();
    await handler.skipToPrevious();
    await handler.skipToNext();
    expect(controller.calls, ['resume', 'pause', 'previous', 'next']);
    await handler.readyForFocus();
    expect(lifecycle.calls, 1);
    controller.state = NarrationState.paused;
    await handler.readyForFocus();
    expect(lifecycle.calls, 1);
    controller.state = NarrationState.stopped;
    controller.stopReason = StopReason.endOfBook;
    handler.publish();
    await handler.skipToPrevious();
    await handler.skipToNext();
    expect(controller.calls, ['resume', 'pause', 'previous', 'next']);
    expect(handler.mediaItem.value!.displayDescription, 'Ended');
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
    expect(handler.playbackState.value.controls, isEmpty);
    await handler.onTaskRemoved();
    expect(controller.calls, hasLength(4));
    controller.state = NarrationState.idle;
    handler.publish();
    expect(handler.mediaItem.value, isNull);
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
  });
}
