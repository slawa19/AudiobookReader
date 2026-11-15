import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  test('Android: резервное копирование выключено', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
  });

  test('Android: облако и перенос исключают все хранилища', () {
    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml')
        .readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final content = RegExp('<$section>([\\s\\S]*?)</$section>')
          .firstMatch(rules)
          ?.group(1);
      expect(content, isNotNull, reason: section);
      for (final domain in [
        'root',
        'file',
        'database',
        'sharedpref',
        'external',
        'device_root',
        'device_file',
        'device_database',
        'device_sharedpref',
      ]) {
        expect(
          content,
          contains('<exclude domain="$domain" path="." />'),
          reason: '$section: $domain',
        );
      }
      expect(content, isNot(contains('<include')));
    }
  });

  test('Android: только портретная ориентация', () {
    expect(manifest, contains('android:screenOrientation="portrait"'));
  });
}
