import 'dart:async';

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
  void changeState(NarrationState value, {StopReason? reason}) {
    state = value;
    stopReason = reason;
    notifyListeners();
  }

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
  int stops = 0;
  Future<void> Function()? onStopForeground;

  @override
  Future<void> stopForeground() async {
    stops++;
    await onStopForeground?.call();
  }

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
  test('stopped on error keeps the response instead of replacing it with end of book', () {
    final state = mediaStateFor(NarrationState.stopped, strings, reason: StopReason.error, error: 'Google error');
    expect(state.message, 'Google error');
    expect(state.foreground, isFalse);
    expect(state.processing, AudioProcessingState.idle);
  });

  test('card has no paragraph or time scale; commands call the controller', () async {
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
    expect(handler.mediaItem.value, isNull);
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
    expect(handler.playbackState.value.controls, isEmpty);
    await handler.onTaskRemoved();
    expect(controller.calls, hasLength(4));
    controller.state = NarrationState.idle;
    handler.publish();
    expect(handler.mediaItem.value, isNull);
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
  });

  for (final row in [
    (NarrationState.playing, NarrationState.stopped, StopReason.endOfBook, 'end of book'),
    (NarrationState.playing, NarrationState.idle, null, 'close button'),
    (NarrationState.playing, NarrationState.idle, null, 'opening another book'),
    (NarrationState.paused, NarrationState.idle, null, 'closing while paused'),
  ]) {
    test('${row.$4}: idle, foreground released, new Listen', () async {
      final controller = RecordingNarration();
      final lifecycle = RecordingLifecycle();
      var card = const MediaCard(id: 'book', title: 'Title', chapter: 'Chapter');
      final handler = NarrationMediaHandler(
        controller: controller,
        strings: () => strings,
        card: () => card,
        lifecycle: lifecycle,
      );
      final events = <Object?>[];
      var foreground = false;
      var notification = false;
      var wasPlaying = false;
      final items = handler.mediaItem.listen(events.add);
      final states = handler.playbackState.listen((state) {
        events.add((state.processingState, state.playing));
        // audio_service 0.18.19: enterPlayingState on false -> true.
        if (!wasPlaying && state.playing) foreground = notification = true;
        wasPlaying = state.playing;
        // idle calls stopSelf, but the bound service stays foreground.
      });
      addTearDown(() async {
        handler.dispose();
        await items.cancel();
        await states.cancel();
        controller.dispose();
      });
      final bridgeReply = Completer<void>();
      lifecycle.onStopForeground = () async {
        await bridgeReply.future;
        expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
        foreground = notification = false;
        events.add('stopForeground');
      };
      await Future<void>.delayed(Duration.zero);
      if (row.$1 == NarrationState.paused) {
        controller.changeState(NarrationState.paused);
        await Future<void>.delayed(Duration.zero);
      }
      expect(foreground, isTrue);
      expect(notification, isTrue);
      events.clear();

      controller.changeState(row.$2, reason: row.$3);
      await Future<void>.delayed(Duration.zero);
      expect(events, [null, (AudioProcessingState.idle, false)]);
      expect(handler.playbackState.value.controls, isEmpty);
      expect(lifecycle.stops, 1);
      // A late card update or a repeated publish must not bring the notification back.
      card = const MediaCard(id: 'other', title: 'Other', chapter: 'Other chapter');
      handler.publish();
      bridgeReply.complete();
      await Future<void>.delayed(Duration.zero);
      expect(events, [null, (AudioProcessingState.idle, false), 'stopForeground']);
      expect(foreground, isFalse);
      expect(notification, isFalse);
      handler.publish();
      await Future<void>.delayed(Duration.zero);
      expect(events.last, 'stopForeground');
      expect(lifecycle.stops, 1);

      controller.changeState(NarrationState.preparing);
      await Future<void>.delayed(Duration.zero);
      await handler.readyForFocus();
      expect(events[events.length - 2], isA<MediaItem>().having((item) => item.id, 'id', 'other'));
      expect(events.last, (AudioProcessingState.loading, true));
      expect(foreground, isTrue);
      expect(notification, isTrue);
      expect(lifecycle.calls, 1);
      controller.changeState(NarrationState.playing);
      await Future<void>.delayed(Duration.zero);
      expect(events.last, (AudioProcessingState.ready, true));
      expect(lifecycle.stops, 1);
    });
  }

  test('a plain pause keeps foreground and the card, the stop bridge is not called', () async {
    final controller = RecordingNarration();
    final lifecycle = RecordingLifecycle();
    final handler = NarrationMediaHandler(
      controller: controller,
      strings: () => strings,
      card: () => const MediaCard(id: 'book', title: 'Title', chapter: 'Chapter'),
      lifecycle: lifecycle,
    );
    final states = <(AudioProcessingState, bool)>[];
    final subscription = handler.playbackState.listen((state) {
      states.add((state.processingState, state.playing));
    });
    addTearDown(() async {
      handler.dispose();
      await subscription.cancel();
      controller.dispose();
    });
    await Future<void>.delayed(Duration.zero);
    controller.changeState(NarrationState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(states, [(AudioProcessingState.ready, true), (AudioProcessingState.ready, false)]);
    expect(handler.mediaItem.value!.displayDescription, 'Paused');
    expect(handler.playbackState.value.controls.map((control) => control.action), contains(MediaAction.play));
    expect(lifecycle.stops, 0);
  });

  test('a new Listen waits for the bridge to confirm the previous foreground is released', () async {
    final controller = RecordingNarration();
    final lifecycle = RecordingLifecycle();
    final bridgeReply = Completer<void>();
    lifecycle.onStopForeground = () => bridgeReply.future;
    final handler = NarrationMediaHandler(
      controller: controller,
      strings: () => strings,
      card: () => const MediaCard(id: 'book', title: 'Title', chapter: 'Chapter'),
      lifecycle: lifecycle,
    );
    addTearDown(handler.dispose);
    addTearDown(controller.dispose);
    controller.changeState(NarrationState.idle);
    controller.changeState(NarrationState.preparing);
    final focusReady = handler.readyForFocus();
    await Future<void>.delayed(Duration.zero);
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
    expect(handler.mediaItem.value, isNull);
    expect(lifecycle.calls, 0);
    bridgeReply.complete();
    await focusReady;
    expect(handler.playbackState.value.processingState, AudioProcessingState.loading);
    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.mediaItem.value, isNotNull);
    expect(lifecycle.calls, 1);
    expect(lifecycle.stops, 1);
  });
}
