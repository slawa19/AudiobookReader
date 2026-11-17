import 'dart:async';

import 'package:audiobook_reader/playback/narration.dart';
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

Future<void> listen(AppHarness h) async {
  await h.tester.tap(find.text('Слушать'));
  await h.until(() => h.player.playing);
}

void main() {
  testWidgets('the permission is asked once, when listening starts; after a refusal playback goes on and the app does '
      'not ask again, also after a restart', (tester) async {
    final h = AppHarness(tester);
    await h.start(fakeTts: true);
    await openBook(h);
    // The other side: opening a book and showing the panels does not ask.
    expect(h.notificationRequests, 0);
    expect(h.app.settings.notificationsAsked, isFalse);

    await listen(h);
    expect(h.notificationRequests, 1);
    expect(h.app.settings.notificationsAsked, isTrue);
    // The fake dialog answered "Don't allow": listening is not affected.
    expect(h.app.services.narration.state, NarrationState.playing);

    h.app.services.narration.pause();
    await tester.pumpAndSettle();
    h.app.services.narration.resume();
    await h.until(() => h.player.playing);
    expect(h.notificationRequests, 1);

    h.app.services.narration.pause();
    await tester.pumpAndSettle();
    await h.restart();
    await openBook(h);
    await listen(h);
    expect(h.notificationRequests, 1);
    h.app.services.narration.pause();
    await tester.pumpAndSettle();
  });

  testWidgets('playback does not wait for the answer: the dialog is still open and the sound already plays', (
    tester,
  ) async {
    final h = AppHarness(tester);
    final dialog = Completer<bool>();
    h.notificationAnswer = () => dialog.future;
    await h.start(fakeTts: true);
    await openBook(h);
    await listen(h);
    expect(h.notificationRequests, 1);
    expect(dialog.isCompleted, isFalse);
    expect(h.app.services.narration.state, NarrationState.playing);
    dialog.complete(true);
    h.app.services.narration.pause();
    await tester.pumpAndSettle();
  });
}
