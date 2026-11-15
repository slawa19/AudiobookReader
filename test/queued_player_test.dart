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
    items.add(item);
    // Android just_audio.onTimelineChanged переводит STATE_ENDED на следующий
    // файл, если playWhenReady ещё true. Принимаем и такой порядок событий.
    if (advanceWhenAppendedToCompleted && snapshot.completed && snapshot.playing) {
      nativeAutoStarts.add(item);
      emit(EnginePlayback(item: item, playing: true, ready: true));
    }
  });
  @override
  Future<void> seek(int index) => operation('seek:$index', () async {
    if (index >= items.length) throw RangeError.index(index, items);
    emit(EnginePlayback(item: items[index], ready: true));
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
  Future<void> dispose() => operation('dispose', updates.close);
}

PlayerItem item(int segment) =>
    PlayerItem(file: File('/synthetic-$segment.wav'), segment: segment, duration: const Duration(seconds: 2));

class Harness {
  final engines = <TestEngine>[];
  final events = <PlayerEvent>[];
  late final player = QueuedPlayer(
    createEngine: () {
      final engine = TestEngine();
      engines.add(engine);
      return engine;
    },
    beforePlay: () async => true,
    readDuration: (_) async => const Duration(seconds: 2),
  );
  Harness() {
    player.events.listen(events.add);
    addTearDown(player.dispose);
  }
  TestEngine get engine => engines.last;
  Iterable<PlayerEvent> get drained => events.where((e) => e.kind == PlayerEventKind.drained);
  Iterable<PlayerItem?> get started => events.where((e) => e.kind == PlayerEventKind.started).map((e) => e.item);
}

void main() {
  test('исчерпание внутри вставки: очередь не пропускает принятый append', () async {
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
    expect(h.player.playbackFailure, isNull);
    h.engine.finish();
    expect(h.player.current, same(c));
    h.engine.finish();
    expect(h.player.current, isNull);
    expect(h.drained, hasLength(1));
    expect(h.drained.single.item, isNull);
  });

  test('добавление до конца не делает seek и не сообщает drained между файлами', () async {
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
    test('append после drained: ${paused ? 'пауза до явного play' : 'сохранено намерение играть'}', () async {
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

  test('pause и speed ждут вставку; после выполнения очереди движок на паузе', () async {
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

  test('clear отделяет старые события и ждёт вставку перед освобождением', () async {
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

  test('retainThrough отсекает уже загруженный хвост; новый append после конца разрешён', () async {
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
