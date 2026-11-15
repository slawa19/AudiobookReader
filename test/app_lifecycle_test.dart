import 'dart:convert';
import 'dart:io';

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/screens/common.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';
import 'support/flows.dart';
import 'support/harness.dart';
import 'support/library_time.dart';

ReadingPosition shown(WidgetTester tester) {
  final st = reader(tester);
  final page = st.layout.pages[st.page];
  return ReadingPosition(page.firstBlock, page.firstOffset);
}

Future<String> openLongBook(AppHarness h) async {
  final file = await h.copy(longBook());
  h.files.events.add(file);
  await h.opened();
  await h.deleted(file);
  final id = h.app.library.shelf.single.id;
  await h.until(() => h.diskState(id)['lastOpened'] != null);
  // Дожидаемся записи открытия и первой раскладки. Она вправе уже сохранить
  // начальную позицию; проверяем последующее движение на замороженных часах.
  await h.finish(h.app.library.flush());
  return id;
}

void main() {
  testWidgets('один уход в фон: одна ошибка записи, книга остаётся открытой', (tester) async {
    final h = AppHarness(tester);
    await h.start();
    final id = await openLongBook(h);
    final blocked = Directory('${h.root.path}/books/$id/state.json.new');
    await tester.runAsync(() => blocked.create());
    try {
      await tapRightThird(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await h.until(() => h.app.library.addJobs.isNotEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(h.app.library.addJobs, hasLength(1));
    } finally {
      await tester.runAsync(() => blocked.delete());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await h.finish(h.app.flush());
    }
    expect(h.diskState(id)['position'], isNotNull);
  });

  testWidgets('FR-R7,I1: закрытие немедленно пишет место; новая полка сохраняет шрифт, тему, язык и страницу', (
    tester,
  ) async {
    final h = AppHarness(tester);
    await h.start();
    final id = await openLongBook(h);
    final before = h.diskState(id)['position'];
    await tapCenter(tester);
    await tester.tap(find.byTooltip('Вид текста'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('font-larger')));
    await tester.tap(find.byKey(const Key('theme-dark')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tapCenter(tester);
    await tapRightThird(tester);
    await tapRightThird(tester);
    await tapRightThird(tester);
    final at = shown(tester);
    expect(reader(tester).page, greaterThan(0));
    expect(at, isNot(const ReadingPosition(0, 0)));
    // Часы писателя заморожены: без flush новая позиция остаётся только в памяти.
    expect(h.diskState(id)['position'], before);
    expect(ReadingPosition.fromJson(before as Map<String, dynamic>), isNot(at));
    expect(h.time.activeTimers, greaterThan(0));
    await tapCenter(tester);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    await h.until(() => ReadingPosition.fromJson(h.diskState(id)['position'] as Map<String, dynamic>) == at);
    expect(ReadingPosition.fromJson(h.diskState(id)['position'] as Map<String, dynamic>), at);
    // Позиция уже проверена без ручного flush. Теперь завершаем весь flush
    // закрытия (включая настройки), прежде чем начинать отдельную сцену языка.
    await h.finish(h.app.flush());
    final config = File('${h.root.path}/settings.json');
    await h.until(config.existsSync);

    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('settings-language')));
    await tester.tap(find.byKey(const Key('settings-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-de')));
    await tester.pumpAndSettle();
    expect(find.text('Einstellungen'), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect((jsonDecode(config.readAsStringSync()) as Map<String, dynamic>)['language'], isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await h.until(() => (jsonDecode(config.readAsStringSync()) as Map<String, dynamic>)['language'] == 'de');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.restart();
    expect(h.app.library.shelf, hasLength(1));
    expect(h.app.settings.fontStep, defaultFontStep + 1);
    expect(h.app.settings.theme, ThemeChoice.dark);
    expect(h.app.settings.language, 'de');
    expect(h.app.settings.hasApiKey, isFalse);
    expect(find.text('Bücher'), findsOneWidget);
    await tester.tap(find.text('Краткая'));
    await h.opened();
    expect(shown(tester), at);
    expect(reader(tester).pageStyle.fontSize, fontSteps[defaultFontStep + 1].size);
    expect(Theme.of(tester.element(find.byKey(const Key('page-area')))).brightness, Brightness.dark);
  });

  testWidgets('фон немедленно пишет последнюю позицию, не ожидая секундного таймера', (tester) async {
    final h = AppHarness(tester);
    await h.start();
    final id = await openLongBook(h);
    final before = h.diskState(id)['position'];
    await tapRightThird(tester);
    await tapRightThird(tester);
    final at = shown(tester);
    expect(reader(tester).page, greaterThan(0));
    expect(h.diskState(id)['position'], before);
    expect(ReadingPosition.fromJson(before as Map<String, dynamic>), isNot(at));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await h.until(() => ReadingPosition.fromJson(h.diskState(id)['position'] as Map<String, dynamic>) == at);
    expect(ReadingPosition.fromJson(h.diskState(id)['position'] as Map<String, dynamic>), at);
    expect(h.time.activeTimers, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('FR-L5: удаление через полку удаляет целиком папку книги', (tester) async {
    final h = AppHarness(tester);
    await h.start();
    final file = await h.copy(shortBook());
    await h.pick(file);
    await h.deleted(file);
    await h.until(() => h.app.library.shelf.isNotEmpty);
    await tester.pumpAndSettle();
    final entry = h.app.library.shelf.single;
    final dir = Directory('${h.root.path}/books/${entry.id}');
    expect(dir.existsSync(), isTrue);
    await tester.longPress(find.text('Краткая'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить книгу'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final l10n = tester.element(dialog).l10n;
    final body = l10n.deleteBookBody(entry.title, formatBytes(l10n, entry.bookBytes));
    expect(find.descendant(of: dialog, matching: find.text(body)), findsOneWidget);
    await tester.tap(find.descendant(of: dialog, matching: find.text(l10n.cancel)));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(dir.existsSync(), isTrue);
    expect(h.app.library.shelf.single.id, entry.id);
    await tester.longPress(find.text('Краткая'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить книгу'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text(body)), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    await h.until(() => !dir.existsSync() && h.app.library.shelf.isEmpty);
    expect(find.text('Добавить книгу'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('FR-R8: полка 360 dp × $scale, последняя строка выше панели и +', (tester) async {
      final h = AppHarness(tester);
      await h.start(textScale: scale);
      await tester.runAsync(() async {
        for (var i = 0; i < 12; i++) {
          final bytes = utf8.encode(
            utf8.decode(shortBook()).replaceFirst('Краткая', 'Длинное название книги номер $i'),
          );
          await h.app.library.addTestBytes(bytes, '$i.fb2');
        }
      });
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(scroll.maxScrollExtent, greaterThan(0));
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pumpAndSettle();
      final last = find.text('Длинное название книги номер 0');
      expect(last, findsOneWidget);
      final row = find.ancestor(of: last, matching: find.byType(InkWell)).first;
      final rowRect = tester.getRect(row);
      final fab = tester.getRect(find.byType(FloatingActionButton));
      expect(rowRect.bottom, lessThanOrEqualTo(fab.top));
      expect(rowRect.bottom, lessThanOrEqualTo(800 - 48));
      final viewport = tester.getRect(find.byType(CustomScrollView));
      expect(viewport.bottom, 800 - 48, reason: 'список обрезан до системной панели');
      expect(tester.takeException(), isNull);
    });
  }
}
