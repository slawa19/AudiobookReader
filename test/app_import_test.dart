import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audiobook_reader/book/parse.dart';
import 'package:audiobook_reader/app/native_application.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/reader/book_page.dart';
import 'package:audiobook_reader/screens/common.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/book_samples.dart';
import 'support/flows.dart';
import 'support/harness.dart';
import 'support/gated_file_library.dart';

void main() {
  testWidgets('FR-L2: + → Добавляется → полка → настоящий текст образца', (tester) async {
    final gate = Completer<ParsedBook>();
    final h = AppHarness(tester);
    await h.start(parser: (_) => gate.future);
    expect(h.app.library.shelf, isEmpty);
    expect(h.app.settings.hasApiKey, isFalse);
    expect(h.app.services.openDemoStates, isNull);
    expect(find.text('Добавить книгу'), findsOneWidget);
    final file = await h.copy(shortBook());
    await h.pick(file);
    await h.until(() => h.app.library.addJobs.isNotEmpty);
    expect(find.text('Добавляется…'), findsOneWidget);
    expect(h.app.library.shelf, isEmpty);
    gate.complete(parseBook(shortBook()));
    await h.until(() => h.app.library.shelf.isNotEmpty);
    await h.deleted(file);
    await tester.pumpAndSettle();
    expect(find.text('Краткая'), findsOneWidget);
    await tester.tap(find.text('Краткая'));
    await h.opened();
    expect(find.byType(BookPage), findsWidgets);
    expect(find.textContaining('Один.', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('отмена системного выбора ничего не меняет', (tester) async {
    final h = AppHarness(tester);
    await h.start();
    await h.pick(null);
    await tester.pumpAndSettle();
    expect(h.files.picks, 1);
    expect(h.app.library.shelf, isEmpty);
    expect(h.app.library.addJobs, isEmpty);
    expect(find.byType(ReaderScreen), findsNothing);
  });

  final failures = [
    (AddFailure.unsupported, () => utf8.encode('%PDF-1.7'), 'Этот формат не поддерживается'),
    (AddFailure.unreadable, () => utf8.encode(fixture('fb2_bad_attribute.xml')), 'Не удалось прочитать книгу'),
    (
      AddFailure.protected,
      () => epub(encryption: 'OPS/text.xhtml'),
      'Книга защищена от копирования, открыть её нельзя',
    ),
  ];
  for (final (reason, bytes, message) in failures) {
    testWidgets('FR-B2: отказ ${reason.name} виден, временная копия удалена', (tester) async {
      final h = AppHarness(tester);
      await h.start();
      final file = await h.copy(bytes(), 'refused.book');
      await h.pick(file);
      await h.until(() => h.app.library.addJobs.any((j) => j.status == AddJobStatus.failed));
      await h.deleted(file);
      await tester.pumpAndSettle();
      expect(h.app.library.shelf, isEmpty);
      expect(h.app.library.addJobs.single.failure, reason);
      expect(find.text(message), findsOneWidget);
      if (reason == AddFailure.unreadable) {
        expect(find.text(h.app.library.addJobs.single.technical!), findsOneWidget);
      }
      expect(find.byType(ReaderScreen), findsNothing);
    });
  }

  testWidgets('FR-L3: повтор выбора открывает существующую книгу и удаляет копию', (tester) async {
    final h = AppHarness(tester);
    await h.start();
    final first = await h.copy(shortBook());
    await h.pick(first);
    await h.deleted(first);
    await h.until(() => h.app.library.shelf.isNotEmpty);
    await tester.pumpAndSettle();
    final again = await h.copy(shortBook());
    await h.pick(again);
    await h.opened();
    await h.deleted(again);
    expect(h.app.library.shelf, hasLength(1));
    expect(reader(tester).widget.book.id, h.app.library.shelf.single.id);
    expect(h.app.library.addJobs, isEmpty);
  });

  for (final cold in [false, true]) {
    testWidgets('внешний файл ${cold ? 'до подписки' : 'после подписки'} добавляется и открывается', (tester) async {
      final h = AppHarness(tester);
      await h.start(mount: !cold);
      final bytes = zip({'book.fb2': shortBook()});
      final file = await h.copy(bytes, 'book.fb2.zip');
      h.files.events.add(file);
      if (cold) await h.pump();
      await h.opened();
      await h.deleted(file);
      expect(find.textContaining('Один.', findRichText: true), findsOneWidget);
      expect(h.files.subscriptions, 1);
      await tapCenter(tester);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      final again = await h.copy(bytes);
      h.files.events.add(again);
      await h.opened();
      await h.deleted(again);
      expect(h.app.library.shelf, hasLength(1));
      expect(h.files.subscriptions, 1);
    });
  }

  testWidgets('ошибки выбора, чтения и потока видны; после onError приходит EPUB', (tester) async {
    final h = AppHarness(tester);
    await h.start();
    h.files.pickError = StateError('copy refused');
    await h.pick(null);
    await h.until(() => h.app.library.addJobs.isNotEmpty);
    expect(find.textContaining('copy refused'), findsOneWidget);
    h.files.pickError = null;
    final missing = await h.copy(shortBook());
    await tester.runAsync(() => File(missing.path).delete());
    await h.pick(missing);
    await h.until(() => h.app.library.addJobs.length == 2);
    await tester.pump();
    expect(find.text(h.app.library.addJobs.first.technical!), findsOneWidget);
    h.files.events.addError(StateError('external copy refused'));
    await h.until(() => h.app.library.addJobs.length == 3);
    expect(find.textContaining('external copy refused'), findsOneWidget);
    final file = await h.copy(
      epub(
        content: '<html><body><p>Текст EPUB.</p></body></html>',
        nav: fixture('epub_single_nav.xhtml'),
        raw: {'OPS/pic.png': File('assets/demo/covers/dama.png').readAsBytesSync()},
      ),
      'book.epub',
    );
    h.files.events.add(file);
    await h.opened();
    await h.deleted(file);
    expect(find.textContaining('Текст EPUB.', findRichText: true), findsOneWidget);
    expect(h.files.subscriptions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('внешняя книга поверх чтения заменяет книгу и остаётся в режиме чтения', (tester) async {
    final h = AppHarness(tester);
    await h.start();
    final first = await h.copy(longBook());
    h.files.events.add(first);
    await h.opened();
    final id = reader(tester).widget.book.id;
    final second = await h.copy(shortBook());
    h.files.events.add(second);
    await h.until(() => find.byType(ReaderScreen).evaluate().any((e) => (e.widget as ReaderScreen).book.id != id));
    await h.deleted(second);
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.textContaining('Один.', findRichText: true), findsOneWidget);
    expect(systemBarsHidden.value, isTrue);
  });

  for (final copyError in [false, true]) {
    testWidgets(
      'поздняя загрузка с полки не перекрывает ${copyError ? 'отказ копирования' : 'более новую внешнюю книгу'}',
      (tester) async {
        final h = AppHarness(tester);
        await h.start(mount: false);
        final original = h.app;
        original.library.dispose();
        original.services.narration.dispose();
        original.services.downloads.dispose();
        original.services.sampler.dispose();
        final library = (await tester.runAsync(() async {
          final library = GatedFileLibrary(
            h.root,
            settings: original.settings,
            clock: h.time.call,
            timer: h.time.timer,
          );
          await library.ready;
          library.delayedId = (await library.addBytes(longBook(), 'first.fb2'))!.id;
          return library;
        }))!;
        h.app = NativeApplication.fromLibrary(library, h.files);
        await h.pump();
        await tester.tap(find.text('Краткая'));
        await h.until(() => library.entered.isCompleted);
        expect(find.byType(ReaderScreen), findsNothing, reason: 'до загрузки остаётся полка');
        expect(find.text('Краткая'), findsOneWidget);
        String? externalId;
        if (copyError) {
          h.files.events.addError(StateError('external copy refused'));
          await h.until(() => library.addJobs.isNotEmpty);
        } else {
          final file = await h.copy(shortBook());
          h.files.events.add(file);
          await h.opened();
          externalId = reader(tester).widget.book.id;
          expect(externalId, isNot(library.delayedId));
        }
        library.release.complete();
        await h.until(() => library.delivered.isCompleted);
        await tester.pumpAndSettle();
        if (copyError) {
          expect(find.byType(ReaderScreen), findsNothing);
          expect(find.textContaining('external copy refused'), findsOneWidget);
        } else {
          expect(find.byType(ReaderScreen), findsOneWidget);
          expect(reader(tester).widget.book.id, externalId);
          expect(find.textContaining('Один.', findRichText: true), findsOneWidget);
        }
        expect(library.entry(library.delayedId!).opened, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
