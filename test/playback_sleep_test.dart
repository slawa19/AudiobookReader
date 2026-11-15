import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/tts/engine.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playback_harness.dart';

void main() {
  for (final minutes in [15, 30, 60]) {
    test(
      '9 $minutes минут: playing → paused ровно по сроку, таймер снят',
      () async {
        final h = await PlaybackHarness.create(
          playbackBook([
            ['Книга.'],
          ]),
        );
        await h.cache('Книга.', seconds: 10000);
        h.controller.readFrom(h.book, 0);
        await until(() => h.player.playing);
        h.controller.setSleepTimer(SleepTimer.minutes(minutes, h.clock.now()));
        // В рабочем приложении между событиями плеера писатель получает управление.
        for (var i = 0; i < minutes; i++) {
          h.clock.advance(const Duration(seconds: 59));
          await ioSettled();
          h.clock.advance(
            const Duration(seconds: 1) -
                (i == minutes - 1
                    ? const Duration(microseconds: 1)
                    : Duration.zero),
          );
        }
        expect(h.controller.state, NarrationState.playing);
        h.clock.advance(const Duration(microseconds: 1));
        expect(h.controller.state, NarrationState.paused);
        expect(h.player.playing, isFalse);
        expect(h.controller.sleepTimer, isNull);
        expect(h.engine.calls, isEmpty);
        h.controller.resume();
        expect(h.controller.state, NarrationState.playing);
      },
    );
  }

  for (final state in ['paused', 'preparing', 'waiting']) {
    test(
      '9 срок истёк в $state: пауза и снятие, поздний звук не запускается',
      () async {
        final h = await PlaybackHarness.create(
          playbackBook([
            ['Первый.', 'Второй.'],
          ]),
        );
        final c = h.controller;
        c.readFrom(h.book, 0);
        await h.calls(2);
        if (state == 'waiting') {
          await h.release(0);
          h.clock.advance(const Duration(seconds: 1));
          expect(c.state, NarrationState.waiting);
        }
        if (state == 'paused') c.pause();
        c.setSleepTimer(SleepTimer.minutes(15, h.clock.now()));
        h.clock.advance(const Duration(minutes: 15));
        expect(c.state, NarrationState.paused);
        expect(c.sleepTimer, isNull);
        await h.release(1);
        expect(h.engine.calls.length, 2);
        expect(c.state, NarrationState.paused);
        expect(h.player.playing, isFalse);
        c.resume();
        expect(
          c.state,
          state == 'waiting'
              ? NarrationState.playing
              : NarrationState.preparing,
        );
      },
    );
  }

  test('9 таймер переживает смену главы, места, голоса и модели; снимается сменой книги и close', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Первая.'],
        ['Вторая.'],
      ]),
    );
    final c = h.controller;
    c.readFrom(h.book, 0);
    final timer = SleepTimer.minutes(15, h.clock.now());
    c.setSleepTimer(timer);
    h.clock.advance(const Duration(minutes: 5));
    c.moveIfListening(h.book, 1);
    expect(c.sleepTimer, same(timer));
    h.settings.voice = 'Kore';
    c.restartSession();
    h.settings.modelId = TtsModel.flashLite.id;
    c.restartSession();
    c.readFrom(h.book, 0);
    expect(c.sleepTimer, same(timer));
    h.clock.advance(const Duration(minutes: 10));
    expect(c.state, NarrationState.paused);
    expect(c.sleepTimer, isNull);
    c.setSleepTimer(SleepTimer.minutes(15, h.clock.now()));
    final other = await h.addBook(
      playbackBook([
        ['Другая книга.'],
      ]),
    );
    c.readFrom(other, 0);
    expect(c.sleepTimer, isNull);
    c.setSleepTimer(SleepTimer.minutes(15, h.clock.now()));
    c.close();
    expect(c.sleepTimer, isNull);
    expect(c.state, NarrationState.idle);
  });

  test(
    '9 после ошибки истёкший таймер снимается перед Читать отсюда',
    () async {
      final h = await PlaybackHarness.create(
        playbackBook([
          ['Первая.'],
          ['Вторая.'],
        ]),
      );
      h.engine.enqueue(error: const TtsError('Google'));
      h.controller.readFrom(h.book, 0);
      h.controller.setSleepTimer(SleepTimer.minutes(15, h.clock.now()));
      await h.calls(2);
      await h.release(0);
      expect(h.controller.state, NarrationState.stopped);
      h.clock.advance(const Duration(minutes: 16));
      h.controller.readFrom(h.book, 1);
      expect(h.controller.sleepTimer, isNull);
      expect(h.controller.state, NarrationState.preparing);
      await h.release(1);
      expect(h.controller.state, NarrationState.playing);
      expect(h.engine.calls.length, 2);
    },
  );

  test(
    '9 до конца главы не запрашивает следующую, пауза на её начале',
    () async {
      final h = await PlaybackHarness.create(
        playbackBook([
          ['Первая.', 'Продолжение.'],
          ['Следующая.'],
        ]),
      );
      final c = h.controller;
      c.readFrom(h.book, 0);
      c.setSleepTimer(SleepTimer.endOfChapter(h.clock.now()));
      await h.calls(2);
      expect(h.engine.calls.map((c) => c.text), ['Первая.', 'Продолжение.']);
      await h.release(0);
      await h.release(1);
      // Часы двигаем, только когда оба файла уже в плеере: на медленной машине (CI, 2026-11-15) запись звука
      // не успевала за фиксированной паузой, и время уходило раньше, чем было что доигрывать.
      await until(() => h.player.playing && h.player.items.length >= 2, 'оба отрезка в плеере');
      h.clock.advance(const Duration(seconds: 3));
      await until(() => c.state == NarrationState.paused, 'пауза в конце главы');
      expect(c.unitStart, const ReadingPosition(2, 0));
      expect(c.sleepTimer, isNull);
      expect(h.engine.calls.length, 2);
      c.resume();
      expect(c.state, NarrationState.preparing);
      await h.calls(3);
      expect(h.engine.calls.last.text, 'Следующая.');
    },
  );

  test(
    '9 до конца последней главы: stopped конец книги, таймер снят, дочитана',
    () async {
      final h = await PlaybackHarness.create(
        playbackBook([
          ['Последняя.'],
        ]),
      );
      h.controller.readFrom(h.book, 0);
      h.controller.setSleepTimer(SleepTimer.endOfChapter(h.clock.now()));
      await h.calls(1);
      await h.release(0);
      h.clock.advance(const Duration(seconds: 2));
      expect(h.controller.state, NarrationState.stopped);
      expect(h.controller.stopReason, StopReason.endOfBook);
      expect(h.controller.sleepTimer, isNull);
      expect(h.library.isFinished(h.book.id), isTrue);
      expect(h.engine.calls.length, 1);
    },
  );

  test('9 таймер после наполнения списка отрезает следующую главу; снятие возвращает хвост', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Первая.'],
        ['Следующая.'],
      ]),
    );
    await h.cache('Первая.');
    await h.cache('Следующая.');
    h.controller.readFrom(h.book, 0);
    await until(() => h.player.items.length == 2);
    h.controller.setSleepTimer(SleepTimer.endOfChapter(h.clock.now()));
    expect(h.player.items.length, 1);
    expect(h.player.playing, isTrue);
    h.controller.setSleepTimer(null);
    await until(() => h.player.items.length == 2);
    h.clock.advance(const Duration(seconds: 11));
    expect(h.controller.unitStart, const ReadingPosition(1, 0));
    expect(h.controller.state, NarrationState.playing);
    expect(h.engine.calls, isEmpty);
  });

  test('9 минуты ограничивают цель запаса оставшимся временем', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Первый.', 'Следующий.'],
      ]),
    );
    await h.cache('Первый.', seconds: 70);
    h.controller.readFrom(h.book, 0);
    h.controller.setSleepTimer(
      SleepTimer.minutes(
        15,
        h.clock.now().subtract(const Duration(minutes: 14)),
      ),
    );
    await ioSettled();
    expect(h.engine.calls, isEmpty);
    h.clock.advance(const Duration(seconds: 60));
    expect(h.controller.state, NarrationState.paused);
    expect(h.controller.sleepTimer, isNull);
    expect(h.engine.calls, isEmpty);
  });
}
