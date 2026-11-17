import 'package:audiobook_reader/playback/controller.dart';
import 'package:audiobook_reader/playback/narration.dart';
import 'package:audiobook_reader/playback/file_chapter_download.dart';
import 'package:audiobook_reader/tts/fake_engine.dart';
import 'package:audiobook_reader/screens/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/flows.dart';

Future<void> openBook(AppHarness h) async {
  final file = await h.copy(shortBook());
  h.files.events.add(file);
  await h.opened();
  await h.deleted(file);
  await tapCenter(h.tester);
}

void main() {
  testWidgets('chapter loading uses the shared queue, stops new requests in background and releases the screen hold', (
    tester,
  ) async {
    final h = AppHarness(tester);
    await h.start(fakeTts: true, synthesis: FakeTtsEngine(manual: true, sampleRate: 100, secondsPerCharacter: 0.1));
    final file = await h.copy(longBook());
    h.files.events.add(file);
    await h.opened();
    await h.deleted(file);
    final book = (await tester.runAsync(() => h.app.library.loadBook(h.app.library.shelf.single.id)))!;
    final downloads = h.app.services.downloads as FileChapterDownloads;
    expect(downloads.queue, same(h.app.queue));
    expect((h.app.services.narration as FileNarrationController).downloads, same(downloads));
    downloads.start(book, 0, downloads.profileFor(book.id));
    await h.until(() => h.engine.calls.isNotEmpty);
    expect(h.screenAwake.values.last, isTrue);
    h.app.setForeground(false);
    expect(h.screenAwake.values.last, isFalse);
    final before = h.engine.calls.length;
    for (final call in h.engine.calls.toList()) {
      call.release();
    }
    await h.until(() => h.app.queue.inFlight == 0);
    await tester.pump();
    expect(h.engine.calls, hasLength(before));
    h.app.setForeground(true);
    await h.until(() => h.engine.calls.length > before);
    expect(h.screenAwake.values.last, isTrue);
    downloads.stop();
    expect(h.screenAwake.values.last, isFalse);
    for (final call in h.engine.calls.toList()) {
      call.release();
    }
    await h.until(() => h.app.queue.inFlight == 0);
  });
  testWidgets('regular build without a key: Listen opens settings, no synthesis', (tester) async {
    final h = AppHarness(tester);
    await h.start();
    await openBook(h);
    await tester.tap(find.text('Слушать'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(h.engine.calls, isEmpty);
    expect(h.app.services.narration.state, NarrationState.idle);
  });

  for (final fake in [false, true]) {
    testWidgets('${fake ? 'fake build without a key' : 'regular build with a key'}: real controller and '
        'files', (tester) async {
      final h = AppHarness(tester);
      await h.start(fakeTts: fake);
      if (!fake) h.app.settings.apiKey = 'test-key';
      await openBook(h);
      expect(h.app.services.narration, isA<FileNarrationController>());
      await tester.tap(find.text('Слушать'));
      await h.until(() => h.player.playing);
      expect(h.engine.calls, isNotEmpty);
      expect(h.app.services.narration.state, NarrationState.playing);
      expect(h.app.services.audio.totalBytes, greaterThan(0));
      expect(h.app.services.spentByMonth().first.dollars, greaterThan(0));
      expect(find.byType(SettingsScreen), findsNothing);
      if (fake) expect(h.app.settings.apiKey, isNull);
      h.app.services.narration.pause();
      await tester.pumpAndSettle();
    });
  }
}
