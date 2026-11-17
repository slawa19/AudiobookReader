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
import 'support/library_time.dart';

// The start of an unnamed chapter is also in the header. Here we check the page itself.
Finder pageText(String text) => find.descendant(
  of: find.byType(BookPage), matching: find.textContaining(text, findRichText: true));

void main() {
  testWidgets('+ stays available while the previous pick is being parsed', (tester) async {
    final gate = Completer<ParsedBook>();
    final h = AppHarness(tester);
    await h.start(parser: (_) => gate.future);
    final file = await h.copy(shortBook());
    await h.pick(file);
    await h.until(() => h.app.library.addJobs.isNotEmpty);
    // The button appears together with the row; wait for its animation, not for the parsing spinner.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Добавить книгу'));
    await tester.pump();
    final picks = h.files.picks;
    gate.complete(parseBook(shortBook()));
    await h.deleted(file);
    expect(picks, 2);
    expect(h.app.library.shelf, hasLength(1));
  });

  testWidgets('FR-L2: + → Adding → shelf → real sample text', (tester) async {
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
    expect(pageText('Один.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling the system picker changes nothing', (tester) async {
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
    testWidgets('FR-B2: failure ${reason.name} is shown, the temporary copy is deleted', (tester) async {
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

  testWidgets('FR-L3: picking again opens the existing book and deletes the copy', (tester) async {
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
    testWidgets('external file ${cold ? 'before subscription' : 'after subscription'} is added and '
        'opened', (tester) async {
      final h = AppHarness(tester);
      await h.start(mount: !cold);
      final bytes = zip({'book.fb2': shortBook()});
      final file = await h.copy(bytes, 'book.fb2.zip');
      h.files.events.add(file);
      if (cold) await h.pump();
      await h.opened();
      await h.deleted(file);
      expect(pageText('Один.'), findsOneWidget);
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

  testWidgets('picker, read and stream errors are shown; an EPUB arrives after onError', (tester) async {
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
    expect(pageText('Текст EPUB.'), findsOneWidget);
    expect(h.files.subscriptions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an external book over reading replaces the book and stays in reading mode', (tester) async {
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
    expect(pageText('Один.'), findsOneWidget);
    expect(systemBarsHidden.value, isTrue);
  });

  for (final copyError in [false, true]) {
    testWidgets(
      'a late shelf load does not override ${copyError ? 'the copy failure' : 'a newer external book'}',
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
          library.delayedId = (await library.addTestBytes(longBook(), 'first.fb2'))!.id;
          return library;
        }))!;
        h.app = NativeApplication.fromLibrary(library, h.files);
        await h.pump();
        await tester.tap(find.text('Краткая'));
        await h.until(() => library.entered.isCompleted);
        expect(find.byType(ReaderScreen), findsNothing, reason: 'the shelf stays until loading finishes');
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
          expect(pageText('Один.'), findsOneWidget);
        }
        expect(library.entry(library.delayedId!).opened, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
