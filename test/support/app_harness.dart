import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/app/native_application.dart';
import 'package:audiobook_reader/library/file_library.dart';
import 'package:audiobook_reader/library/incoming_files.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'book_samples.dart';
import 'library_time.dart';

/// Одиночный поток хранит события до подписки, как Android при холодном запуске.
class TestIncomingFiles implements IncomingFiles {
  final events = StreamController<IncomingFile>();
  IncomingFile? picked;
  Object? pickError;
  int picks = 0;
  int subscriptions = 0;

  @override
  Stream<IncomingFile> get incomingFiles {
    subscriptions++;
    return events.stream;
  }

  @override
  Future<IncomingFile?> pickFile() async {
    picks++;
    if (pickError != null) throw pickError!;
    final file = picked;
    picked = null;
    return file;
  }
}

List<int> shortBook() => utf8.encode(fixture('fb2_metadata.xml'));

/// Тот же образец с длинным телом: несколько настоящих страниц для проверки позиции.
List<int> longBook() => utf8.encode(
  fixture('fb2_metadata.xml').replaceFirst(
    '<p>Один.</p>',
    List.generate(100, (i) => '<p>Абзац $i. ${'Текст книги для чтения. ' * 12}</p>').join(),
  ),
);

class AppHarness {
  AppHarness(this.tester);
  final WidgetTester tester;
  late Directory root;
  late NativeApplication app;
  TestIncomingFiles files = TestIncomingFiles();
  final time = LibraryTime();
  int _copies = 0;

  Future<void> start({LibraryParser? parser, bool mount = true, double textScale = 1}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.padding = const FakeViewPadding(top: 32, bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 48);
    tester.platformDispatcher.localesTestValue = [const Locale('ru')];
    tester.platformDispatcher.localeTestValue = const Locale('ru');
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('reader-app-');
      await create(parser: parser);
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await finish(app.library.flush());
      app.services.narration.dispose();
      app.services.downloads.dispose();
      app.services.sampler.dispose();
      app.library.dispose();
      app.settings.dispose();
      await finish(files.events.close());
      await tester.runAsync(() async {
        await root.delete(recursive: true);
      });
      tester.view.reset();
      tester.platformDispatcher.clearAllTestValues();
    });
    if (mount) await pump();
  }

  Future<void> create({LibraryParser? parser}) async {
    app = await NativeApplication.create(
      root: root,
      incoming: files,
      parser: parser,
      clock: time.call,
      timer: time.timer,
    );
  }

  Future<void> restart() async {
    await tester.pumpWidget(const SizedBox());
    await finish(app.library.flush());
    app.services.narration.dispose();
    app.services.downloads.dispose();
    app.services.sampler.dispose();
    app.library.dispose();
    app.settings.dispose();
    await finish(files.events.close());
    files = TestIncomingFiles();
    await tester.runAsync(() => create());
    await pump();
  }

  Future<void> pump() async {
    await tester.pumpWidget(AudiobookApp.application(assembly: app));
    await tester.pumpAndSettle();
  }

  Future<IncomingFile> copy(List<int> bytes, [String name = 'book.fb2']) async => (await tester.runAsync(() async {
    final file = File('${root.path}/incoming/${_copies++}');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return IncomingFile(path: file.path, name: name);
  }))!;

  Future<void> pick(IncomingFile? file) async {
    files.picked = file;
    await tester.pumpAndSettle();
    final fab = find.byType(FloatingActionButton);
    await tester.tap(fab.evaluate().isEmpty ? find.text('Добавить книгу') : fab);
    await tester.pump();
  }

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 500 && !condition(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(condition(), isTrue, reason: 'не дождались результата дисковой операции');
  }

  Future<void> deleted(IncomingFile file) async {
    await until(() => !File(file.path).existsSync());
  }

  Future<void> finish(Future<void> operation) async {
    var done = false;
    Object? error;
    operation.then(
      (_) => done = true,
      onError: (Object e) {
        error = e;
        done = true;
      },
    );
    await until(() => done);
    if (error != null) throw error!;
  }

  Future<void> opened() async {
    await until(() => find.byType(ReaderScreen).evaluate().isNotEmpty);
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> diskState(String id) =>
      jsonDecode(File('${root.path}/books/$id/state.json').readAsStringSync()) as Map<String, dynamic>;
}
