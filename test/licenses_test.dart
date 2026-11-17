import 'dart:convert';
import 'dart:io';

import 'package:audiobook_reader/screens/licenses.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

const demoTexts = 'Demo texts';

/// The separator of entries in a NOTICES file (`licenseSeparator` of the flutter tool's `license_collector.dart`).
final separator = '\n${'-' * 80}\n';

/// The entries of the repository's `NOTICES` file read by the flutter tool's rule for a package's NOTICES file
/// (`LicenseCollector.obtainLicenses`): only when the file has more than one entry, the lines before the first blank
/// line of each entry are package names; a single entry would be listed under the Dart package name.
Map<String, String> noticesEntries() {
  final raw = File('NOTICES').readAsStringSync().split(separator);
  expect(raw.length, greaterThan(1), reason: 'with one entry the tool ignores the names in it');
  final out = <String, String>{};
  for (final entry in raw) {
    final split = entry.indexOf('\n\n');
    expect(split, greaterThan(0), reason: 'every entry starts with its names and a blank line');
    for (final name in entry.substring(0, split).split('\n')) {
      expect(out.containsKey(name), isFalse, reason: name);
      out[name] = entry.substring(split + 2);
    }
  }
  return out;
}

/// The license entries that the license page shows, by package. The source is the NOTICES that the flutter tool
/// built for the test bundle with the same collector as for the APK (`build/unit_test_assets/NOTICES.Z`); the test
/// binding does not register it, so it is read here and split by the rule of `ServicesBinding._parseLicenses`.
Future<Map<String, List<String>>> pageEntries() async {
  final bytes = await rootBundle.load('NOTICES.Z');
  final notices = utf8.decode(gzip.decode(bytes.buffer.asUint8List()));
  final out = <String, List<String>>{};
  for (final entry in notices.split(separator)) {
    final split = entry.indexOf('\n\n');
    if (split < 0) continue;
    for (final package in entry.substring(0, split).split('\n')) {
      (out[package] ??= []).add(entry.substring(split + 2));
    }
  }
  return out;
}

String dartPackageName() =>
    RegExp(r'^name:\s*(\S+)\s*$', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the NOTICES file at the repository root', () {
    test('names the app, the two fonts and the demo texts, and nothing under the Dart package name', () {
      final entries = noticesEntries();
      expect(entries.keys.toSet(), {appName, 'Merriweather', 'Roboto', demoTexts});
      expect(dartPackageName(), 'audiobook_reader');
      expect(entries.containsKey(dartPackageName()), isFalse);
    });

    test('the app entry: the holder, the license, the repository, then the whole LICENSE file', () {
      final text = noticesEntries()[appName]!;
      final license = File('LICENSE').readAsStringSync();
      expect(text, endsWith(license));
      final preamble = text.substring(0, text.length - license.length);
      expect(preamble, contains('© 2026 Slawa Gorobets'));
      expect(preamble, contains('GPL-3.0-or-later'));
      expect(preamble, contains('Source code: $repositoryUrl'));
      expect(license, contains('GNU GENERAL PUBLIC LICENSE'));
      expect(license, contains('Version 3, 29 June 2007'));
    });

    test('the font and demo-text entries are their files, byte for byte', () {
      final entries = noticesEntries();
      expect(entries['Merriweather'], File('assets/fonts/Merriweather-OFL.txt').readAsStringSync());
      expect(entries['Roboto'], File('assets/fonts/Roboto-OFL.txt').readAsStringSync());
      expect(entries[demoTexts], File('assets/demo/SOURCES.txt').readAsStringSync());
      for (final font in ['Merriweather', 'Roboto']) {
        expect(entries[font], contains('SIL OPEN FONT LICENSE Version 1.1'), reason: font);
      }
      // The CC BY-SA attribution belongs to the demo texts alone.
      expect(entries[demoTexts], contains('Wikisource contributors, licensed under CC BY-SA 4.0'));
      for (final other in [appName, 'Merriweather', 'Roboto']) {
        expect(entries[other], isNot(contains('CC BY-SA')), reason: other);
      }
    });
  });

  test('the license data the page shows: the app once under its name, never under the Dart package name', () async {
    final entries = await pageEntries();
    // The other side: the data really is the tool's NOTICES with the dependencies, not an empty registry.
    expect(entries.keys, containsAll(['flutter', 'audio_service', 'just_audio']));
    expect(entries.containsKey(dartPackageName()), isFalse);
    expect(entries[appName], hasLength(1));
    expect(entries[appName]!.single, contains('GPL-3.0-or-later'));
    expect(entries[appName]!.single, contains(repositoryUrl));
    expect(entries[appName]!.single, contains('GNU GENERAL PUBLIC LICENSE'));
    for (final name in ['Merriweather', 'Roboto', demoTexts]) {
      expect(entries[name], hasLength(1), reason: name);
    }
  });

  test('appVersion equals the version in pubspec.yaml (without the build number)', () {
    final match = RegExp(r'^version:\s*(\S+?)(?:\+\d+)?\s*$', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(match, isNotNull);
    expect(appVersion, match!.group(1));
  });

  testWidgets('the last settings row opens the standard license page with the app name and version', (tester) async {
    await pumpPrototype(tester);
    await tester.tap(find.byTooltip('Настройки'));
    await settle(tester);
    expect(find.byType(LicensePage), findsNothing);
    final row = find.byKey(const Key('settings-licenses'));
    await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.descendant(of: row, matching: find.text('Лицензии открытого ПО')), findsOneWidget);
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text(appName), findsWidgets);
    expect(find.text(appVersion), findsOneWidget);
  });

  group('the row at 320 dp with the text scale 1.3', () {
    const labels = {
      'ru': 'Лицензии открытого ПО',
      'en': 'Open-source licenses',
      'pl': 'Licencje open source',
      'de': 'Open-Source-Lizenzen',
      'uk': 'Ліцензії відкритого ПЗ',
    };
    for (final lang in labels.keys) {
      testWidgets('$lang: the label is shown whole and nothing overflows', (tester) async {
        await pumpPrototype(tester, size: phone320, textScale: 1.3, locale: lang);
        await tester.tap(find.byIcon(Icons.settings_outlined));
        await settle(tester);
        final row = find.byKey(const Key('settings-licenses'));
        await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        expect(find.descendant(of: row, matching: find.text(labels[lang]!)), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
