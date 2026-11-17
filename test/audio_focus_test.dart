import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:audiobook_reader/playback/media_session.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/playback/voice_sample.dart';
import 'package:flutter_test/flutter_test.dart';

import 'media_session_test.dart' show RecordingNarration, strings;

class FocusController extends RecordingNarration {
  void change(NarrationState value) {
    state = value;
    notifyListeners();
  }

  @override
  void pause() {
    super.pause();
    change(NarrationState.paused);
  }

  @override
  void resume() {
    super.resume();
    change(NarrationState.preparing);
  }
}

class Sample extends VoiceSampler {
  @override
  SampleState state = SampleState.idle;
  int stops = 0;
  @override
  void stop() {
    stops++;
    state = SampleState.idle;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Session implements AudioFocusSession {
  final interruptionsController = StreamController<AudioInterruptionEvent>.broadcast(sync: true);
  final noisyController = StreamController<void>.broadcast(sync: true);
  final calls = <bool>[];
  Completer<bool>? nextActivation;
  bool allowed = true;
  @override
  Stream<AudioInterruptionEvent> get interruptions => interruptionsController.stream;
  @override
  Stream<void> get noisy => noisyController.stream;
  @override
  Future<bool> setActive(bool active) async {
    calls.add(active);
    if (active && nextActivation != null) {
      final pending = nextActivation!;
      nextActivation = null;
      return pending.future;
    }
    return allowed;
  }

  Future<void> dispose() async {
    await interruptionsController.close();
    await noisyController.close();
  }
}

class ForegroundGate implements MediaServiceLifecycle {
  final started = Completer<void>();
  @override
  Future<void> awaitForeground() => started.future;
  @override
  Future<void> stopForeground() async {}
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  for (final state in [NarrationState.preparing, NarrationState.waiting, NarrationState.playing]) {
    for (final noisy in [false, true]) {
      test('${state.name}: ${noisy ? 'headphones' : 'interruption'} pause, the end does not resume', () async {
        final controller = FocusController()..state = NarrationState.idle;
        final sample = Sample();
        final session = Session();
        final gate = ForegroundGate();
        final media = NarrationMediaHandler(
          controller: controller,
          strings: () => strings,
          card: () => null,
          lifecycle: gate,
        );
        final errors = <Object>[];
        final focus = NarrationAudioFocus(
          controller: controller,
          sampler: sample,
          session: session,
          media: media,
          failed: (e, _) => errors.add(e),
        );
        controller.change(state);
        await settle();
        expect(session.calls, isEmpty, reason: 'focus waits for a confirmed service');
        gate.started.complete();
        await settle();
        expect(session.calls, [true]);
        if (noisy) {
          session.noisyController.add(null);
        } else {
          session.interruptionsController.add(AudioInterruptionEvent(true, AudioInterruptionType.duck));
        }
        await settle();
        expect(controller.state, NarrationState.paused);
        expect(sample.stops, 1);
        session.interruptionsController.add(AudioInterruptionEvent(false, AudioInterruptionType.pause));
        await settle();
        expect(controller.calls, ['pause']);
        expect(controller.state, NarrationState.paused);
        expect(errors, isEmpty);
        await focus.dispose();
        media.dispose();
        controller.dispose();
        sample.dispose();
        await session.dispose();
      });
    }
  }

  test('a late focus reply before the pause does not cancel a new resume', () async {
    final controller = FocusController()..state = NarrationState.idle;
    final sample = Sample();
    final session = Session();
    final gate = ForegroundGate()..started.complete();
    final media = NarrationMediaHandler(
      controller: controller,
      strings: () => strings,
      card: () => null,
      lifecycle: gate,
    );
    final focus = NarrationAudioFocus(
      controller: controller,
      sampler: sample,
      session: session,
      media: media,
      failed: (e, _) => fail('$e'),
    );
    final pending = Completer<bool>();
    session.nextActivation = pending;
    controller.change(NarrationState.preparing);
    final first = focus.activateNarration();
    await settle();
    controller.pause();
    controller.resume();
    final second = focus.activateNarration();
    pending.complete(true);
    expect(await first, isFalse);
    expect(await second, isTrue);
    expect(session.calls.first, isTrue);
    expect(session.calls.last, isTrue);
    expect(session.calls.sublist(1, session.calls.length - 1), everyElement(isFalse));
    expect(controller.calls, ['pause', 'resume']);
    await focus.dispose();
    media.dispose();
    controller.dispose();
    sample.dispose();
    await session.dispose();
  });
}
