// Пути пользователя «Скачать главу» (FR-D2, А§6.7) и пометка «озвучена».

import 'package:audiobook_reader/library/library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/flows.dart';
import 'support/harness.dart';

Future<void> openToc(WidgetTester tester) async {
  await tapCenter(tester);
  await tester.tap(find.byTooltip('Оглавление'));
  await tester.pumpAndSettle();
}

String estimateText(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('download-estimate'))).data!;

void main() {
  testWidgets('глава озвучена → сменил голос книги → оглавление: глава больше не «озвучена», есть оценка',
      (tester) async {
    // FR-D2: «озвучена» — по правилу готовности А§6.1 для ДЕЙСТВУЮЩЕГО профиля голоса. Звук главы другим голосом
    // для нового голоса не годится: при прослушивании он будет синтезироваться и оплачиваться заново.
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p, at: const ReadingPosition(3, 0)); // глава I — озвучена в демо-данных
    await openToc(tester);
    expect(find.byKey(const Key('voiced-mark')), findsOneWidget, reason: 'предусловие: глава I озвучена');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('voice-chip-idle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voice-Kore')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(p.library.bookVoice('kapitanskaya'), 'Kore');

    await tester.tap(find.byTooltip('Оглавление'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voiced-mark')), findsNothing, reason: 'для голоса Kore глава не озвучена');
    expect(find.byKey(const Key('download-estimate')), findsOneWidget);
  });

  testWidgets('«Скачать главу» → половина готова → «Остановить»: оценка — остаток, а не вся глава', (tester) async {
    // FR-D2: «после ручной остановки — снова предложение скачать с оценкой остатка»; А§6.7: оценка — по
    // отсутствующим отпечаткам главы.
    final p = await pumpPrototype(tester);
    await openKapitanskaya(tester, p); // глава II, не озвучена
    await openToc(tester);
    final full = estimateText(tester);
    await tester.tap(find.byKey(const Key('download-start')));
    await advance(tester, const Duration(seconds: 20));
    expect(p.downloads.task!.fraction, greaterThan(0.4), reason: 'предусловие: больше трети готово');
    await tester.tap(find.byKey(const Key('download-stop')));
    await tester.pumpAndSettle();
    expect(estimateText(tester), isNot(full), reason: 'оценка после остановки — остаток, а не прежняя цена главы');
  });
}
