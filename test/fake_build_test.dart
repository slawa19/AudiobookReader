import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/app/assembly.dart';
import 'package:audiobook_reader/screens/l10n/app_localizations.dart';
import 'package:audiobook_reader/screens/services.dart';
import 'package:audiobook_reader/screens/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';
import 'support/app_harness.dart';

void main() {
  test('признак сборки выключен по умолчанию, включается FAKE_TTS=true', () {
    expect(useFakeTts, const String.fromEnvironment('FAKE_TTS') == 'true');
  });

  testWidgets('корень Android передаёт признак сборки в настройки', (tester) async {
    final h = AppHarness(tester);
    await h.start();
    expect(h.app.services.fakeTts, useFakeTts);
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Подставной голос'), useFakeTts ? findsOneWidget : findsNothing);
  });

  for (final fakeTts in [false, true]) {
    for (final (locale, label) in [
      ('ru', 'Подставной голос'),
      ('en', 'Fake voice'),
      ('pl', 'Głos testowy'),
      ('de', 'Teststimme'),
    ]) {
      testWidgets('$locale: строка подставного голоса только при fakeTts=$fakeTts', (tester) async {
        final prototype = await pumpPrototype(tester, size: phone320, textScale: 2, locale: locale);
        final original = prototype.services;
        final services = AppServices(
          library: original.library,
          settings: original.settings,
          narration: original.narration,
          downloads: original.downloads,
          sampler: original.sampler,
          audio: original.audio,
          tariffs: original.tariffs,
          addBook: original.addBook,
          openUrl: original.openUrl,
          spentByMonth: original.spentByMonth,
          themePreviews: original.themePreviews,
          fakeTts: fakeTts,
        );
        await tester.pumpWidget(MaterialApp(
          locale: Locale(locale),
          supportedLocales: supportedLocales,
          localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          home: SettingsScreen(services: services),
        ));
        await tester.pumpAndSettle();
        expect(find.text(label), fakeTts ? findsOneWidget : findsNothing);
        expect(find.byKey(const Key('fake-voice')), fakeTts ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
