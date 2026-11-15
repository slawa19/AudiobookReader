import 'dart:convert';
import 'dart:io';

import 'package:audiobook_reader/library/file_library.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/book_samples.dart';
import 'support/library_time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late FileLibrary library;
  late LibraryTime time;

  Future<void> start() async {
    library = FileLibrary(
      root,
      settings: AppSettings(voice: 'voice', modelId: 'model'),
      clock: time.call,
      timer: time.timer,
    );
    await library.ready;
  }

  Future<void> record(String model, int audio, int input, {DateTime? at}) =>
      library.recordUsage(
        modelId: model,
        audioTokens: audio,
        inputTokens: input,
        at: at,
      );

  void expectTokens(DateTime month, String model, int audio, int input) {
    final tokens = library.usage[month]![model]!;
    expect(tokens.audioTokens, audio);
    expect(tokens.inputTokens, input);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('library-usage-');
    time = LibraryTime()..now = DateTime(2026, 11, 15);
    await start();
  });

  tearDown(() async {
    await library.flush();
    library.dispose();
    library.settings.dispose();
    await root.delete(recursive: true);
  });

  test(
    'FR-M2: суммы независимы по месяцам и строковым идентификаторам моделей',
    () async {
      expect(library.usage, isEmpty);
      await record('flash', 100, 10);
      await record('flash', 20, 3);
      await record('другая-модель', 80, 5);
      await record('flash', 7, 2, at: DateTime(2026, 10, 31, 23, 59));
      expect(library.usage, hasLength(2));
      expect(library.usage[DateTime(2026, 11)], hasLength(2));
      expectTokens(DateTime(2026, 11), 'flash', 120, 13);
      expectTokens(DateTime(2026, 11), 'другая-модель', 80, 5);
      expectTokens(DateTime(2026, 10), 'flash', 7, 2);
    },
  );

  test('подставные часы: границы месяца и года не смешивают расход', () async {
    time.now = DateTime(2026, 11, 30, 23, 59, 59);
    await record('model', 1, 2);
    time.advance(const Duration(seconds: 1));
    await record('model', 3, 4);
    time.now = DateTime(2026, 12, 31, 23, 59, 59);
    await record('model', 5, 6);
    time.advance(const Duration(seconds: 1));
    await record('model', 7, 8);
    expectTokens(DateTime(2026, 11), 'model', 1, 2);
    expectTokens(DateTime(2026, 12), 'model', 8, 10);
    expectTokens(DateTime(2027, 1), 'model', 7, 8);
  });

  test(
    'месяц UTC-момента определяется после перевода в местное время',
    () async {
      final local = DateTime(2027, 1, 1, 0, 30);
      await record('model', 9, 4, at: local.toUtc());
      expect(library.usage.keys, [DateTime(2027, 1)]);
      expectTokens(DateTime(2027, 1), 'model', 9, 4);
    },
  );

  test('два одновременных ответа учтены ровно по одному разу', () async {
    await Future.wait([record('model', 20, 2), record('model', 30, 3)]);
    expectTokens(DateTime(2026, 11), 'model', 50, 5);
    // Повторный вызов — новый ответ: дедупликация принадлежит очереди, не библиотеке.
    await record('model', 20, 2);
    expectTokens(DateTime(2026, 11), 'model', 70, 7);
  });

  test(
    'Future записи означает готовый usage.json без flush и ожидания секунды',
    () async {
      // Другие настройки уже заняли писателя в ту же подставную секунду.
      library.settings.theme = ThemeChoice.dark;
      await library.flush();
      library.settings.language = 'pl';
      expect(time.activeTimers, 1);
      await record('model', 42, 8);
      expect(time.activeTimers, 1);
      expect(await File('${root.path}/usage.json.new').exists(), isFalse);
      library.dispose();
      library.settings.dispose();
      // Имитируем потерю процесса: никаких flush перед новой библиотекой.
      await start();
      expectTokens(DateTime(2026, 11), 'model', 42, 8);
      expect(
        library.settings.language,
        isNull,
        reason: 'отложенная запись настроек не была принудительно выполнена',
      );
      await record('model', 2, 1);
      expectTokens(DateTime(2026, 11), 'model', 44, 9);
    },
  );

  test('расход, обе позиции и голос сохраняются общим писателем', () async {
    final entry = await library.addTestBytes(
      utf8.encode(fixture('fb2_sections.xml')),
      'book.fb2',
    );
    final id = entry!.id;
    await library.loadBook(id);
    await library.flush();
    library.savePosition(id, const ReadingPosition(1, 1));
    final first = record('model', 10, 1);
    library.saveListeningPosition(id, const ReadingPosition(2, 1));
    library.setBookVoice(id, 'другой голос');
    final second = record('model', 20, 2);
    await Future.wait([first, second, library.flush()]);
    library.dispose();
    library.settings.dispose();
    await start();
    expectTokens(DateTime(2026, 11), 'model', 30, 3);
    expect(library.positionOf(id), const ReadingPosition(1, 1));
    expect(library.listeningPositionOf(id), const ReadingPosition(2, 1));
    expect(library.bookVoice(id), 'другой голос');
  });

  for (final broken in [
    '',
    '{broken',
    '[]',
    'null',
    '{"2026-13":{}}',
    '{"not-a-month":{}}',
    '{"2026-11":{"model":null}}',
    '{"2026-11":{"model":{"audioTokens":-1,"inputTokens":2}}}',
    '{"2026-11":{"model":{"audioTokens":1.5,"inputTokens":2}}}',
  ]) {
    test('битый usage.json не роняет запуск: $broken', () async {
      await record('model', 1, 2);
      library.dispose();
      library.settings.dispose();
      await File('${root.path}/usage.json').writeAsString(broken);
      await start();
      expect(library.usage, isEmpty);
      await record('model', 3, 4);
      expectTokens(DateTime(2026, 11), 'model', 3, 4);
    });
  }

  test('сбой записи не портит прежний файл и не отравляет очередь', () async {
    await record('model', 10, 1);
    final file = File('${root.path}/usage.json');
    final before = await file.readAsString();
    final blocked = await Directory('${file.path}.new').create();
    await expectLater(
      record('model', 20, 2),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsString(), before);
    expectTokens(DateTime(2026, 11), 'model', 10, 1);
    await blocked.delete();
    await record('model', 20, 2);
    expectTokens(DateTime(2026, 11), 'model', 30, 3);
  });

  test(
    'снимок расхода неизменяемый и не меняется после нового ответа',
    () async {
      await record('model', 10, 1);
      final snapshot = library.usage;
      expect(() => snapshot.clear(), throwsUnsupportedError);
      expect(() => snapshot.values.single.clear(), throwsUnsupportedError);
      await record('model', 20, 2);
      expect(snapshot.values.single['model']!.audioTokens, 10);
      expectTokens(DateTime(2026, 11), 'model', 30, 3);
    },
  );

  test(
    'отрицательные токены не записываются, нулевой ответ допустим',
    () async {
      await expectLater(record('model', -1, 1), throwsArgumentError);
      await expectLater(record('model', 1, -1), throwsArgumentError);
      expect(library.usage, isEmpty);
      expect(await File('${root.path}/usage.json').exists(), isFalse);
      await record('model', 0, 0);
      expectTokens(DateTime(2026, 11), 'model', 0, 0);
    },
  );
}
