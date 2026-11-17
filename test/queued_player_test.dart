import 'dart:async';
import 'dart:io';

import 'package:audiobook_reader/playback/player.dart';
import 'package:audiobook_reader/playback/queued_player.dart';
import 'package:flutter_test/flutter_test.dart';

class TestEngine implements PlaylistEngine {
  final updates = StreamController<EnginePlayback>.broadcast(sync: true);
  final items = <PlayerItem>[];
  final calls = <String>[];
  Completer<void>? appendGate, appendEntered;
  int operations = 0;
  bool overlap = false;
  double speed = 1;
  bool advanceWhenAppendedToCompleted = false;
  final nativeAutoStarts = <PlayerItem>[];
  Object? loadFailure, appendFailure, playFailure, disposeFailure;
  bool holdStart = false;
  @override
  EnginePlayback snapshot = const EnginePlayback();
  @override
  Stream<EnginePlayback> get events => updates.stream;
  void emit(EnginePlayback state) {
    snapshot = state;
    updates.add(state);
  }

  Future<void> operation(String name, Future<void> Function() action) async {
    if (operations != 0) overlap = true;
    operations++;
    calls.add(name);
    try {
      await action();
    } finally {
      operations--;
    }
  }

  @override
  Future<void> load(PlayerItem item) => operation('load:${item.segment}', () async {
    if (loadFailure != null) throw loadFailure!;
    items.add(item);
    emit(EnginePlayback(item: item, ready: true));
  });
  @override
  Future<void> append(PlayerItem item) => operation('append:${item.segment}', () async {
    appendEntered?.complete();
    appendEntered = null;
    final gate = appendGate;
    appendGate = null;
    if (gate != null) await gate.future;
    if (appendFailure != null) throw appendFailure!;
    items.add(item);
    // Android just_audio.onTimelineChanged moves STATE_ENDED to the next
    // file if playWhenReady is still true. This event order is accepted too.
    if (advanceWhenAppendedToCompleted && snapshot.completed && snapshot.playing) {
      nativeAutoStarts.add(item);
      emit(EnginePlayback(item: item, playing: true, ready: true));
    }
  });
  @override
  Future<void> seek(int index, {Duration position = Duration.zero}) => operation('seek:$index', () async {
    if (index >= items.length) throw RangeError.index(index, items);
    emit(EnginePlayback(item: items[index], position: position, ready: true));
  });
  @override
  Future<void> retain(int count) => operation('retain:$count', () async {
    items.removeRange(count, items.length);
  });
  @override
  Future<void> setSpeed(double value) => operation('speed:$value', () async {
    speed = value;
  });
  @override
  void play() {
    if (operations != 0) overlap = true;
    calls.add('play');
    if (playFailure != null) throw playFailure!;
    if (holdStart) return;
    emit(EnginePlayback(item: snapshot.item, position: snapshot.position, playing: true, ready: true));
  }

  @override
  Future<void> pause() => operation('pause', () async {
    emit(EnginePlayback(item: snapshot.item, position: snapshot.position, ready: true, completed: snapshot.completed));
  });
  void finish() {
    final index = items.indexOf(snapshot.item!);
    if (index + 1 < items.length) {
      emit(EnginePlayback(item: items[index + 1], playing: snapshot.playing, ready: true));
    } else {
      emit(EnginePlayback(item: snapshot.item, playing: snapshot.playing, completed: true));
    }
  }

  @override
  Future<void> dispose() => operation('dispose', () async {
    snapshot = EnginePlayback(item: snapshot.item, position: snapshot.position);
    await updates.close();
    if (disposeFailure != null) throw disposeFailure!;
  });
}

PlayerItem item(int segment) =>
    PlayerItem(file: File('/synthetic-$segment.wav'), segment: segment, duration: const Duration(seconds: 2));

class Harness {
  final TestEngine? firstEngine;
  final engines = <TestEngine>[];
  final events = <PlayerEvent>[];
  late final player = QueuedPlayer(
    createEngine: () {
      final engine = engines.isEmpty ? firstEngine ?? TestEngine() : TestEngine();
      engines.add(engine);
      return engine;
    },
    beforePlay: () async => true,
    readDuration: (_) async => const Duration(seconds: 2),
  );
  Harness({this.firstEngine}) {
    player.events.listen(events.add);
    addTearDown(player.dispose);
  }
  TestEngine get engine => engines.last;
  Iterable<PlayerEvent> get drained => events.where((e) => e.kind == PlayerEventKind.drained);
  Iterable<PlayerItem?> get started => events.where((e) => e.kind == PlayerEventKind.started).map((e) => e.item);
}

void main() {
  test('FR-2: a release error does not stop the commands of the new list', () async {
    final h = Harness();
    h.player.append(item(0));
    h.player.play();
    await h.player.settled;
    h.engine.disposeFailure = StateError('dispose failed');
    h.player.clear(1);
    await expectLater(h.player.settled, throwsStateError);
    final next = item(1);
    h.player.append(next);
    h.player.play();
    await h.player.settled;
    expect(h.engines, hasLength(2));
    expect(h.engine.items, [next]);
    expect(h.player.playing, isTrue);
    expect(h.started.last, same(next));
  });

  test('current is set synchronously from the source instance; clear and drained reset it', () async {
    final h = Harness();
    final a = item(0), b = item(1);
    expect(h.player.current, isNull);
    h.player.append(a);
    expect(h.player.current, same(a));
    expect(h.engines, isEmpty, reason: 'the platform queue has not run yet');
    h.player.clear(3);
    expect(h.player.current, isNull);
    h.player.append(b);
    expect(h.player.current, same(b));
    h.player.play();
    await h.player.settled;
    expect(h.events.single.item, same(b));
    expect(h.events.single.generation, 3);
    h.engine.finish();
    expect(h.player.current, isNull);
    expect(h.player.position, Duration.zero);
    expect(h.player.playing, isFalse);
  });

  test('play is idempotent; started waits for the actual start, progress follows the current file', () async {
    final h = Harness();
    final a = item(0), b = item(1);
    h.player.append(a);
    h.player.append(b);
    await h.player.settled;
    h.engine.holdStart = true;
    h.player.play();
    h.player.play();
    h.player.play();
    await h.player.settled;
    expect(h.player.playing, isFalse);
    expect(h.engine.calls.where((c) => c == 'play'), hasLength(1));
    expect(h.started, isEmpty);
    h.engine.emit(EnginePlayback(item: a, ready: true, playing: true));
    expect(h.started.single, same(a));
    final plays = h.engine.calls.where((c) => c == 'play').length;
    h.player.play();
    h.player.play();
    await h.player.settled;
    expect(h.engine.calls.where((c) => c == 'play'), hasLength(plays));
    for (var i = 1; i <= 5; i++) {
      h.engine.emit(
        EnginePlayback(
          item: a,
          ready: true,
          playing: true,
          progress: true,
          position: Duration(milliseconds: i * 100),
        ),
      );
      expect(h.player.position, Duration(milliseconds: i * 100));
    }
    expect(h.events.where((e) => e.kind == PlayerEventKind.progress), hasLength(5));
    expect(h.events.where((e) => e.kind == PlayerEventKind.progress).every((e) => identical(e.item, a)), isTrue);
    h.engine.finish();
    expect(h.player.current, same(b));
    expect(h.player.position, Duration.zero);
    expect(h.started, [a, b]);
  });

  test(
    'position is still right after pause, including before the command is applied; resume restores the place',
    () async {
      final h = Harness();
      final a = item(0);
      h.player.append(a);
      h.player.play();
      await h.player.settled;
      h.engine.emit(
        EnginePlayback(
          item: a,
          ready: true,
          playing: true,
          progress: true,
          position: const Duration(milliseconds: 450),
        ),
      );
      h.player.pause();
      final paused = h.player.position;
      expect(paused, const Duration(milliseconds: 450));
      final progress = h.events.length;
      h.engine.emit(
        EnginePlayback(
          item: a,
          ready: true,
          playing: true,
          progress: true,
          position: const Duration(milliseconds: 650),
        ),
      );
      expect(h.player.position, paused);
      expect(h.events, hasLength(progress));
      await h.player.settled;
      expect(h.player.position, paused);
      h.player.play();
      await h.player.settled;
      expect(h.engine.snapshot.position, paused);
      expect(h.player.position, paused);
      expect(h.started, [a], reason: 'continuing the same file does not create a second started');
    },
  );

  test('retainThrough keeps the sounding current even with a boundary before it', () async {
    final h = Harness();
    final a = item(0), b = item(1), c = item(2);
    for (final next in [a, b, c]) {
      h.player.append(next);
    }
    h.player.play();
    await h.player.settled;
    h.engine.finish();
    h.engine.emit(
      EnginePlayback(item: b, playing: true, ready: true, progress: true, position: const Duration(milliseconds: 250)),
    );
    h.player.retainThrough(-1);
    expect(h.player.current, same(b));
    await h.player.settled;
    expect(h.engine.items, [a, b]);
    expect(h.player.current, same(b));
    expect(h.player.position, const Duration(milliseconds: 250));
    expect(h.player.playing, isTrue);
    expect(h.engine.calls, isNot(contains('pause')));
  });

  for (final operation in ['load', 'append', 'play', 'stream']) {
    test('failed during $operation: source item, generation, audio stopped and the tail does not play', () async {
      final unsafe = StateError('secret /private/owner/book.wav');
      final engine = TestEngine();
      if (operation == 'load') engine.loadFailure = unsafe;
      final h = Harness(firstEngine: engine);
      final a = item(0), b = item(1), c = item(2);
      h.player.clear(4);
      PlayerItem failedItem = a;
      var stoppedBeforeEvent = false;
      h.player.events.listen((e) {
        if (e.kind == PlayerEventKind.failed) stoppedBeforeEvent = !engine.snapshot.playing;
      });
      h.player.append(a);
      if (operation == 'load') {
        h.player.append(b);
        h.player.play();
      } else if (operation == 'append') {
        h.player.play();
        await h.player.settled;
        engine.appendFailure = unsafe;
        failedItem = b;
        h.player.append(b);
      } else if (operation == 'play') {
        await h.player.settled;
        engine.playFailure = unsafe;
        h.player.play();
      } else {
        h.player.play();
        await h.player.settled;
        engine.updates.addError(EngineFailure(a));
      }
      h.player.append(c);
      await h.player.settled;
      final failure = h.events.where((e) => e.kind == PlayerEventKind.failed).single;
      expect(failure.item, same(failedItem));
      expect(failure.generation, 4);
      expect(failure.toString(), isNot(contains('private')));
      expect(stoppedBeforeEvent, isTrue);
      expect(h.player.playing, isFalse);
      expect(engine.calls, isNot(contains('append:2')));
      final calls = engine.calls.length;
      h.player.play();
      await h.player.settled;
      expect(engine.calls, hasLength(calls));
      h.player.clear(5);
      h.player.append(c);
      h.player.play();
      await h.player.settled;
      expect(h.player.playing, isTrue);
      expect(h.events.last.generation, 5);
      expect(h.events.last.item, same(c));
    });
  }

  test('exhaustion inside an insert: the queue does not drop an accepted append', () async {
    final h = Harness();
    final a = item(0), b = item(1), c = item(2);
    h.player.append(a);
    h.player.play();
    await h.player.settled;
    final entered = Completer<void>(), gate = Completer<void>();
    h.engine.appendEntered = entered;
    h.engine.appendGate = gate;
    h.player.append(b);
    h.player.append(c);
    await entered.future;
    h.engine.finish();
    expect(h.drained, isEmpty);
    expect(h.player.current, same(b));
    expect(h.engine.items, [a]);
    gate.complete();
    await h.player.settled;
    expect(h.engine.calls.where((c) => c.startsWith('seek')), ['seek:1']);
    expect(h.player.current, same(b));
    expect(h.started, [a, b]);
    expect(h.engine.overlap, isFalse);
    expect(h.events.any((e) => e.kind == PlayerEventKind.failed), isFalse);
    h.engine.finish();
    expect(h.player.current, same(c));
    h.engine.finish();
    expect(h.player.current, isNull);
    expect(h.drained, hasLength(1));
    expect(h.drained.single.item, isNull);
  });

  test('appending before the end does not seek and does not report drained between files', () async {
    final h = Harness();
    final a = item(0), b = item(1);
    h.player.append(a);
    h.player.play();
    await h.player.settled;
    h.player.append(b);
    await h.player.settled;
    h.engine.finish();
    expect(h.drained, isEmpty);
    expect(h.started, [a, b]);
    expect(h.engine.calls.any((c) => c.startsWith('seek')), isFalse);
    h.engine.finish();
    expect(h.drained, hasLength(1));
  });

  for (final paused in [false, true]) {
    test('append after drained: ${paused ? 'paused until an explicit play' : 'the intent to play is kept'}', () async {
      final h = Harness();
      final a = item(0), b = item(1);
      h.player.append(a);
      h.player.play();
      await h.player.settled;
      h.engine.advanceWhenAppendedToCompleted = true;
      h.engine.finish();
      expect(h.player.current, isNull);
      if (paused) h.player.pause();
      h.player.append(b);
      await h.player.settled;
      expect(h.engine.calls, contains('seek:1'));
      expect(h.engine.nativeAutoStarts, isEmpty);
      expect(h.player.current, same(b));
      expect(h.player.playing, !paused);
      if (paused) {
        expect(h.started, [a]);
        h.player.play();
        await h.player.settled;
      }
      expect(h.started, [a, b]);
    });
  }

  test('pause and speed wait for the insert; after the queue runs the engine is paused', () async {
    final h = Harness();
    final a = item(0), b = item(1);
    h.player.setSpeed(2);
    h.player.append(a);
    h.player.play();
    await h.player.settled;
    expect(h.engine.speed, 2);
    final gate = Completer<void>(), entered = Completer<void>();
    h.engine.advanceWhenAppendedToCompleted = true;
    h.engine.appendGate = gate;
    h.engine.appendEntered = entered;
    h.player.append(b);
    await entered.future;
    h.engine.finish();
    h.player.pause();
    h.player.setSpeed(1.5);
    expect(h.engine.calls.last, 'append:1');
    gate.complete();
    await h.player.settled;
    expect(h.engine.overlap, isFalse);
    expect(h.engine.nativeAutoStarts, [b]);
    expect(h.player.playing, isFalse);
    expect(h.engine.speed, 1.5);
    expect(h.started, [a]);
    h.player.play();
    await h.player.settled;
    expect(h.started, [a, b]);
  });

  test('clear separates old events and waits for the insert before releasing', () async {
    final h = Harness();
    final a = item(0), b = item(1), fresh = item(2);
    h.player.append(a);
    h.player.play();
    await h.player.settled;
    final old = h.engine;
    final gate = Completer<void>(), entered = Completer<void>();
    old.appendGate = gate;
    old.appendEntered = entered;
    h.player.append(b);
    await entered.future;
    h.player.clear(7);
    expect(h.player.current, isNull);
    old.finish();
    old.emit(EnginePlayback(item: a, playing: true, ready: true, progress: true, position: const Duration(seconds: 1)));
    old.updates.addError(EngineFailure(a));
    h.player.append(fresh);
    h.player.play();
    gate.complete();
    await h.player.settled;
    expect(old.calls.last, 'dispose');
    expect(old.overlap, isFalse);
    expect(h.drained, isEmpty);
    expect(h.started, [a, fresh]);
    expect(h.events.last.generation, 7);
    expect(h.events.last.item, same(fresh));
  });

  test('retainThrough cuts off the already loaded tail; a new append after the end is allowed', () async {
    final h = Harness();
    final a = item(0), b = item(1), c = item(2);
    h.player.append(a);
    h.player.append(b);
    h.player.append(c);
    h.player.play();
    await h.player.settled;
    h.player.retainThrough(0);
    await h.player.settled;
    expect(h.engine.items, [a]);
    h.engine.finish();
    expect(h.player.current, isNull);
    h.player.append(b);
    await h.player.settled;
    expect(h.player.current, same(b));
    expect(h.player.playing, isTrue);
    expect(h.engine.calls.last, 'play');
  });
}
