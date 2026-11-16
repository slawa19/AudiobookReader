import 'dart:io';

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/file_library.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/tts/engine.dart';
import 'package:audiobook_reader/tts/segments.dart';
import 'package:audiobook_reader/tts/voices.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playback_harness.dart';

const page = PageRange(ReadingPosition(0, 0), ReadingPosition(100, 0));

// Каждое предложение длиннее 80 и короче 200 знаков: у сцен с двумя частями остаётся отдельный хвост.
const firstSentence =
    'Первое предложение достаточно длинное, чтобы первая часть старта содержала текст для непрерывного звучания. ';
const secondSentence =
    'Второе предложение достаточно длинное, чтобы первая часть старта содержала текст для непрерывного звучания. ';

void main() {
  test('8 счётчик и новое место наблюдаются вместе, включая снятие истёкшего таймера и смену книги', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Первый.', 'Второй.'],
      ]),
    );
    final c = h.controller;
    c.readFrom(h.book, 0);
    c.setSleepTimer(
      SleepTimer.minutes(
        15,
        h.clock.now().subtract(const Duration(minutes: 16)),
      ),
    );
    final seen = <ReadingPosition?>[];
    var revision = c.commandRevision;
    c.addListener(() {
      if (revision != c.commandRevision) {
        revision = c.commandRevision;
        seen.add(c.unitStart);
      }
    });
    c.next();
    expect(seen, [const ReadingPosition(1, 0)]);
    expect(c.sleepTimer, isNull);
    final other = await h.addBook(
      playbackBook([
        ['Другая.'],
      ]),
    );
    c.readFrom(other, 0);
    expect(seen, [const ReadingPosition(1, 0), const ReadingPosition(0, 0)]);
  });

  for (final reason in [TtsErrorReason.invalidKey, TtsErrorReason.other]) {
    test('4 ошибка $reason сохраняет Google и не запускается сама', () async {
      final h = await PlaybackHarness.create(
        playbackBook([
          ['Текст.'],
        ]),
      );
      h.engine.enqueue(error: TtsError('Текст Google', reason: reason));
      h.controller.readFrom(h.book, 0);
      await h.calls(1);
      await h.release(0);
      expect(h.controller.state, NarrationState.stopped);
      expect(
        h.controller.error!.kind,
        reason == TtsErrorReason.invalidKey
            ? NarrationErrorKind.badKey
            : NarrationErrorKind.other,
      );
      expect(h.controller.error!.googleMessage, 'Текст Google');
      expect(h.controller.unitStart, const ReadingPosition(0, 0));
      h.clock.advance(const Duration(minutes: 1));
      await ioSettled();
      expect(h.engine.calls.length, 1);
      expect(h.controller.state, NarrationState.stopped);
    });
  }
  test('10 автоматическая часть длинного предложения переживает смену профиля; вперёд идёт к следующему абзацу', () async {
    final text = '${List.filled(300, 'слово').join(' ')}.';
    final h = await PlaybackHarness.create(
      playbackBook([
        [text, 'Следующий абзац.'],
      ], kind: BlockKind.paragraph),
    );
    final canonical = chapterSegments(h.book.blocks);
    final expected = canonical[1].mappings.first.blockStart;
    for (final segment in canonical) {
      await h.cache(segment.text, seconds: 60);
    }
    h.controller.readFrom(h.book, 0);
    await until(() => h.player.playing && h.player.items.length >= 2);
    h.clock.advance(const Duration(seconds: 61));
    expect(h.controller.unitStart, ReadingPosition(0, expected));
    h.controller.pause();
    h.settings.voice = 'Kore';
    h.controller.restartSession();
    expect(h.controller.unitStart, ReadingPosition(0, expected));
    expect(h.controller.state, NarrationState.paused);
    expect(h.engine.calls, isEmpty);
    h.controller.next();
    expect(h.controller.unitStart, const ReadingPosition(1, 0));
  });
  test('1 idle → preparing → playing → paused → playing; прерывание без автопродолжения', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Первый.', 'Второй.'],
      ]),
    );
    final c = h.controller;
    expect(c.state, NarrationState.idle);
    c.listen(h.book, page);
    expect(c.state, NarrationState.preparing);
    expect(c.unitStart, const ReadingPosition(0, 0));
    await h.calls(2);
    expect(h.engine.calls.length, 2);
    await h.release(0);
    expect(c.state, NarrationState.playing);
    h.clock.advance(const Duration(milliseconds: 200));
    c.pause();
    expect(c.state, NarrationState.paused);
    final position = h.player.position;
    final rev = c.commandRevision;
    h.clock.advance(const Duration(seconds: 2));
    expect(h.player.position, position);
    c.resume();
    expect(c.state, NarrationState.playing);
    expect(h.player.position, position);
    expect(c.commandRevision, rev + 1);
    h.player.interrupt();
    expect(c.state, NarrationState.paused);
    h.clock.advance(const Duration(minutes: 1));
    expect(h.player.playing, isFalse);
    expect(c.commandRevision, rev + 1);
  });

  test('1 preparing → paused; поздний ответ добавлен, но не звучит; resume без звука preparing', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Первый.'],
      ]),
    );
    final c = h.controller;
    c.listen(h.book, page);
    await h.calls(1);
    c.pause();
    c.resume();
    expect(c.state, NarrationState.preparing);
    c.pause();
    await h.release(0);
    expect(h.engine.calls.length, 1);
    expect(c.state, NarrationState.paused);
    expect(h.player.items.length, 1);
    expect(h.player.playing, isFalse);
    expect(c.unitStart, const ReadingPosition(0, 0));
    c.resume();
    expect(c.state, NarrationState.playing);
  });

  test('1 next/previous без звука preparing, из паузы остаётся paused; stopped игнорирует шаги', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Первый.', 'Второй.', 'Третий.'],
      ]),
    );
    final c = h.controller;
    c.listen(h.book, page);
    await h.calls(2);
    c.next();
    expect(c.state, NarrationState.preparing);
    expect(c.unitStart, const ReadingPosition(1, 0));
    c.previous();
    expect(c.state, NarrationState.preparing);
    expect(c.unitStart, const ReadingPosition(0, 0));
    c.pause();
    c.next();
    expect(c.state, NarrationState.paused);
    expect(c.unitStart, const ReadingPosition(1, 0));
    expect(h.engine.calls.length, 2);
  });

  for (final action in ['chapter', 'close', 'delete', 'clear', 'removeAudio']) {
    test(
      '2 поздний ответ после $action и новой команды сохраняет только допустимый кэш и расход',
      () async {
        final h = await PlaybackHarness.create(
          playbackBook([
            ['Старый.'],
            ['Новый.'],
          ]),
        );
        final c = h.controller;
        c.listen(h.book, page);
        await h.calls(2);
        final key = h.key('Старый.');
        switch (action) {
          case 'chapter':
            c.moveIfListening(h.book, 1);
          case 'close':
            c.close(screenPosition: const ReadingPosition(1, 2));
          case 'delete':
            c.deleteBook(h.book.id);
            await until(
              () =>
                  !Directory('${h.root.path}/books/${h.book.id}').existsSync(),
            );
          case 'clear':
            c.clearAllNarration();
          case 'removeAudio':
            c.deleteBookNarration(h.book.id);
        }
        if (action == 'delete') {
          final other = await h.addBook(
            playbackBook([
              ['Другая книга.'],
            ]),
          );
          c.readFrom(other, 0);
        } else {
          c.readFrom(h.book, 1);
        }
        final session = c.session, position = c.unitStart;
        final reading = h.library.positionOf(c.bookId!);
        await h.release(0);
        expect(h.audioTokens, 18);
        expect(c.session, session);
        expect(c.unitStart, position);
        expect(h.library.positionOf(c.bookId!), reading);
        expect(c.state, NarrationState.preparing);
        expect(h.player.items, isEmpty);
        expect(
          h.audio.has(key, bookId: h.book.id),
          action == 'chapter' || action == 'close',
        );
        if (action == 'delete') {
          expect(
            Directory('${h.root.path}/books/${h.book.id}').existsSync(),
            isFalse,
          );
        }
        if (action == 'clear' || action == 'removeAudio') {
          expect(
            Directory('${h.root.path}/books/${h.book.id}/audio').existsSync(),
            isFalse,
          );
        }
        expect(h.engine.calls.length, action == 'delete' ? 3 : 2);
      },
    );
  }

  test(
    '3 одинаковые абзацы разных глав — один запрос; текущий сеанс ждёт прежний',
    () async {
      final h = await PlaybackHarness.create(
        playbackBook([
          ['Одинаковый абзац.'],
          ['Одинаковый абзац.'],
        ], kind: BlockKind.paragraph),
      );
      final c = h.controller;
      c.listen(h.book, page);
      await h.calls(1);
      expect(h.engine.calls.length, 1);
      c.moveIfListening(h.book, 1);
      await ioSettled();
      expect(h.engine.calls.length, 1);
      await h.release(0);
      expect(c.state, NarrationState.playing);
      expect(c.unitStart, const ReadingPosition(1, 0));
      expect(
        h.library.listeningPositionOf(h.book.id),
        const ReadingPosition(1, 0),
      );
      expect(h.player.items.length, 1);
      expect(h.engine.calls.length, 1);
      expect(h.audioTokens, 43);
    },
  );

  test('4 ближайший ждёт повтора: дальний начатый заканчивается, новых дальних нет', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Ближний.', 'Начатый.', 'Дальний.', 'Ещё дальше.'],
      ]),
    );
    h.engine.enqueue(error: const TemporaryTtsError('Повтор'));
    h.controller.listen(h.book, page);
    await h.calls(2);
    await h.release(0);
    expect(h.controller.state, NarrationState.preparing);
    expect(h.engine.calls.length, 2);
    await h.release(1);
    expect(h.audio.has(h.key('Начатый.'), bookId: h.book.id), isTrue);
    expect(h.player.items, isEmpty);
    expect(h.engine.calls.length, 2);
    h.clock.advance(const Duration(milliseconds: 999));
    await ioSettled();
    expect(h.engine.calls.length, 2);
    h.clock.advance(const Duration(milliseconds: 1));
    await h.calls(3);
    expect(h.engine.calls[2].text, 'Ближний.');
    expect(h.controller.unitStart, const ReadingPosition(0, 0));
  });

  test('4 playing → waiting → playing автоматически; waiting → paused; поздний звук молчит', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Первый.', 'Второй.', 'Третий.'],
      ]),
    );
    final c = h.controller;
    c.listen(h.book, page);
    await h.calls(2);
    await h.release(0);
    final revision = c.commandRevision;
    h.clock.advance(const Duration(seconds: 1));
    expect(c.state, NarrationState.waiting);
    expect(h.library.isFinished(h.book.id), isFalse);
    await h.release(1);
    expect(c.state, NarrationState.playing);
    expect(c.unitStart, const ReadingPosition(1, 0));
    expect(c.commandRevision, revision);
    await h.calls(3);
    h.clock.advance(const Duration(seconds: 1));
    expect(c.state, NarrationState.waiting);
    c.pause();
    await h.release(2);
    expect(c.state, NarrationState.paused);
    expect(h.player.playing, isFalse);
    expect(h.engine.calls.length, 3);
  });

  for (final paused in [false, true]) {
    test(
      '4 постоянная ошибка ${paused ? 'на паузе сразу' : 'после готового звука'} → stopped с первым неготовым местом',
      () async {
        final h = await PlaybackHarness.create(
          playbackBook([
            ['Первый.', 'Второй.', 'Третий.'],
          ]),
        );
        h.engine.enqueue();
        h.engine.enqueue(
          error: const TtsError(
            'Текст Google',
            reason: TtsErrorReason.paymentRequired,
            usage: TtsUsage(audioTokens: 7),
          ),
        );
        final c = h.controller;
        c.listen(h.book, page);
        await h.calls(2);
        await h.release(0);
        if (paused) c.pause();
        await h.release(1);
        if (!paused) {
          expect(c.state, NarrationState.playing);
          h.clock.advance(const Duration(seconds: 1));
        }
        expect(c.state, NarrationState.stopped);
        expect(c.stopReason, StopReason.error);
        expect(c.error!.kind, NarrationErrorKind.payment);
        expect(c.error!.googleMessage, 'Текст Google');
        expect(c.unitStart, const ReadingPosition(1, 0));
        expect(h.library.positionOf(h.book.id), const ReadingPosition(1, 0));
        final revision = c.commandRevision;
        c.next();
        c.previous();
        expect(c.commandRevision, revision);
        expect(
          h.engine.calls.length,
          3,
        ); // Третий был начат до прихода постоянной ошибки.
        h.library.savePosition(h.book.id, const ReadingPosition(2, 0));
        c.resume();
        expect(c.state, NarrationState.preparing);
        expect(c.unitStart, const ReadingPosition(2, 0));
      },
    );
  }

  test(
    '4 preparing → stopped; 404 хранит модель ошибки; без ключа старт запрещён',
    () async {
      final h = await PlaybackHarness.create(
        playbackBook([
          ['Текст.'],
        ]),
      );
      h.settings.apiKey = null;
      h.controller.listen(h.book, page);
      expect(h.controller.state, NarrationState.idle);
      expect(h.engine.calls, isEmpty);
      h.settings.apiKey = 'dummy-secret';
      h.engine.enqueue(
        error: TtsError(
          'dummy-secret Google 404',
          reason: TtsErrorReason.modelNotFound,
          model: TtsModel.flash.id,
        ),
      );
      h.controller.listen(h.book, page);
      await h.calls(1);
      await h.release(0);
      expect(h.controller.state, NarrationState.stopped);
      expect(h.controller.error!.kind, NarrationErrorKind.modelNotFound);
      expect(h.controller.error!.googleMessage, '[REDACTED] Google 404');
      h.settings.modelId = TtsModel.flashLite.id;
      h.controller.restartSession();
      expect(h.controller.error!.modelId, TtsModel.flash.id);
      expect(h.engine.calls.length, 1);
    },
  );

  test(
    '5 две части старта повторно используются при непрерывном проходе',
    () async {
      const text = '$firstSentenceВторое предложение с остатком.';
      final h = await PlaybackHarness.create(
        playbackBook([
          ['Заголовок'],
          [text],
        ], kind: BlockKind.paragraph),
      );
      final c = h.controller;
      c.readFrom(h.book, 1);
      await h.calls(2);
      expect(h.engine.calls.map((c) => c.text), [
        firstSentence,
        'Второе предложение с остатком.',
      ]);
      await h.release(0);
      await h.release(1);
      c.close();
      c.readFrom(h.book, 0);
      await h.calls(3);
      await h.release(2);
      h.clock.advance(const Duration(seconds: 2));
      await ioSettled();
      expect(h.engine.calls.length, 3);
      expect(c.unitStart, const ReadingPosition(1, 0));
      expect(c.state, NarrationState.playing);
    },
  );

  test('5 одна готовая часть — только недостающая; целый файл — вообще без синтеза', () async {
    const text = '$firstSentenceВторое предложение.';
    final h = await PlaybackHarness.create(
      playbackBook([
        [text],
      ], kind: BlockKind.paragraph),
    );
    await h.cache(firstSentence);
    h.controller.listen(h.book, page);
    await h.calls(1);
    expect(h.engine.calls.single.text, 'Второе предложение.');
    expect(h.controller.state, NarrationState.playing);
    await h.release(0);
    h.controller.close();
    await h.cache(text);
    h.controller.listen(h.book, page);
    await ioSettled();
    expect(h.engine.calls.length, 1);
    expect(h.player.items.length, 1);
  });

  test(
    '5 Читать отсюда внутри готовой группы — только хвост, не начало группы',
    () async {
      final h = await PlaybackHarness.create(
        playbackBook([
          ['Первый абзац.', secondSentence.trimRight(), 'Третий абзац.'],
        ], kind: BlockKind.paragraph),
      );
      await h.cache('Первый абзац.\n${secondSentence.trimRight()}\nТретий абзац.');
      h.controller.readFrom(h.book, 1);
      await h.calls(2);
      expect(h.engine.calls.map((c) => c.text), [
        '${secondSentence.trimRight()}\n',
        'Третий абзац.',
      ]);
      await h.release(0);
      expect(h.controller.unitStart, const ReadingPosition(1, 0));
      expect(h.engine.calls.length, 2);
    },
  );

  test(
    '8 FR-P3 три старта, Закрыть, место переживает новую FileLibrary',
    () async {
      const text =
          'Первое предложение. $secondSentenceТретье предложение.';
      final h = await PlaybackHarness.create(
        playbackBook([
          [text],
        ], kind: BlockKind.paragraph),
      );
      final c = h.controller;
      c.listen(
        h.book,
        const PageRange(ReadingPosition(0, 5), ReadingPosition(0, 45)),
      );
      expect(c.unitStart, const ReadingPosition(0, 20));
      await h.calls(2);
      await h.release(0);
      c.pause();
      c.close(screenPosition: const ReadingPosition(0, 9));
      expect(
        h.library.listeningPositionOf(h.book.id),
        const ReadingPosition(0, 20),
      );
      c.listen(
        h.book,
        const PageRange(ReadingPosition(0, 9), ReadingPosition(0, 45)),
      );
      expect(c.unitStart, const ReadingPosition(0, 20));
      c.close();
      await h.library.flush();
      final restored = FileLibrary(
        h.root,
        settings: AppSettings(voice: 'Aoede', modelId: TtsModel.flash.id),
      );
      await restored.ready;
      expect(
        restored.listeningPositionOf(h.book.id),
        const ReadingPosition(0, 20),
      );
      await restored.flush();
      restored.dispose();
      c.listen(
        h.book,
        const PageRange(ReadingPosition(0, 3), ReadingPosition(0, 10)),
      );
      expect(c.unitStart, const ReadingPosition(0, 0));
      c.close();
      c.readFrom(h.book, 0);
      expect(c.unitStart, const ReadingPosition(0, 0));
      expect(c.state, NarrationState.preparing);
    },
  );

  test('8 скорость с первого звука; явные команды и close с передачей позиции; конец книги', () async {
    final h = await PlaybackHarness.create(
      playbackBook([
        ['Первый.', 'Второй.'],
      ]),
      speed: 2,
    );
    final c = h.controller;
    c.listen(h.book, page);
    await h.calls(2);
    await h.release(0);
    await h.release(1);
    expect(c.speed, 2);
    expect(h.player.speed, 2);
    h.clock.advance(const Duration(milliseconds: 200));
    expect(h.player.position, const Duration(milliseconds: 400));
    final count = h.engine.calls.length, revision = c.commandRevision;
    c.setSpeed(1.5);
    await ioSettled();
    expect(h.engine.calls.length, count);
    expect(c.commandRevision, revision);
    h.clock.advance(const Duration(seconds: 3));
    expect(c.state, NarrationState.stopped);
    expect(c.stopReason, StopReason.endOfBook);
    expect(h.library.isFinished(h.book.id), isTrue);
    expect(c.commandRevision, revision);
    c.close(screenPosition: const ReadingPosition(0, 3));
    expect(c.state, NarrationState.idle);
    expect(h.library.positionOf(h.book.id), const ReadingPosition(0, 3));
    expect(h.library.isFinished(h.book.id), isTrue);
  });

  test('10 профиль книги важнее общего; смена из паузы с того же предложения, без лишнего restart', () async {
    const text = 'Первое предложение. $secondSentenceТретье.';
    final h = await PlaybackHarness.create(
      playbackBook([
        [text],
      ], kind: BlockKind.paragraph),
    );
    h.library.setBookVoice(h.book.id, 'Charon');
    final c = h.controller;
    c.listen(
      h.book,
      const PageRange(ReadingPosition(0, 3), ReadingPosition(0, 45)),
    );
    await h.calls(2);
    expect(h.engine.calls.first.profile.voiceId, 'Charon');
    expect(c.unitStart, const ReadingPosition(0, 20));
    c.pause();
    h.settings.voice = 'Kore';
    final session = c.session, revision = c.commandRevision;
    c.restartSession();
    expect(c.session, session);
    h.library.setBookVoice(h.book.id, 'Kore');
    c.restartSession();
    expect(c.session, session + 1);
    expect(c.state, NarrationState.paused);
    expect(c.unitStart, const ReadingPosition(0, 20));
    expect(c.commandRevision, revision);
    expect(h.engine.calls.length, 2);
    await h.release(0);
    await h.release(1);
    c.resume();
    await h.calls(4);
    expect(h.engine.calls[2].text, secondSentence);
    expect(h.engine.calls[2].profile.voiceId, 'Kore');
    expect(c.state, NarrationState.preparing);
    await h.release(2);
    expect(c.state, NarrationState.playing);
    expect(c.unitStart, const ReadingPosition(0, 20));
    expect(
      segmentParts(segmentsFrom(h.book.blocks, block: 0, offset: 20).first)
          .length,
      2,
    );
  });

  test('5 старт с отрезка короче 80 знаков делает один запрос', () async {
    const text = 'Первое предложение. Второе предложение.';
    final h = await PlaybackHarness.create(
      playbackBook([
        [text],
      ], kind: BlockKind.paragraph),
    );
    expect(text.length, lessThan(firstPartMin));
    h.controller.listen(h.book, page);
    await h.calls(1);
    await ioSettled();
    expect(h.engine.calls.map((call) => call.text), [text]);
    expect(h.controller.state, NarrationState.preparing);
    await h.release(0);
    expect(h.engine.calls.length, 1);
    expect(h.player.items.length, 1);
    expect(h.controller.state, NarrationState.playing);
    expect(h.controller.unitStart, const ReadingPosition(0, 0));
  });
}
