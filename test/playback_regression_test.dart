import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:audiobook_reader/audio/audio_encoder.dart';
import 'package:audiobook_reader/audio/wav_audio_encoder.dart';
import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/file_library.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/clock.dart';
import 'package:audiobook_reader/playback/fake_player.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/playback/player.dart';
import 'package:audiobook_reader/playback/voice_sample.dart';
import 'package:audiobook_reader/tts/engine.dart';
import 'package:audiobook_reader/tts/fake_engine.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/download_harness.dart';
import 'support/playback_harness.dart';

class ProbePlayer extends FakePlayer {
  ProbePlayer({required super.clock});
  int probes = 0;
  int? probesAtFirstPlay;
  bool rejectAll = false;
  @override
  Future<Duration> duration(File file) {
    probes++;
    if (rejectAll) throw StateError('dummy-secret unsafe exception');
    return super.duration(file);
  }

  @override
  void play() {
    probesAtFirstPlay ??= probes;
    super.play();
  }
}

class UnstartedPlayer extends FakePlayer {
  UnstartedPlayer({required super.clock});
  bool holdStart = true;
  @override
  void play() {
    if (!holdStart) super.play();
  }
}

// currentIndex of the platform engine may stay on the last item.
class StickyPlayer extends FakePlayer {
  StickyPlayer({required super.clock}) {
    events.listen((e) {
      if (e.kind == PlayerEventKind.drained) drained = true;
    });
  }
  bool drained = false;
  @override
  PlayerItem? get current =>
      super.current ?? (drained && items.isNotEmpty ? items.last : null);
  @override
  void play() {
    if (!drained) super.play();
  }

  @override
  void append(PlayerItem item) {
    drained = false;
    super.append(item);
  }

  @override
  void clear(int generation) {
    drained = false;
    super.clear(generation);
  }
}

class ReplayPlayer extends FakePlayer {
  ReplayPlayer({required super.clock}) {
    super.events.listen(replayed.add);
  }
  final replayed = StreamController<PlayerEvent>.broadcast(sync: true);
  @override
  Stream<PlayerEvent> get events => replayed.stream;
  @override
  Future<void> dispose() async {
    await super.dispose();
    await replayed.close();
  }
}

class RollbackClock extends ManualPlaybackClock {
  Duration shift = Duration.zero;
  @override
  DateTime now() => super.now().add(shift);
}

class ObservedLibrary extends FileLibrary {
  ObservedLibrary(
    super.root, {
    required super.settings,
    super.clock,
    super.timer,
    super.parser,
  });
  int positions = 0;
  bool failDelete = false, failFlush = false;
  @override
  void savePosition(
    String bookId,
    ReadingPosition position, {
    double? fraction,
  }) {
    positions++;
    super.savePosition(
      bookId,
      position,
      fraction: fraction,
    );
  }

  @override
  Future<void> deleteBook(String bookId) async {
    if (failDelete) throw StateError('delete denied');
    await super.deleteBook(bookId);
  }

  @override
  Future<void> flush() async {
    if (failFlush) throw const FileSystemException('state write denied');
    await super.flush();
  }
}

class CountedBlocks extends ListBase<Block> {
  CountedBlocks(this.source);
  final List<Block> source;
  final reads = <int, int>{};
  @override
  int get length => source.length;
  @override
  set length(int value) => throw UnsupportedError('immutable');
  @override
  Block operator [](int index) {
    reads.update(index, (v) => v + 1, ifAbsent: () => 1);
    return source[index];
  }

  @override
  void operator []=(int index, Block value) =>
      throw UnsupportedError('immutable');
}

class DiskFullEncoder implements AudioEncoder {
  int attempts = 0;
  bool full = true;
  @override
  String get extension => 'wav';
  @override
  String get formatId => const WavAudioEncoder().formatId;
  @override
  Future<void> encode({
    required String pcmPath,
    required String outputPath,
    required int sampleRate,
  }) async {
    attempts++;
    if (full) throw const FileSystemException('disk full');
    await const WavAudioEncoder().encode(
      pcmPath: pcmPath,
      outputPath: outputPath,
      sampleRate: sampleRate,
    );
  }
}

class UnknownFailureEngine extends FakeTtsEngine {
  @override
  Future<TtsResult> synthesize(String text, VoiceProfile profile) async =>
      throw StateError('dummy-secret unsafe exception');
}

class RetryNearestEngine extends FakeTtsEngine {
  RetryNearestEngine(this.retry)
    : super(manual: true, sampleRate: 100, secondsPerCharacter: secondsPerChar);
  final bool retry;
  @override
  Future<TtsResult> synthesize(String text, VoiceProfile profile) {
    if (retry && text.startsWith('0 ')) {
      enqueue(error: const TemporaryTtsError('retry'));
    }
    return super.synthesize(text, profile);
  }
}

Future<PlaybackHarness> observed(Book source) => PlaybackHarness.create(
  source,
  libraryFactory: (root, settings, clock, parser) => ObservedLibrary(
    root,
    settings: settings,
    clock: clock.now,
    timer: clock.schedule,
    parser: parser,
  ),
);

List<String> longChapter([int count = 14]) => [
  for (var i = 0; i < count; i++) '$i ${'word ' * 110}',
];

// File I/O runs on the wall clock; timers and responses are fake.
Future<void> untilWithProgress(
  bool Function() condition,
  void Function() progress,
  String reason,
) async {
  final wait = Stopwatch()..start();
  while (!condition()) {
    if (wait.elapsed >= const Duration(seconds: 10)) {
      fail('Did not finish within 10 s: $reason');
    }
    progress();
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  test(
    'R9c an error before started leaves preparing and restores the file',
    () async {
      late UnstartedPlayer player;
      final h = await PlaybackHarness.create(
        playbackBook([
          ['Книга.'],
        ]),
        playerFactory: (clock) => player = UnstartedPlayer(clock: clock),
      );
      await h.cache('Книга.');
      h.controller.readFrom(h.book, 0);
      await until(() => player.current != null, 'file preparation before started');
      expect(h.controller.state, NarrationState.preparing);
      player.failCurrent();
      await h.calls(1);
      expect(h.controller.state, NarrationState.preparing);
      expect(h.engine.calls, hasLength(1));
      player.holdStart = false;
      await h.release(0);
      expect(h.controller.state, NarrationState.playing);
    },
  );

  test(
    'R9c a late drained of the old list does not finish the restored audio',
    () async {
      late ReplayPlayer player;
      final h = await PlaybackHarness.create(
        playbackBook([
          ['Первый.', 'Второй.'],
        ]),
        playerFactory: (clock) => player = ReplayPlayer(clock: clock),
      );
      final events = <PlayerEvent>[];
      player.events.listen(events.add);
      await h.cache('Первый.');
      await h.cache('Второй.');
      h.controller.readFrom(h.book, 0);
      await until(
        () => events.isNotEmpty && player.items.length == 2,
        'player event and both files in the list',
      );
      final old = events.first;
      player.failCurrent();
      await h.calls(1);
      await h.release(0);
      expect(h.controller.state, NarrationState.playing);
      player.replayed.add(PlayerEvent(PlayerEventKind.drained, old.generation));
      expect(h.controller.state, NarrationState.playing);
      expect(h.library.isFinished(h.book.id), isFalse);
    },
  );

  test('R9c the sample reports an error of a new port event', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Книга.'],
      ]),
    );
    h.sampler.play(h.profile, bookLanguage: 'ru');
    await h.calls(1);
    await h.release(0);
    expect(h.sampler.state, SampleState.playing);
    h.samplePlayer.failCurrent();
    expect(h.sampler.state, SampleState.failed);
    expect(h.sampler.errorMessage, 'PlayerError: audio file unreadable');
  });

  test(
    'R9a contract of current, pause, retainThrough and a repeated play',
    () async {
      final clock = ManualPlaybackClock();
      final player = FakePlayer(clock: clock);
      addTearDown(player.dispose);
      final events = <PlayerEvent>[];
      player.events.listen(events.add);
      player.clear(1);
      expect(player.current, isNull);
      final first = PlayerItem(
        file: File('first.wav'),
        segment: 1,
        duration: const Duration(seconds: 1),
      );
      final second = PlayerItem(
        file: File('second.wav'),
        segment: 2,
        duration: const Duration(seconds: 1),
      );
      player.append(first);
      expect(identical(player.current, first), isTrue);
      player.append(second);
      player.play();
      player.play();
      expect(
        events.where((e) => e.kind == PlayerEventKind.started),
        hasLength(1),
      );
      expect(identical(events.first.item, first), isTrue);
      clock.advance(const Duration(milliseconds: 100));
      expect(events.last.kind, PlayerEventKind.progress);
      player.pause();
      final at = player.position;
      clock.advance(const Duration(seconds: 1));
      expect(player.position, at);
      player.retainThrough(0);
      expect(player.current, same(first));
      expect(player.items, [first]);
      player.play();
      clock.advance(const Duration(seconds: 1));
      expect(events.last.kind, PlayerEventKind.drained);
      expect(player.current, isNull);
      player.append(second);
      expect(player.current, same(second));
      player.play();
      expect(events.last.kind, PlayerEventKind.started);
      expect(events.last.item, same(second));
      player.clear(2);
      expect(player.current, isNull);
    },
  );

  test(
    'R10b an unknown exception contains only the type and a technical description',
    () async {
      final h = await PlaybackHarness.create(
        playbackBook([
          ['Книга.'],
        ]),
        engineFactory: UnknownFailureEngine.new,
      );
      h.controller.readFrom(h.book, 0);
      await until(() => h.controller.error != null, 'synthesis error');
      expect(
        h.controller.error!.googleMessage,
        'StateError: synthesis request failed',
      );
    },
  );

  for (final badAgain in [false, true]) {
    test(
      'R9c player error ${badAgain ? 'stops on the repeat' : 'replaces the file and continues'}',
      () async {
        final h = await PlaybackHarness.create(
          playbackBook([
            ['Первый.', 'Второй.'],
          ]),
        );
        await h.cache('Первый.');
        await h.cache('Второй.');
        h.controller.readFrom(h.book, 0);
        await until(() => h.player.items.length == 2, 'both files in the player');
        h.player.failCurrent();
        await h.calls(1);
        expect(h.audio.has(h.key('Первый.'), bookId: h.book.id), isFalse);
        expect(h.engine.calls.map((c) => c.text), ['Первый.']);
        await h.release(0);
        expect(h.controller.state, NarrationState.playing);
        if (badAgain) {
          h.player.failCurrent();
          await until(
            () => h.controller.state == NarrationState.stopped,
            'stop after a repeated player error',
          );
          expect(h.controller.state, NarrationState.stopped);
          expect(h.controller.unitStart, const ReadingPosition(0, 0));
          expect(
            h.controller.error!.googleMessage,
            'PlayerError: audio file unreadable',
          );
        } else {
          h.clock.advance(const Duration(seconds: 1));
          expect(h.controller.state, NarrationState.playing);
          expect(h.controller.unitStart, const ReadingPosition(1, 0));
        }
        expect(h.engine.calls, hasLength(1));
      },
    );
  }
  for (final retry in [false, true]) {
    for (final waiting in [false, true]) {
      test(
        'R1 ${retry ? 'retries' : 'a hanging request'} ${waiting ? 'waiting' : 'preparing'} do not buy past the target',
        () async {
          final h = await PlaybackHarness.create(
            playbackBook([
              [if (waiting) 'Вступление.', ...longChapter()],
            ]),
            engineFactory: () => RetryNearestEngine(retry),
          );
          if (waiting) await h.cache('Вступление.', seconds: 1);
          h.controller.readFrom(h.book, 0);
          await h.calls(2);
          if (waiting) h.clock.advance(const Duration(seconds: 2));
          for (var turn = 0; turn < 14; turn++) {
            final calls = h.engine.calls.toList();
            for (var i = 0; i < calls.length; i++) {
              if (!calls[i].released && (retry || i != 0)) {
                calls[i].release();
              }
            }
            await ioSettled();
            if (retry) {
              h.clock.advance(const Duration(seconds: 30));
              await ioSettled();
            }
          }
          final far = h.engine.calls
              .where((c) => !c.text.startsWith('0 '))
              .map((c) => c.text)
              .toSet();
          expect(far.length, lessThanOrEqualTo(4));
          var bought = 0.0;
          final unique = <String>{};
          for (final call in h.engine.calls) {
            if (!unique.add(call.text)) continue;
            // The last segment may cross the target; the next one must not be bought.
            expect(bought, lessThan(120.01));
            bought += call.text.length * secondsPerChar;
          }
          expect(
            h.controller.state,
            waiting ? NarrationState.waiting : NarrationState.preparing,
          );
        },
      );
    }
  }

  test(
    'R1 a healthy nearest one reaches the target and a download takes the whole chapter',
    () async {
      final d = await DownloadHarness.create(playbackBook([longChapter()]));
      final h = d.h;
      h.controller.readFrom(h.book, 0);
      await untilWithProgress(
        () =>
            h.controller.state == NarrationState.playing &&
            h.player.items.fold(0, (s, i) => s + i.duration.inMilliseconds) >=
                120000,
        () {
          for (final call in h.engine.calls.toList()) {
            call.release();
          }
        },
        'accumulating 120 s of ready audio',
      );
      expect(h.controller.state, NarrationState.playing);
      expect(
        h.player.items.fold(
          0.0,
          (s, i) => s + i.duration.inMilliseconds / 1000,
        ),
        greaterThanOrEqualTo(120),
      );
      expect(h.engine.calls.length, lessThan(14));
      h.controller.pause();
      d.start();
      await d.finish();
      expect(d.downloads.isVoiced(h.book.id, 0, h.profile), isTrue);
    },
  );

  test('R2 a deletion failure is visible on the shelf and the book is narrated again', () async {
    final h = await observed(
      playbackBook([
        ['Книга.'],
      ]),
    );
    final library = h.library as ObservedLibrary;
    library.failDelete = true;
    final escaped = <Object>[];
    runZonedGuarded(
      () => h.controller.deleteBook(h.book.id),
      (e, _) => escaped.add(e),
    );
    await until(() => library.addJobs.isNotEmpty, 'deletion failure message');
    expect(escaped, isEmpty);
    expect(library.addJobs.single.technical, contains('delete denied'));
    expect(library.shelf, hasLength(1));
    h.controller.readFrom(h.book, 0);
    await h.calls(1);
    await h.release(0);
    expect(h.controller.state, NarrationState.playing);
  });

  for (final rejectAgain in [false, true]) {
    test(
      'R3 a broken file ${rejectAgain ? 'is not read again' : 'is replaced'} without a skip',
      () async {
        late ProbePlayer player;
        final h = await PlaybackHarness.create(
          playbackBook([
            ['До.', 'Повреждён.', 'После.'],
          ]),
          playerFactory: (clock) => player = ProbePlayer(clock: clock),
        );
        for (final text in ['До.', 'Повреждён.', 'После.']) {
          await h.cache(text, seconds: 10);
        }
        h.audio
            .file(h.key('Повреждён.'), bookId: h.book.id)!
            .writeAsStringSync('broken');
        h.controller.readFrom(h.book, 0);
        await h.calls(1);
        await until(() => h.player.playing, 'playback up to the broken file');
        expect(h.controller.state, NarrationState.playing);
        expect(h.controller.unitStart, const ReadingPosition(0, 0));
        expect(h.engine.calls.map((c) => c.text), ['Повреждён.']);
        if (rejectAgain) player.rejectAll = true;
        await h.release(0);
        h.clock.advance(const Duration(seconds: 10));
        await until(
          () =>
              h.controller.unitStart == const ReadingPosition(1, 0) &&
              h.controller.state ==
                  (rejectAgain ? NarrationState.stopped : NarrationState.playing),
          'transition to the replaced file',
        );
        expect(h.controller.unitStart, const ReadingPosition(1, 0));
        expect(
          h.controller.state,
          rejectAgain ? NarrationState.stopped : NarrationState.playing,
        );
        if (rejectAgain) {
          expect(
            h.controller.error!.googleMessage,
            'StateError: audio file unreadable',
          );
          expect(h.library.positionOf(h.book.id), const ReadingPosition(1, 0));
        }
        expect(h.engine.calls, hasLength(1));
      },
    );
  }

  test(
    'R3 replacing a broken file restores the reserve already taken beyond the gap',
    () async {
      final h = await PlaybackHarness.create(
        playbackBook([
          ['До.', 'Битый.', 'После.'],
        ]),
      );
      await h.cache('До.', seconds: 10);
      await h.cache('Битый.', seconds: 10);
      await h.cache('После.', seconds: 300);
      h.audio
          .file(h.key('Битый.'), bookId: h.book.id)!
          .writeAsStringSync('broken');
      h.controller.readFrom(h.book, 0);
      await h.calls(1);
      await until(() => h.player.playing, 'playback before the gap');
      expect(h.engine.calls.map((c) => c.text), ['Битый.']);
      expect(h.controller.state, NarrationState.playing);
      await h.release(0);
      h.clock.advance(const Duration(seconds: 10));
      await until(
        () => h.controller.unitStart == const ReadingPosition(1, 0),
        'transition to the restored reserve',
      );
      expect(h.controller.unitStart, const ReadingPosition(1, 0));
    },
  );

  test('R4 a fired timer repeats when the clock is set back', () async {
    late RollbackClock clock;
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Книга.'],
      ]),
      clockFactory: () => clock = RollbackClock(),
    );
    h.engine.enqueue(error: const TemporaryTtsError('retry'));
    h.controller.readFrom(h.book, 0);
    await h.calls(1);
    await h.release(0);
    clock.shift = const Duration(hours: -1);
    clock.advance(const Duration(seconds: 1));
    await h.calls(2);
    expect(h.engine.calls, hasLength(2));
  });

  for (final count in [8, 200]) {
    test(
      'R5 downloaded $count segments: first audio after one probe, the list is limited',
      () async {
        late ProbePlayer player;
        final texts = [for (var i = 0; i < count; i++) 'Отрезок $i.'];
        final h = await PlaybackHarness.create(
          playbackBook([texts]),
          playerFactory: (clock) => player = ProbePlayer(clock: clock),
        );
        for (final text in texts) {
          await h.cache(text, seconds: 40);
        }
        h.controller.readFrom(h.book, 0);
        await until(() => player.items.length >= 3, 'three files in the reserve window');
        expect(player.probesAtFirstPlay, 1);
        expect(player.probes, lessThanOrEqualTo(3));
        expect(player.items, hasLength(3));
        h.clock.advance(const Duration(seconds: 41));
        await until(() => player.probes > 3, 'reserve window top-up');
        expect(player.probes, greaterThan(3));
        expect(h.engine.calls, isEmpty);
      },
    );
  }

  test('R6 commands share only the chapters reached', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        for (var i = 0; i < 50; i++)
          [for (var b = 0; b < 8; b++) 'Глава $i блок $b ${'word ' * 110}'],
      ]),
    );
    final blocks = CountedBlocks(h.book.blocks);
    final book = Book(
      id: h.book.id,
      title: h.book.title,
      author: h.book.author,
      language: h.book.language,
      chapters: h.book.chapters,
      blocks: blocks,
      notes: h.book.notes,
    );
    blocks.reads.clear();
    h.controller.readFrom(book, 0);
    h.controller.next();
    expect(blocks.reads.keys.where((i) => i >= 8), isEmpty);
    h.controller.moveIfListening(book, 8);
    expect(blocks.reads.containsKey(8), isTrue);
    expect(blocks.reads.keys.where((i) => i >= 16), isEmpty);
  });

  test('R7 a minute of a single block does not write the position on every step', () async {
    final h = await observed(
      playbackBook([
        ['abcdefghij ' * 40],
      ]),
    );
    await h.cache(h.book.blocks.single.text, seconds: 120);
    final lib = h.library as ObservedLibrary;
    h.controller.readFrom(h.book, 0);
    await until(() => h.player.playing);
    final writes = lib.positions;
    var notices = 0;
    h.controller.addListener(() => notices++);
    for (var i = 0; i < 600; i++) {
      h.clock.advance(const Duration(milliseconds: 100));
    }
    await ioSettled();
    expect(lib.positions - writes, 0);
    expect(notices, inInclusiveRange(20, 250));
    expect(h.controller.blockProgress, closeTo(0.5, 0.01));
    h.controller.pause();
    expect(lib.positions - writes, 1);
    expect(lib.positionOf(h.book.id)!.offset, greaterThan(0));
  });

  for (final action in ['close', 'clear', 'remove']) {
    test('R8 $action from stopped keeps the screen position', () async {
      final h = await PlaybackHarness.create(
        playbackBook([
          ['Первый.', 'Второй.'],
        ]),
      );
      h.engine.enqueue(error: const TtsError('Google'));
      h.controller.readFrom(h.book, 0);
      await h.calls(2);
      await h.release(0);
      expect(h.controller.state, NarrationState.stopped);
      h.library.savePosition(h.book.id, const ReadingPosition(1, 2));
      switch (action) {
        case 'close':
          h.controller.close();
        case 'clear':
          h.controller.clearAllNarration();
        case 'remove':
          h.controller.deleteBookNarration(h.book.id);
      }
      expect(h.library.positionOf(h.book.id), const ReadingPosition(1, 2));
    });
  }

  test(
    'R9b the last current after drained does not interfere with waiting and the end of the book',
    () async {
      final h = await PlaybackHarness.create(
        playbackBook([
          ['Первый.', 'Второй.'],
        ]),
        playerFactory: (clock) => StickyPlayer(clock: clock),
      );
      h.controller.readFrom(h.book, 0);
      await h.calls(2);
      await h.release(0);
      h.clock.advance(const Duration(seconds: 1));
      expect(h.player.current, isNotNull);
      expect(h.controller.state, NarrationState.waiting);
      await h.release(1);
      expect(h.controller.state, NarrationState.playing);
      h.clock.advance(const Duration(seconds: 1));
      expect(h.controller.stopReason, StopReason.endOfBook);
      expect(h.library.isFinished(h.book.id), isTrue);
    },
  );

  for (final action in ['pause', 'stop', 'close']) {
    test('R10a a flush error during $action is visible and handled', () async {
      final h = await observed(
        playbackBook([
          ['Книга.'],
        ]),
      );
      final lib = h.library as ObservedLibrary;
      await h.cache('Книга.', seconds: 10);
      h.controller.readFrom(h.book, 0);
      await until(() => h.player.playing);
      lib.failFlush = true;
      final escaped = <Object>[];
      runZonedGuarded(() {
        switch (action) {
          case 'pause':
            h.controller.pause();
          case 'stop':
            h.clock.advance(const Duration(seconds: 10));
          case 'close':
            h.controller.close();
        }
      }, (e, _) => escaped.add(e));
      await until(() => lib.addJobs.isNotEmpty, 'flush error message');
      lib.failFlush = false;
      expect(escaped, isEmpty);
      expect(lib.addJobs.single.fileName, 'state.json / settings.json');
      expect(lib.addJobs.single.technical, contains('state write denied'));
    });
  }

  test('R10c the end of a chapter is declared paused right away', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Первая.'],
        ['Следующая.'],
      ]),
    );
    await h.cache('Первая.', seconds: 1);
    h.controller.readFrom(h.book, 0);
    h.controller.setSleepTimer(SleepTimer.endOfChapter(h.clock.now()));
    await until(() => h.player.playing);
    final states = <NarrationState>[];
    h.controller.addListener(() => states.add(h.controller.state));
    h.clock.advance(const Duration(seconds: 1));
    await ioSettled();
    expect(states, isNot(contains(NarrationState.waiting)));
    expect(h.controller.state, NarrationState.paused);
    expect(h.controller.unitStart, const ReadingPosition(1, 0));
  });

  test('R6 the reserve window is not counted as the end of a long chapter', () async {
    final texts = longChapter(20);
    final h = await PlaybackHarness.create(
      playbackBook([
        texts,
        ['Следующая.'],
      ]),
    );
    for (final text in texts) {
      await h.cache(text, seconds: 0.05);
    }
    await h.cache('Следующая.');
    h.controller.readFrom(h.book, 0);
    h.controller.setSleepTimer(SleepTimer.endOfChapter(h.clock.now()));
    await until(() => h.player.playing, 'start of the long chapter');
    h.clock.advance(const Duration(seconds: 1));
    await ioSettled();
    expect(h.controller.sleepTimer, isNotNull);
    await until(() => h.player.playing, 'audio after the reserve window top-up');
    expect(h.controller.state, NarrationState.playing);
    await untilWithProgress(
      () => h.controller.state == NarrationState.paused,
      () => h.clock.advance(const Duration(seconds: 1)),
      'pause at the end of the long chapter',
    );
    expect(h.controller.state, NarrationState.paused);
    expect(h.controller.unitStart, const ReadingPosition(20, 0));
    expect(h.engine.calls, isEmpty);
  });

  test('R10d while PCM waits to be written, new purchases are forbidden', () async {
    final encoder = DiskFullEncoder();
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Ближний.', 'Второй.', 'Третий.', 'Четвёртый.'],
      ]),
      encoder: encoder,
    );
    h.controller.readFrom(h.book, 0);
    await h.calls(2);
    await h.release(1);
    await until(() => encoder.attempts > 0, 'first attempt to write PCM');
    expect(encoder.attempts, 1);
    h.controller.readFrom(h.book, 2);
    await ioSettled();
    expect(h.engine.calls, hasLength(2));
    h.clock.advance(const Duration(seconds: 1));
    await untilWithProgress(
      () => encoder.attempts > 1,
      () {
        expect(h.engine.calls, hasLength(2));
        h.clock.advance(const Duration(seconds: 1));
      },
      'repeated attempt to write PCM on a full disk',
    );
    expect(encoder.attempts, greaterThan(1));
    expect(h.engine.calls, hasLength(2));
    encoder.full = false;
    await untilWithProgress(
      () => h.engine.calls.length >= 3,
      () => h.clock.advance(const Duration(seconds: 30)),
      'new purchase after the PCM write',
    );
    expect(h.audio.has(h.key('Второй.'), bookId: h.book.id), isTrue);
  });
}
