// Экраны и переходы пальцем: полка, голос, настройки, «Вид текста», поворот экрана (разделы E и F проверки
// жестов 2026-11-14).

import 'dart:io';

import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/library/settings.dart';
import 'package:audiobook_reader/playback/voice_sample.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gesture_support.dart';
import 'support/flows.dart';
import 'support/harness.dart';

void main() {
  group('полка', () {
    testWidgets('книга тронута дважды подряд (в том числе при медленном чтении с диска): открыт один экран чтения',
        (tester) async {
      final p = await pumpPrototype(tester);
      p.library.loadDelay = const Duration(milliseconds: 300);
      final c = tester.getCenter(find.text('Капитанская дочка').first);
      await quickTap(tester, c);
      await frames(tester, 120);
      await quickTap(tester, c);
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.byKey(const Key('page-area')), findsOneWidget);
      // Приведено к решению J: в иммерсивном чтении первая «Назад» показывает панели, вторая закрывает книгу.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(reader(tester).panelsVisible, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-area')), findsNothing, reason: 'закрыта книга — и полка: второго экрана нет');
      expect(find.byKey(const Key('shelf-title')), findsOneWidget);
      // После возврата книга снова открывается.
      await quickTap(tester, tester.getCenter(find.text('Капитанская дочка').first));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-area')), findsOneWidget);
    });

    testWidgets('прокрутка полки и касание после неё; долгое нажатие — меню, касание затемнения — меню закрыто, книга '
        'не открыта', (tester) async {
      await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await tester.dragFrom(const Offset(160, 500), const Offset(0, -260));
      await tester.pumpAndSettle();
      final row = find.text('Мёртвые души');
      expect(row.hitTestable(), findsOneWidget);
      await tester.longPress(row);
      await tester.pumpAndSettle();
      expect(find.text('Удалить книгу'), findsOneWidget);
      await tester.tapAt(const Offset(160, 60));
      await tester.pumpAndSettle();
      expect(find.text('Удалить книгу'), findsNothing);
      expect(find.byKey(const Key('page-area')), findsNothing);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-area')), findsOneWidget);
    });
  });

  group('голос', () {
    testWidgets('пробы подряд, выбор во время пробы, прокрутка до последнего голоса, уход во время пробы', (tester) async {
      final p = await pumpPrototype(tester);
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-voice')));
      await tester.pumpAndSettle();

      await quickTap(tester, tester.getCenter(find.byKey(const Key('probe-Achernar'))));
      await frames(tester, 300);
      expect(p.sampler.voice, 'Achernar');
      await quickTap(tester, tester.getCenter(find.byKey(const Key('probe-Autonoe'))));
      await frames(tester, 300);
      expect(p.sampler.voice, 'Autonoe', reason: 'новая проба заменяет прежнюю');
      expect(p.sampler.state, SampleState.loading);

      // Выбор другого голоса во время пробы: голос выбран, проба не оборвана.
      await quickTap(tester, tester.getCenter(find.text('Callirrhoe')));
      await frames(tester, 100);
      expect(p.settings.voice, 'Callirrhoe');
      expect(p.sampler.voice, 'Autonoe');

      // Повторное касание «Пробы» звучащего голоса останавливает её.
      await frames(tester, 900);
      expect(p.sampler.state, SampleState.playing);
      await quickTap(tester, tester.getCenter(find.byKey(const Key('probe-Autonoe'))));
      await frames(tester, 100);
      expect(p.sampler.voice, isNull);

      // Прокрутка пальцем до последнего голоса и его проба.
      final last = find.byKey(const Key('probe-Zubenelgenubi'));
      await tester.dragUntilVisible(last, find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(last);
      await frames(tester, 200);
      expect(p.sampler.voice, 'Zubenelgenubi');

      // Уход с экрана во время пробы останавливает её.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(p.sampler.voice, isNull);
      expect(p.sampler.state, SampleState.idle);
      expect(find.byKey(const Key('settings-voice')), findsOneWidget);
      expect(find.textContaining('Callirrhoe'), findsOneWidget, reason: 'настройки показывают выбранный голос');
    });
  });

  group('настройки: поле ключа (FR-P7)', () {
    testWidgets('«Слушать» без ключа → ключ введён в поле → системная «Назад»: ключ сохранён', (tester) async {
      final p = await pumpPrototype(tester);
      p.settings.apiKey = null;
      await openKapitanskaya(tester, p);
      await tapCenter(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('listen')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('key-field')), findsOneWidget);
      // Читатель вставил ключ в поле (долгое нажатие → «Вставить» системного меню или подсказка клавиатуры) и
      // вернулся в книгу. Отдельной кнопки «Готово» на экране нет — только действие клавиатуры.
      await tester.enterText(find.byKey(const Key('key-field')), 'AIzaSyD-typed-key-0000');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-area')), findsOneWidget, reason: 'предусловие: вернулись в книгу');
      expect(p.settings.hasApiKey, isTrue,
          reason: 'введённый ключ не должен молча пропадать: иначе «Слушать» снова ведёт в настройки без объяснения');
    });

    testWidgets('«Изменить» → очень длинное значение и действие клавиатуры «Готово»: ключ сохранён, поле закрыто, '
        'хвост — четыре знака', (tester) async {
      final p = await pumpPrototype(tester, size: phone320, textScale: 1.3);
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('key-change')));
      await tester.pumpAndSettle();
      final long = '${'A' * 600}wxyz';
      await tester.enterText(find.byKey(const Key('key-field')), long);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(p.settings.hasApiKey, isTrue);
      expect(p.settings.apiKeyTail, 'wxyz');
      expect(find.byKey(const Key('key-field')), findsNothing);
      expect(find.textContaining('wxyz'), findsOneWidget);
      expect(find.textContaining('AAAA'), findsNothing, reason: 'ключ на экране не показан');
    });
  });

  group('«Вид текста» (FR-R6, FR-R7)', () {
    testWidgets('быстрые нажатия размера туда и обратно, тема между ними: место чтения — тот же блок и смещение, '
        'страница та же', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(60, 300));
      final page0 = currentPage(tester);
      final first = ReadingPosition(page0.firstBlock, page0.firstOffset);
      await tapCenter(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Вид текста'));
      await tester.pumpAndSettle();
      final larger = tester.getCenter(find.byKey(const Key('font-larger')));
      final smaller = tester.getCenter(find.byKey(const Key('font-smaller')));
      for (var i = 0; i < 3; i++) {
        await quickTap(tester, larger);
        await frames(tester, 32);
        expect(currentPage(tester).contains(60, 300), isTrue, reason: 'крупнее, шаг ${i + 1}');
      }
      await quickTap(tester, tester.getCenter(find.byKey(const Key('theme-dark'))));
      await frames(tester, 32);
      expect(currentPage(tester).contains(60, 300), isTrue, reason: 'смена темы');
      for (var i = 0; i < 5; i++) {
        await quickTap(tester, smaller);
        await frames(tester, 32);
        expect(currentPage(tester).contains(60, 300), isTrue, reason: 'мельче, шаг ${i + 1}');
      }
      for (var i = 0; i < 2; i++) {
        await quickTap(tester, larger);
        await frames(tester, 32);
      }
      await tester.pumpAndSettle();
      expect(p.settings.fontStep, defaultFontStep);
      expect(p.settings.theme, ThemeChoice.dark);
      final page1 = currentPage(tester);
      expect(ReadingPosition(page1.firstBlock, page1.firstOffset), first,
          reason: 'вернулись к прежнему размеру — страница начинается там же');
      // Лист смахивается вниз; панели остаются, страница та же.
      final sheet = tester.getRect(find.byKey(const Key('appearance-sheet')));
      await swipe(tester, Offset(sheet.center.dx, sheet.top + 10), const Offset(0, 400), ms: 200);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('appearance-sheet')), findsNothing);
      expect(reader(tester).panelsVisible, isTrue);
      expect(ReadingPosition(currentPage(tester).firstBlock, currentPage(tester).firstOffset), first);
    });
  });

  group('поворот экрана (FR-R7, FR-R8)', () {
    testWidgets('поворот в альбомную и обратно: место чтения то же', (tester) async {
      final p = await pumpPrototype(tester);
      await openKapitanskaya(tester, p, at: const ReadingPosition(60, 300));
      final page0 = currentPage(tester);
      final first = ReadingPosition(page0.firstBlock, page0.firstOffset);
      tester.view.physicalSize = const Size(915, 412) * snapshotDpr;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(currentPage(tester).contains(60, 300), isTrue, reason: 'после поворота на экране то же место (FR-R7)');
      tester.view.physicalSize = phone412 * snapshotDpr;
      await tester.pumpAndSettle();
      final page1 = currentPage(tester);
      expect(ReadingPosition(page1.firstBlock, page1.firstOffset), first);
    });

    // Заменён по решению F проверки жестов: первая версия — только портретная ориентация. Был тест «альбомная
    // ориентация с вырезом сбоку: текст не заходит под вырез» — альбомной в первой версии нет (спека 001, «Не делаем»).
    testWidgets('альбомная не включается: приложение просит у системы только портретную, то же в манифесте',
        (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpPrototype(tester);
      final orientation = calls.where((c) => c.method == 'SystemChrome.setPreferredOrientations').toList();
      expect(orientation, isNotEmpty, reason: 'приложение закрепляет ориентацию при запуске');
      expect(orientation.last.arguments, ['DeviceOrientation.portraitUp']);
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:screenOrientation="portrait"'));
    });
  });
}
