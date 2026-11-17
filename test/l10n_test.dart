import 'dart:convert';
import 'dart:io';

import 'package:audiobook_reader/app/app.dart';
import 'package:audiobook_reader/screens/l10n/app_localizations.dart';
import 'package:audiobook_reader/tts/book_language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

Map<String, Object?> arb(String lang) =>
    jsonDecode(File('lib/screens/l10n/app_$lang.arb').readAsStringSync()) as Map<String, Object?>;

Set<String> keys(Map<String, Object?> a) => a.keys.where((k) => !k.startsWith('@')).toSet();

/// Placeholder names in an ICU string: {name}, {count, plural, …}.
Set<String> placeholders(String s) => RegExp(r'\{(\w+)[,}]').allMatches(s).map((m) => m.group(1)!).toSet();

void main() {
  group('ARB', () {
    final ru = arb('ru');
    // The whole Cyrillic block: Russian and Ukrainian letters alike (І, Ї, Є, Ґ lie outside А–я).
    final cyrillic = RegExp('[\u0400-\u04FF]');
    for (final lang in ['en', 'pl', 'de', 'uk']) {
      test('$lang: all keys are present, no extra ones, same placeholders', () {
        final other = arb(lang);
        expect(keys(other), keys(ru));
        for (final k in keys(ru)) {
          expect(placeholders(other[k]! as String), placeholders(ru[k]! as String), reason: '$lang: $k');
          expect((other[k]! as String).trim(), isNotEmpty, reason: '$lang: $k');
        }
      });

      if (lang != 'uk') {
        test('$lang: no Cyrillic (except the language names «Русский» and «Українська»)', () {
          final other = arb(lang);
          for (final k in keys(other).where((k) => k != 'langRu' && k != 'langUk')) {
            expect(cyrillic.hasMatch(other[k]! as String), isFalse, reason: '$lang: $k');
          }
        });
      }
    }

    test('the Cyrillic check is not vacuous: Russian and Ukrainian-only letters are caught, Latin ones are not', () {
      expect(cyrillic.hasMatch(ru['emptyBody']! as String), isTrue);
      for (final letter in ['ї', 'Ї', 'і', 'І', 'є', 'Є', 'ґ', 'Ґ']) {
        expect(cyrillic.hasMatch('Bücher $letter'), isTrue, reason: letter);
      }
      expect(cyrillic.hasMatch(arb('uk')['langUk']! as String), isTrue);
      // The other side: Latin text with diacritics (Polish, German) passes.
      expect(cyrillic.hasMatch('Zażółć gęślą jaźń, Größe, Bücher'), isFalse);
      expect(cyrillic.hasMatch(arb('en')['listen']! as String), isFalse);
    });

    test('uk: no letters that the Ukrainian alphabet lacks (ы, э, ъ, ё) — not Russian text disguised as Ukrainian', () {
      final uk = arb('uk');
      for (final k in keys(uk).where((k) => k != 'langRu')) {
        expect(RegExp('[ыэъёЫЭЪЁ]').hasMatch(uk[k]! as String), isFalse, reason: 'uk: $k');
      }
      // The other side: Russian text does not pass this check.
      expect(RegExp('[ыэъёЫЭЪЁ]').hasMatch(ru['emptyBody']! as String), isTrue);
    });

    test('the completeness check is not vacuous: a missing key would be detected', () {
      final cut = Map.of(arb('en'))..remove('listen');
      expect(keys(cut), isNot(keys(arb('ru'))));
    });
  });

  group('plural forms and numbers', () {
    test('Russian, Ukrainian and Polish have three to four forms, English and German have two', () async {
      final uk = await AppLocalizations.delegate.load(const Locale('uk'));
      final ru = await AppLocalizations.delegate.load(const Locale('ru'));
      final pl = await AppLocalizations.delegate.load(const Locale('pl'));
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final de = await AppLocalizations.delegate.load(const Locale('de'));
      expect(ru.sleepMinutes(1), '1 минута');
      expect(ru.sleepMinutes(2), '2 минуты');
      expect(ru.sleepMinutes(15), '15 минут');
      expect(ru.sleepMinutes(21), '21 минута');
      expect(uk.sleepMinutes(1), '1 хвилина');
      expect(uk.sleepMinutes(2), '2 хвилини');
      expect(uk.sleepMinutes(5), '5 хвилин');
      expect(uk.sleepMinutes(11), '11 хвилин');
      expect(uk.sleepMinutes(15), '15 хвилин');
      expect(uk.sleepMinutes(21), '21 хвилина');
      expect(uk.sleepMinutes(24), '24 хвилини');
      expect(pl.sleepMinutes(2), '2 minuty');
      expect(pl.sleepMinutes(15), '15 minut');
      expect(pl.sleepMinutes(22), '22 minuty');
      expect(en.sleepMinutes(1), '1 minute');
      expect(en.sleepMinutes(15), '15 minutes');
      expect(de.sleepMinutes(30), '30 Minuten');
    });

    test('the chapter mark agrees with the word for a chapter: «глава» is feminine, «розділ» is not', () async {
      final ru = await AppLocalizations.delegate.load(const Locale('ru'));
      final uk = await AppLocalizations.delegate.load(const Locale('uk'));
      expect(ru.voiced, 'озвучена');
      expect(uk.voiced, 'озвучено');
      expect(uk.endOfChapterShort, 'розділ');
    });

    test('money, percentages and speed follow the locale', () async {
      final ru = await AppLocalizations.delegate.load(const Locale('ru'));
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final uk = await AppLocalizations.delegate.load(const Locale('uk'));
      expect(uk.money(4.12), contains('4,12'));
      expect(uk.money(4.12), contains(r'$'));
      expect(uk.speedValue(1.25), '1,25×');
      expect(ru.money(4.12), contains('4,12'));
      expect(ru.money(4.12), contains(r'$'));
      expect(en.money(4.12), r'$4.12');
      expect(ru.speedValue(1.25), '1,25×');
      expect(en.speedValue(1.25), '1.25×');
      expect(ru.percent(0.34), contains('34'));
      expect(en.percent(0.34), '34%');
    });
  });

  group('interface language', () {
    testWidgets('by default the phone language; if it is not one of the five, English', (tester) async {
      await pumpPrototype(tester, locale: 'de');
      expect(find.text('Bücher'), findsOneWidget);
    });

    testWidgets('a Ukrainian phone gets the Ukrainian interface, Material labels too', (tester) async {
      await pumpPrototype(tester, locale: 'uk');
      expect(find.byTooltip('Налаштування'), findsWidgets);
      final context = tester.element(find.byTooltip('Налаштування').first);
      expect(MaterialLocalizations.of(context).backButtonTooltip, 'Назад');
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets('a phone language outside the five gives English', (tester) async {
      await pumpPrototype(tester, locale: 'fr');
      expect(find.text('Books'), findsOneWidget);
    });

    testWidgets('a language chosen in settings applies at once, system Material labels too', (tester) async {
      final p = await pumpPrototype(tester);
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('language-pl')));
      await tester.pumpAndSettle();
      expect(p.settings.language, 'pl');
      expect(find.text('Ustawienia'), findsWidgets);
      expect(find.text('Język'), findsOneWidget);
      // The Material back button is labelled in Polish: the material_ui delegates are wired in.
      final context = tester.element(find.text('Język'));
      expect(MaterialLocalizations.of(context).backButtonTooltip, 'Wstecz');
      await tester.tap(find.byKey(const Key('settings-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('language-system')));
      await tester.pumpAndSettle();
      expect(p.settings.language, isNull);
      expect(find.text('Настройки'), findsWidgets);
    });

    test('language resolution: a language from the list is used, otherwise English', () {
      expect(resolveLocale([const Locale('pl', 'PL')], supportedLocales), const Locale('pl'));
      expect(resolveLocale([const Locale('fr'), const Locale('de')], supportedLocales), const Locale('de'));
      expect(resolveLocale([const Locale('uk', 'UA')], supportedLocales), const Locale('uk'));
      expect(resolveLocale([const Locale('fr')], supportedLocales), const Locale('en'));
    });
  });

  group('the probe phrase and style follow the book language', () {
    test('five languages and English for the rest', () {
      for (final lang in ['ru', 'en', 'pl', 'de', 'uk']) {
        expect(samplePhraseFor(lang), samplePhrases[lang]);
        expect(readingStyleFor(lang), readingStyles[lang]);
      }
      expect(samplePhraseFor('fr'), samplePhrases['en']);
      expect(readingStyleFor('cs-CZ'), readingStyles['en']);
      expect(readingStyleFor('uk-UA'), readingStyles['uk']);
      expect(samplePhraseFor('pl-PL'), samplePhrases['pl']);
    });

    test('the style does not name the reader gender', () {
      for (final w in ['рассказчица', 'рассказчик', 'чтица', 'narratorka', 'Erzählerin', 'Erzähler', 'оповідач', 'оповідачка', 'читачка']) {
        for (final s in readingStyles.values) {
          expect(s.contains(w), isFalse, reason: w);
        }
      }
    });
  });
}
