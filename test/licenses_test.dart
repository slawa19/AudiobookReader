import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const appName = 'Book AudioReader';
const repositoryUrl = 'https://github.com/slawa19/BookAudioReader';
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

/// The license entries bundled into the app, by package. The source is the NOTICES that the flutter tool
/// built for the test bundle with the same collector as for the APK (`build/unit_test_assets/NOTICES.Z`); the test
/// binding does not register it, so it is read here and split by the rule of `ServicesBinding._parseLicenses`.
Future<Map<String, List<String>>> bundledEntries() async {
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

  test('the notices bundled into the app: the app once under its name, never under the Dart package name', () async {
    final entries = await bundledEntries();
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

  test('the app has no license page: the notices ship in the APK and with the release (owner, 2026-11-17)', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    // The other side: the scan really reads the app's code, so an empty or misplaced scan cannot pass.
    expect(sources.any((f) => f.readAsStringSync().contains('class SettingsScreen')), isTrue);
    for (final file in sources) {
      final text = file.readAsStringSync();
      expect(text, isNot(contains('showLicensePage')), reason: file.path);
      expect(text, isNot(contains('LicensePage')), reason: file.path);
      expect(text, isNot(contains('AboutListTile')), reason: file.path);
    }
  });
}
