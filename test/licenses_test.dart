import 'dart:io';

import 'package:audiobook_reader/screens/licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

/// Packages of the entries that the registry yields, with the text of each package's entries.
Future<Map<String, String>> collect() async {
  final out = <String, StringBuffer>{};
  await for (final entry in LicenseRegistry.licenses) {
    for (final package in entry.packages) {
      (out[package] ??= StringBuffer()).writeln(entry.paragraphs.map((p) => p.text).join('\n'));
    }
  }
  return {for (final e in out.entries) e.key: e.value.toString()};
}

void main() {
  group('registry', () {
    setUp(() {
      LicenseRegistry.reset();
      registerLicenses();
    });
    tearDown(LicenseRegistry.reset);

    test('yields the project, Merriweather and Roboto, and claims nothing else', () async {
      final packages = await collect();
      expect(packages.keys.toSet(), {appName, 'Merriweather', 'Roboto'});
      // The other side: a package name that is not ours is not claimed.
      expect(packages.containsKey('flutter'), isFalse);
      expect(packages.containsKey('Open Sans'), isFalse);
    });

    test('the project entry names the license, the holder and the repository; the full GPL text follows', () async {
      final text = (await collect())[appName]!;
      expect(text, contains('GPL-3.0-or-later'));
      expect(text, contains('Slawa Gorobets'));
      expect(text, contains(repositoryUrl));
      expect(text, contains('GNU GENERAL PUBLIC LICENSE'));
      expect(text, contains('Version 3, 29 June 2007'));
    });

    test('the font entries carry their own SIL Open Font License texts', () async {
      final packages = await collect();
      for (final font in ['Merriweather', 'Roboto']) {
        expect(packages[font], contains('SIL OPEN FONT LICENSE Version 1.1'), reason: font);
        expect(packages[font], isNot(contains('GNU GENERAL PUBLIC LICENSE')), reason: font);
      }
      expect(packages['Merriweather'], contains('Merriweather'));
      expect(packages['Roboto'], contains('Roboto'));
    });
  });

  test('the registered files are in pubspec.yaml assets', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final asset in [projectLicenseAsset, merriweatherLicenseAsset, robotoLicenseAsset]) {
      expect(pubspec, contains('- $asset\n'), reason: asset);
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
  });

  test('appVersion equals the version in pubspec.yaml (without the build number)', () {
    final match = RegExp(r'^version:\s*(\S+?)(?:\+\d+)?\s*$', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(match, isNotNull);
    expect(appVersion, match!.group(1));
  });

  testWidgets('the last settings row opens the standard license page with the app name and version', (tester) async {
    LicenseRegistry.reset();
    registerLicenses();
    addTearDown(LicenseRegistry.reset);
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
    // The page lists the packages from the registry: ours are there.
    for (var i = 0; i < 50 && find.text('Roboto').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Merriweather'), findsOneWidget);
    expect(find.text('Roboto'), findsOneWidget);
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
