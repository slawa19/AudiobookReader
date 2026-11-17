import 'dart:io';

import 'package:audiobook_reader/audio/file_audio_store.dart';
import 'package:audiobook_reader/audio/wav_audio_encoder.dart';
import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/book/parse.dart';
import 'package:audiobook_reader/library/file_library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/playback/chapter_download.dart';
import 'package:audiobook_reader/playback/file_chapter_download.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/playback/synthesis_queue.dart';
import 'package:audiobook_reader/playback/tariffs.dart';
import 'package:audiobook_reader/tts/engine.dart';
import 'package:audiobook_reader/tts/fake_engine.dart';
import 'package:audiobook_reader/tts/segments.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/download_harness.dart';
import 'support/playback_harness.dart';

void main() {
  test(
    'estimate, ready share, stop and a proportional price for the remainder',
    () async {
      final d = await DownloadHarness.create(
        playbackBook([
          ['Первый.', 'Второй длиннее.', 'Третий.'],
          ['За границей.'],
        ]),
      );
      final h = d.h, downloads = d.downloads;
      final total = downloads.estimate(h.book, 0, h.profile);
      expect(total.seconds, 29 * secondsPerChar);
      expect(total.dollars, closeTo(total.seconds * 25 * 9 / 1000000, 1e-12));
      d.start();
      await h.calls(2);
      expect(d.awake.enabled, isTrue);
      await h.release(0);
      expect(downloads.task!.fraction, closeTo(7 / 29, 1e-12));
      final ready = downloads.task!.readySeconds;
      downloads.stop();
      expect(downloads.task, isNull);
      expect(d.awake.enabled, isFalse);
      final rest = downloads.estimate(h.book, 0, h.profile);
      expect(rest.seconds, closeTo(total.seconds - ready, 1e-12));
      expect(
        rest.dollars,
        closeTo(total.dollars * rest.seconds / total.seconds, 1e-12),
      );
      final calls = h.engine.calls.length;
      for (var i = 1; i < calls; i++) {
        await h.release(i);
      }
      expect(h.engine.calls.length, calls);
      expect(h.engine.calls.any((c) => c.text == 'За границей.'), isFalse);
      expect(h.audio.bytesForBook(h.book.id), greaterThan(0));
    },
  );

  test('the estimate counts identical text once; readiness and share count all occurrences', () async {
    final d = await DownloadHarness.create(
      playbackBook([
        ['Повтор.', 'Повтор.', 'Другой.'],
      ]),
    );
    final h = d.h;
    expect(
      d.downloads.estimate(h.book, 0, h.profile).seconds,
      14 * secondsPerChar,
    );
    d.start();
    await h.calls(2);
    await h.release(0);
    expect(d.downloads.task!.fraction, closeTo(2 / 3, 1e-12));
    await h.release(1);
    expect(d.downloads.isVoiced(h.book.id, 0, h.profile), isTrue);
    expect(h.engine.calls.map((c) => c.text), ['Повтор.', 'Другой.']);
    expect(d.awake.changes, [true, false]);
  });

  test(
    'readiness: a whole file, all parts and only the missing part',
    () async {
      final text = 'Первое предложение. ${'Продолжение ' * 24}';
      final d = await DownloadHarness.create(
        playbackBook([
          [text],
        ]),
      );
      final h = d.h;
      final segment = chapterSegments(h.book.blocks).single;
      final parts = segmentParts(segment);
      expect(parts.length, 2);
      await h.cache(parts.first.text);
      expect(d.downloads.isVoiced(h.book.id, 0, h.profile), isFalse);
      expect(
        d.downloads.estimate(h.book, 0, h.profile).seconds,
        parts.last.text.length * secondsPerChar,
      );
      d.start();
      await h.calls(1);
      expect(h.engine.calls.single.text, parts.last.text);
      await h.release(0);
      expect(d.downloads.isVoiced(h.book.id, 0, h.profile), isTrue);
      expect(h.audio.has(h.key(text), bookId: h.book.id), isFalse);
      h.controller.deleteBookNarration(h.book.id);
      await h.cache(text);
      expect(d.downloads.isVoiced(h.book.id, 0, h.profile), isTrue);
      expect(d.downloads.estimate(h.book, 0, h.profile).seconds, 0);
      d.start();
      expect(d.downloads.task, isNull);
      expect(h.engine.calls.length, 1);
    },
  );

  test(
    'leaving and returning: the first unready one; a manual stop cancels the continuation',
    () async {
      final d = await DownloadHarness.create(
        playbackBook([
          ['Первый.', 'Второй.', 'Третий.', 'Четвёртый.', 'Пятый.'],
        ]),
      );
      final h = d.h;
      d.start();
      await h.calls(2);
      d.downloads.setForeground(false);
      expect(d.awake.enabled, isFalse);
      await h.release(0);
      await h.release(1);
      expect(h.engine.calls.length, 2);
      d.downloads.setForeground(true);
      await h.calls(4);
      expect(h.engine.calls[2].text, 'Третий.');
      expect(d.awake.enabled, isTrue);
      d.downloads.setForeground(false);
      d.downloads.stop();
      await h.release(2);
      await h.release(3);
      d.downloads.setForeground(true);
      await ioSettled();
      expect(h.engine.calls.length, 4);
      expect(d.downloads.task, isNull);
      expect(d.awake.enabled, isFalse);
      expect(d.downloads.isVoiced(h.book.id, 0, h.profile), isFalse);
    },
  );

  for (final change in ['book', 'app', 'model']) {
    test(
      'changing the $change: the task is stopped, the old narration is kept, the new profile is not narrated',
      () async {
        final d = await DownloadHarness.create(
          playbackBook([
            ['Один.', 'Два.', 'Три.'],
            ['Готово.'],
          ]),
        );
        final h = d.h;
        final old = h.profile;
        await h.cache('Готово.');
        expect(d.downloads.isVoiced(h.book.id, 1, old), isTrue);
        d.start();
        await h.calls(2);
        if (change == 'book') {
          h.library.setBookVoice(h.book.id, 'Kore');
        } else if (change == 'app') {
          h.settings.voice = 'Kore';
        } else {
          h.settings.modelId = TtsModel.flashLite.id;
        }
        expect(d.downloads.task, isNull);
        expect(d.awake.enabled, isFalse);
        final current = d.downloads.profileFor(h.book.id);
        expect(current, h.profile);
        expect(d.downloads.isVoiced(h.book.id, 1, current), isFalse);
        expect(
          d.downloads.estimate(h.book, 0, current).seconds,
          13 * secondsPerChar,
        );
        expect(d.downloads.isVoiced(h.book.id, 1, old), isTrue);
      },
    );
  }

  test('permanent error: the cause and the Google text stay with the task; listening is untouched', () async {
    final d = await DownloadHarness.create(
      playbackBook([
        ['Ошибка.', 'Готовое.'],
        ['Слушаем.'],
      ]),
    );
    final h = d.h;
    await h.cache('Готовое.');
    await h.cache('Слушаем.');
    h.controller.readFrom(h.book, 2);
    await until(() => h.controller.state == NarrationState.playing);
    final session = h.controller.session;
    h.engine.enqueue(
      error: const TtsError(
        'Google: Request contains an invalid argument.',
        reason: TtsErrorReason.invalidRequest,
        usage: TtsUsage(audioTokens: 17),
      ),
    );
    d.start();
    await h.calls(1);
    await h.release(0);
    final t = d.downloads.task!;
    expect(t.status, DownloadStatus.failed);
    expect(t.error!.reason, TtsErrorReason.invalidRequest);
    expect(t.googleMessage, 'Google: Request contains an invalid argument.');
    expect(h.controller.state, NarrationState.playing);
    expect(h.controller.session, session);
    expect(h.controller.error, isNull);
    expect(h.audioTokens, 17);
    expect(
      d.downloads.estimate(h.book, 0, h.profile).seconds,
      7 * secondsPerChar,
    );
    expect(d.awake.enabled, isFalse);
    d.start();
    await h.calls(2);
    await h.release(1);
    expect(d.downloads.task, isNull);
    expect(d.downloads.isVoiced(h.book.id, 0, h.profile), isTrue);
  });

  test('an error without listening does not open the player panel', () async {
    final d = await DownloadHarness.create(
      playbackBook([
        ['Текст.'],
      ]),
    );
    final h = d.h;
    h.engine.enqueue(
      error: const TtsError('Google', reason: TtsErrorReason.invalidKey),
    );
    d.start();
    await h.calls(1);
    await h.release(0);
    expect(d.downloads.task!.googleMessage, 'Google');
    expect(h.controller.state, NarrationState.idle);
    expect(h.controller.bookId, isNull);
  });

  test('a temporary error is retried; pausing listening does not interfere; stop cancels the retry', () async {
    final d = await DownloadHarness.create(
      playbackBook([
        ['Текст.'],
      ]),
    );
    final h = d.h;
    h.engine.enqueue(error: const TemporaryTtsError('Сеть'));
    h.engine.enqueue(error: const TemporaryTtsError('Сеть'));
    d.start();
    await h.calls(1);
    await h.release(0);
    h.controller.pause();
    h.clock.advance(const Duration(seconds: 1));
    await h.calls(2);
    await h.release(1);
    d.downloads.stop();
    h.clock.advance(const Duration(minutes: 2));
    await ioSettled();
    expect(h.engine.calls.length, 2);
  });

  test('a shared limit of two: listening and downloading', () async {
    final d = await DownloadHarness.create(
      playbackBook([
        ['Слушаем.'],
        ['Первый.', 'Второй.', 'Третий.'],
      ]),
    );
    final h = d.h;
    h.controller.readFrom(h.book, 0);
    // Set the boundary after the start but before the queue microtask.
    h.controller.setSleepTimer(SleepTimer.endOfChapter(h.clock.now()));
    await h.calls(1);
    d.start(1);
    await h.calls(2);
    await ioSettled();
    expect(h.engine.calls.length, 2);
    expect(h.queue.inFlight, 2);
    expect(h.engine.calls[1].text, 'Первый.');
    await h.release(0);
    await h.calls(3);
    expect(h.engine.calls[2].text, 'Второй.');
    expect(h.queue.inFlight, 2);
    h.controller.pause();
    await h.release(1);
    await h.calls(4);
    expect(h.engine.calls[3].text, 'Третий.');
    expect(h.queue.inFlight, 2);
    await d.finish();
  });

  test(
    'a late permanent error in the background stays with the task and is not restarted',
    () async {
      final d = await DownloadHarness.create(
        playbackBook([
          ['Текст.'],
        ]),
      );
      final h = d.h;
      h.engine.enqueue(error: const TtsError('Google: отказ'));
      d.start();
      await h.calls(1);
      d.downloads.setForeground(false);
      await h.release(0);
      expect(d.downloads.task!.status, DownloadStatus.failed);
      expect(d.downloads.task!.googleMessage, 'Google: отказ');
      d.downloads.setForeground(true);
      await ioSettled();
      expect(h.engine.calls.length, 1);
      expect(d.awake.enabled, isFalse);
    },
  );

  test('background cancels temporary retries, returning continues, a profile change in the background cancels '
      'the continuation', () async {
    final d = await DownloadHarness.create(
      playbackBook([
        ['Текст.'],
      ]),
    );
    final h = d.h;
    h.engine.enqueue(error: const TemporaryTtsError('Сеть'));
    d.start();
    await h.calls(1);
    await h.release(0);
    d.downloads.setForeground(false);
    h.clock.advance(const Duration(minutes: 1));
    await ioSettled();
    expect(h.engine.calls.length, 1);
    d.downloads.setForeground(true);
    await h.calls(2);
    d.downloads.setForeground(false);
    h.settings.voice = 'Kore';
    await h.release(1);
    d.downloads.setForeground(true);
    await ioSettled();
    expect(h.engine.calls.length, 2);
    expect(d.downloads.task, isNull);
    expect(d.downloads.isVoiced(h.book.id, 0, h.profile), isFalse);
  });

  test(
    'a new start after clearing waits for the old response but does not accept its audio',
    () async {
      final d = await DownloadHarness.create(
        playbackBook([
          ['Текст.'],
        ]),
      );
      final h = d.h;
      h.engine.enqueue(usage: const TtsUsage(audioTokens: 17));
      h.engine.enqueue(usage: const TtsUsage(audioTokens: 23));
      d.start();
      await h.calls(1);
      h.controller.clearAllNarration();
      d.start();
      await ioSettled();
      expect(h.engine.calls.length, 1);
      await h.release(0);
      await h.calls(2);
      expect(h.audioTokens, 17);
      expect(d.downloads.isVoiced(h.book.id, 0, h.profile), isFalse);
      expect(h.audio.totalBytes, 0);
      expect(d.downloads.task, isNotNull);
      await h.release(1);
      expect(h.audioTokens, 40);
      expect(d.downloads.isVoiced(h.book.id, 0, h.profile), isTrue);
      expect(h.audio.totalBytes, greaterThan(0));
    },
  );

  test(
    'the tariff for today and stopping the only previous task with a new start',
    () async {
      final d = await DownloadHarness.create(
        playbackBook([
          ['Первая.'],
          ['Вторая.'],
        ]),
      );
      final h = d.h;
      final before = d.downloads.estimate(h.book, 0, h.profile);
      h.clock.advance(const Duration(days: 60));
      final after = d.downloads.estimate(h.book, 0, h.profile);
      expect(after.seconds, before.seconds);
      expect(after.dollars, before.dollars * 2);
      d.start();
      await h.calls(1);
      d.start(1);
      await h.calls(2);
      expect(d.downloads.task!.chapter, 1);
      await h.release(0);
      expect(d.downloads.task!.chapter, 1);
      expect(d.downloads.task!.fraction, 0);
      await h.release(1);
      expect(d.downloads.task, isNull);
      expect(d.downloads.isVoiced(h.book.id, 0, h.profile), isTrue);
      expect(d.downloads.isVoiced(h.book.id, 1, h.profile), isTrue);
    },
  );

  for (final downloadFirst in [false, true]) {
    test(
      'one request per fingerprint: ${downloadFirst ? 'download' : 'listening'} first',
      () async {
        final text = 'Первое предложение. ${'Дальше ' * 36}';
        final d = await DownloadHarness.create(
          playbackBook([
            [text],
          ]),
        );
        final h = d.h;
        if (downloadFirst) {
          d.start();
          await h.calls(1);
          h.controller.readFrom(h.book, 0);
        } else {
          h.controller.readFrom(h.book, 0);
          await h.calls(2);
          d.start();
        }
        await ioSettled();
        final expected = downloadFirst ? 1 : 2;
        expect(h.engine.calls.length, expected);
        for (var i = 0; i < expected; i++) {
          await h.release(i);
        }
        expect(h.engine.calls.length, expected);
        expect(h.controller.state, NarrationState.playing);
        expect(d.downloads.task, isNull);
        expect(d.downloads.isVoiced(h.book.id, 0, h.profile), isTrue);
      },
    );
  }

  for (final deletion in ['book', 'book narration', 'all narration']) {
    test(
      'deleting the $deletion during a request: the spend is recorded, there is no file and no new requests',
      () async {
        final d = await DownloadHarness.create(
          playbackBook([
            ['Первый.', 'Второй.', 'Третий.'],
          ]),
        );
        final h = d.h;
        final firstKey = h.key('Первый.');
        h.engine.enqueue(usage: const TtsUsage(audioTokens: 17));
        h.engine.enqueue(usage: const TtsUsage(audioTokens: 23));
        d.start();
        await h.calls(2);
        if (deletion == 'book') {
          h.controller.deleteBook(h.book.id);
          await until(() => h.library.shelf.isEmpty);
        } else if (deletion == 'book narration') {
          h.controller.deleteBookNarration(h.book.id);
        } else {
          h.controller.clearAllNarration();
        }
        expect(d.downloads.task, isNull);
        expect(d.awake.enabled, isFalse);
        expect(h.engine.calls.every((c) => !c.released), isTrue);
        await h.release(0);
        await h.release(1);
        expect(h.audioTokens, 40);
        expect(h.audio.totalBytes, 0);
        expect(h.audio.has(firstKey, bookId: h.book.id), isFalse);
        expect(
          Directory('${h.root.path}/books/${h.book.id}/audio').existsSync(),
          isFalse,
        );
        expect(h.engine.calls.length, 2);
        d.downloads.setForeground(false);
        d.downloads.setForeground(true);
        await ioSettled();
        expect(h.engine.calls.length, 2);
        if (deletion == 'book') {
          expect(
            Directory('${h.root.path}/books/${h.book.id}').existsSync(),
            isFalse,
          );
        } else {
          expect(d.downloads.isVoiced(h.book.id, 0, h.profile), isFalse);
          d.start();
          await d.finish();
          expect(d.downloads.isVoiced(h.book.id, 0, h.profile), isTrue);
          expect(h.audio.bytesForBook(h.book.id), greaterThan(0));
          expect(h.audio.totalBytes, greaterThan(0));
        }
      },
    );
  }

  test('finishing, a restart on the same folder, clearing and a new download take up space', () async {
    final source = Book.fromJson({
      ...playbackBook([
        ['Готовая глава.'],
      ]).toJson(),
      'parserVersion': currentParserVersion,
    });
    final d = await DownloadHarness.create(source);
    final h = d.h;
    d.start();
    await d.finish();
    expect(d.downloads.isVoiced(h.book.id, 0, h.profile), isTrue);
    expect(h.audio.totalBytes, greaterThan(0));
    await h.library.flush();
    final settings = AppSettings(voice: 'Aoede', modelId: TtsModel.flash.id);
    final library = FileLibrary(h.root, settings: settings);
    await library.ready;
    final book = await library.loadBook(h.book.id);
    final audio = FileAudioStore(h.root, encoder: const WavAudioEncoder());
    final engine = FakeTtsEngine(manual: true);
    final queue = SynthesisQueue(
      engine: engine,
      audio: audio,
      library: library,
      settings: settings,
    );
    final downloads = FileChapterDownloads(
      queue: queue,
      tariffs: Tariffs(today: h.clock.now),
      bookFor: (_) => book,
      screenAwake: FakeScreenAwake(),
    );
    final profile = downloads.profileFor(book.id);
    expect(downloads.isVoiced(book.id, 0, profile), isTrue);
    expect(downloads.estimate(book, 0, profile).seconds, 0);
    downloads.start(book, 0, profile);
    expect(downloads.task, isNull);
    expect(engine.calls, isEmpty);
    downloads.dispose();
    queue.dispose();
    audio.dispose();
    library.dispose();
    settings.dispose();
    h.controller.clearAllNarration();
    expect(d.downloads.isVoiced(h.book.id, 0, h.profile), isFalse);
    d.start();
    await d.finish();
    expect(h.engine.calls.length, 2);
    expect(h.audio.totalBytes, greaterThan(0));
  });
}
