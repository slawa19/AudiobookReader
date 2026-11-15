import 'dart:convert';

import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/reader/page_style.dart';
import 'package:audiobook_reader/screens/common.dart';
import 'package:audiobook_reader/screens/l10n/app_localizations.dart';
import 'package:audiobook_reader/screens/reader_screen.dart';
import 'package:audiobook_reader/screens/reader_sheets.dart';
import 'package:audiobook_reader/screens/settings_screen.dart';
import 'package:audiobook_reader/screens/toc_screen.dart';
import 'package:audiobook_reader/screens/voice_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';
import 'support/harness.dart';

Book contentsBook({bool many = false}) => Book(
  id: 'kapitanskaya',
  title: 'Проверка глав',
  author: '',
  language: 'ru',
  chapters: many
      ? [for (var i = 0; i < 40; i++) Chapter(title: 'Глава $i', level: 1, firstBlock: i, blockCount: 1)]
      : const [
          Chapter(title: 'Настоящее название', level: 1, firstBlock: 0, blockCount: 1),
          Chapter(title: '', level: 1, firstBlock: 1, blockCount: 3),
          Chapter(title: '', level: 1, firstBlock: 4, blockCount: 1),
          Chapter(title: 'После картинки', level: 1, firstBlock: 5, blockCount: 1),
        ],
  blocks: many
      ? [for (var i = 0; i < 40; i++) Block(index: i, kind: BlockKind.paragraph, text: 'Текст $i')]
      : const [
          Block(index: 0, kind: BlockKind.paragraph, text: 'Не заменять настоящее название'),
          Block(index: 1, kind: BlockKind.image, text: ''),
          Block(index: 2, kind: BlockKind.separator, text: ' \n '),
          Block(index: 3, kind: BlockKind.paragraph, text: '  Первые слова\nбезымянной главы и дальнейший текст.  '),
          Block(index: 4, kind: BlockKind.image, text: ''),
          Block(index: 5, kind: BlockKind.paragraph, text: 'Заключение'),
        ],
  notes: const {},
);

Future<void> openContents(WidgetTester tester, Prototype p, Book book, {int current = 0}) async {
  tester
      .state<NavigatorState>(find.byType(Navigator).first)
      .push<int>(
        MaterialPageRoute(
          builder: (_) => TocScreen(services: p.services, book: book, current: current),
        ),
      );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('оглавление: область 48 dp не входит в прокрутку, последняя глава доступна целиком', (tester) async {
    final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
    tester.view.padding = const FakeViewPadding(top: 64, bottom: 96);
    tester.view.viewPadding = const FakeViewPadding(top: 64, bottom: 96);
    await openContents(tester, p, contentsBook(many: true));
    final list = find.byType(ListView);
    const safeBottom = 640.0 - 48;
    expect(tester.getRect(list).bottom, lessThanOrEqualTo(safeBottom));
    final last = find.byKey(const Key('chapter-39'));
    await tester.scrollUntilVisible(
      last,
      300,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(safeBottom));
    expect(tester.getRect(last).top, greaterThan(tester.getRect(list).top));
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(find.byType(TocScreen), findsNothing);
  });

  for (final current in [0, 1, 2]) {
    testWidgets('оглавление: название, начало текста и пропуск картинки (текущая $current)', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await openContents(tester, p, contentsBook(), current: current);
      expect(find.text('Настоящее название'), findsOneWidget);
      expect(find.text('Не заменять настоящее название'), findsNothing);
      final excerpt = find.text('Первые слова безымянной главы и дальнейший текст.');
      expect(excerpt, findsOneWidget);
      final text = tester.widget<Text>(excerpt);
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.style!.fontFamily, tester.widget<Text>(find.text('Настоящее название')).style!.fontFamily);
      expect(text.style!.color, Theme.of(tester.element(excerpt)).colorScheme.onSurfaceVariant);
      expect(find.byType(ListTile), findsNWidgets(3));
      expect(find.text('После картинки'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('48 dp: настройки, голос и все листы прокручиваются над системной областью', (tester) async {
    final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
    tester.view.padding = const FakeViewPadding(top: 64, bottom: 96);
    tester.view.viewPadding = const FakeViewPadding(top: 64, bottom: 96);
    await tester.pumpAndSettle();
    const safeBottom = 640.0 - 48;
    Future<void> close() async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    for (final screen in [SettingsScreen(services: p.services), VoiceScreen(services: p.services)]) {
      tester.state<NavigatorState>(find.byType(Navigator).first).push<void>(MaterialPageRoute(builder: (_) => screen));
      await tester.pumpAndSettle();
      final list = find.byType(CustomScrollView);
      expect(tester.getRect(list).bottom, lessThanOrEqualTo(safeBottom));
      final l10n = AppLocalizations.of(tester.element(list));
      final tail = find.text(
        screen is SettingsScreen ? l10n.storageNote : l10n.probeNote(p.sampler.phraseFor(l10n.localeName)),
      );
      await tester.scrollUntilVisible(
        tail,
        300,
        scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
      );
      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getRect(tail).bottom, lessThanOrEqualTo(safeBottom));
      expect(tester.takeException(), isNull);
      await close();
    }
    final book = contentsBook();
    final context = tester.element(find.byKey(const Key('shelf-title')));
    for (final show in <void Function()>[
      () {
        showTextAppearanceSheet(context, p.settings, p.services.themePreviews);
      },
      () {
        showSpeedSheet(context, p.settings, p.narration);
      },
      () {
        showSleepSheet(context, p.narration);
      },
      () {
        showNoteSheet(
          context,
          book: Book(
            id: book.id,
            title: book.title,
            author: '',
            language: 'ru',
            chapters: book.chapters,
            blocks: book.blocks,
            notes: {
              'note': Note(
                id: 'note',
                blocks: [Block(index: 0, kind: BlockKind.paragraph, text: 'Длинная сноска. ' * 200)],
              ),
            },
          ),
          noteId: 'note',
          style: PageStyle(fontSize: 16, lineHeight: 24, textScaler: TextScaler.linear(1.3)),
        );
      },
      () {
        showScrollableSheet<void>(
          context,
          (_) => Column(children: [for (var i = 0; i < 40; i++) ListTile(title: Text('Пункт $i'))]),
        );
      },
    ]) {
      show();
      await tester.pumpAndSettle();
      await tester.pump(layerSettleTime);
      final scroll = find.byType(SingleChildScrollView);
      expect(tester.getRect(scroll).height, greaterThan(48));
      expect(tester.getRect(scroll).bottom, lessThanOrEqualTo(safeBottom));
      await tester.drag(scroll, const Offset(0, -6000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await close();
    }
    await tester.longPress(find.text('Капитанская дочка'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(SingleChildScrollView)).bottom, lessThanOrEqualTo(safeBottom));
    expect(tester.getRect(find.text('Удалить книгу')).bottom, lessThanOrEqualTo(safeBottom));
  });

  for (final titled in [false, true]) {
    testWidgets('безымянная глава: одна подпись на полке после перезапуска и в шапке (название $titled)', (
      tester,
    ) async {
      final h = AppHarness(tester);
      await h.start();
      final source = utf8.decode(longBook());
      final bytes = utf8.encode(
        titled
            ? source
                  .replaceFirst('<body>', '<body><section><title><p>Настоящее название</p></title>')
                  .replaceFirst('</body>', '</section></body>')
            : source,
      );
      await h.pick(await h.copy(bytes));
      await h.until(() => h.app.library.shelf.isNotEmpty);
      final id = h.app.library.shelf.single.id;
      final book = (await tester.runAsync(() => h.app.library.loadBook(id)))!;
      h.app.library.markOpened(id);
      h.app.library.savePosition(id, const ReadingPosition(0, 0));
      await h.restart();
      final expected = titled
          ? 'Настоящее название'
          : 'Абзац 0. Текст книги для чтения. Текст книги для чтения. Текст книги…';
      await h.until(() => find.text(expected).evaluate().isNotEmpty);
      final shelfText = tester.widget<Text>(find.text(expected));
      expect(shelfText.maxLines, titled ? isNull : 1);
      await tester.tap(find.text(book.title));
      await h.opened();
      await tester.tapAt(tester.getRect(find.byKey(const Key('page-area'))).center);
      await tester.pumpAndSettle();
      final header = tester.widget<Text>(find.byKey(const Key('top-bar-chapter')));
      expect(header.data, expected);
      expect(header.maxLines, titled ? isNull : 1);
      expect(
        h.app.library.shelf.single.chapterTitle,
        titled ? expected : isEmpty,
        reason: 'подпись формируется при показе, название в модели не меняется',
      );
    });
  }

  test('доля: новая, начало, малые значения, округление, 99 % и дочитанная', () {
    final l10n = lookupAppLocalizations(const Locale('ru'));
    expect(shelfProgress(l10n, null), l10n.progressNew);
    for (final (fraction, percent) in [(0.0, 0), (0.004, 0), (0.006, 1), (0.995, 99), (0.9999, 99), (1.0, 100)]) {
      expect(shelfProgress(l10n, fraction), l10n.percent(percent / 100), reason: '$fraction');
    }
  });

  testWidgets('доля: конец позиции без finished не даёт 100 %, finished даёт и после перезапуска', (tester) async {
    final h = AppHarness(tester);
    await h.start();
    await h.pick(await h.copy(longBook()));
    await h.until(() => h.app.library.shelf.isNotEmpty);
    final id = h.app.library.shelf.single.id;
    final book = (await tester.runAsync(() => h.app.library.loadBook(id)))!;
    h.app.library.markOpened(id);
    final last = book.blocks.last;
    h.app.library.savePosition(id, ReadingPosition(last.index, last.text.length));
    expect(h.app.library.isFinished(id), isFalse);
    expect(h.app.library.entry(id).fraction, lessThan(1));
    final l10n = lookupAppLocalizations(const Locale('ru'));
    expect(shelfProgress(l10n, h.app.library.entry(id).fraction), l10n.percent(0.99));
    h.app.library.setFinished(id, true);
    expect(shelfProgress(l10n, h.app.library.entry(id).fraction), l10n.percent(1));
    await h.restart();
    expect(h.app.library.entry(id).fraction, 1);
  });

  testWidgets('доля: одна позиция меньше половины процента совпадает в чтении и на полке', (tester) async {
    final h = AppHarness(tester);
    await h.start();
    final source = utf8.decode(longBook());
    final body = source.substring(source.indexOf('<body>') + 6, source.indexOf('</body>'));
    await h.pick(await h.copy(utf8.encode(source.replaceFirst(body, body * 4))));
    await h.until(() => h.app.library.shelf.isNotEmpty);
    final id = h.app.library.shelf.single.id;
    final book = (await tester.runAsync(() => h.app.library.loadBook(id)))!;
    h.app.library.savePosition(id, const ReadingPosition(1, 0));
    await tester.tap(find.text(book.title));
    await h.opened();
    final state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
    expect(state.layout.pages[state.page].firstBlock, 1);
    final footer = tester.widget<Text>(find.byKey(const Key('footer-percent'))).data;
    final l10n = lookupAppLocalizations(const Locale('ru'));
    expect(footer, l10n.percent(0));
    final fraction = h.app.library.entry(id).fraction!;
    expect(fraction, greaterThan(0));
    expect(fraction, lessThan(0.005));
    expect(shelfProgress(l10n, fraction), footer);
  });

  testWidgets('системные панели: тема меняет значки, подложка Android отключена на полке и в оглавлении', (
    tester,
  ) async {
    final styles = <Map<Object?, Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
        styles.add(call.arguments as Map<Object?, Object?>);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final p = await pumpPrototype(tester);
    for (final choice in [ThemeChoice.dark, ThemeChoice.light, ThemeChoice.sepia]) {
      p.settings.theme = choice;
      await tester.pumpAndSettle();
      await tester.idle();
      final brightness = choice == ThemeChoice.dark ? 'Brightness.light' : 'Brightness.dark';
      void check() {
        expect(styles, isNotEmpty);
        final style = styles.last;
        expect(style['systemNavigationBarIconBrightness'], brightness);
        expect(style['statusBarIconBrightness'], brightness);
        expect(style['systemNavigationBarContrastEnforced'], false);
        expect(style['systemStatusBarContrastEnforced'], false);
        expect(style['systemNavigationBarColor'], 0);
        expect(style['statusBarColor'], 0);
      }

      check();
      await openContents(tester, p, contentsBook());
      await tester.idle();
      check();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      for (final screen in [SettingsScreen(services: p.services), VoiceScreen(services: p.services)]) {
        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .push<void>(MaterialPageRoute(builder: (_) => screen));
        await tester.pumpAndSettle();
        await tester.idle();
        check();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('системные панели: смена темы из листа чтения сразу обновляет значки', (tester) async {
    await pumpPrototype(tester);
    await openBook(tester, 'Капитанская дочка');
    await tester.tapAt(tester.getRect(find.byKey(const Key('page-area'))).center);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Вид текста'));
    await tester.pumpAndSettle();
    await tester.pump(layerSettleTime);
    for (final name in ['dark', 'light', 'sepia']) {
      await tester.tap(find.byKey(Key('theme-$name')));
      await tester.pumpAndSettle();
      await tester.idle();
      final style = SystemChrome.latestStyle!;
      final icons = name == 'dark' ? Brightness.light : Brightness.dark;
      expect(style.statusBarIconBrightness, icons);
      expect(style.systemNavigationBarIconBrightness, icons);
      expect(style.systemNavigationBarContrastEnforced, isFalse);
      expect(style.systemStatusBarContrastEnforced, isFalse);
    }
  });
}
