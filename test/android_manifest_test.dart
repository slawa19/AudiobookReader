import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();
  final filters = RegExp(r'<intent-filter>[\s\S]*?</intent-filter>')
      .allMatches(manifest)
      .map((match) => match.group(0)!)
      .toList();

  Set<String> values(String filter, String attribute) => RegExp('android:$attribute="([^"]+)"')
      .allMatches(filter)
      .map((match) => match.group(1)!)
      .toSet();

  const bookTypes = {
    'application/epub+zip',
    'application/x-fictionbook+xml',
    'application/x-fictionbook',
    'application/x-fictionbook+zip',
    'application/fb2',
    'application/fb2+zip',
  };
  const genericTypes = {
    'application/zip',
    'application/x-zip-compressed',
    'application/octet-stream',
    'application/xml',
    'text/xml',
  };

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

  test('Android: VIEW принимает книжный MIME без ограничения пути content-URI', () {
    final view = filters.where((filter) => filter.contains('android.intent.action.VIEW'));
    expect(view, hasLength(2));
    final typed = view.singleWhere((filter) => !filter.contains('android:pathSuffix'));
    expect(values(typed, 'mimeType'), bookTypes);
    expect(values(typed, 'scheme'), {'content'});
    expect(values(typed, 'name'), contains('android.intent.category.DEFAULT'));
    expect(typed, isNot(contains('android:host')));
  });

  test('Android: общие MIME в VIEW ограничены расширениями книг, TXT не принимается', () {
    final generic = filters.singleWhere((filter) => filter.contains('android:pathSuffix'));
    expect(generic, contains('android.intent.action.VIEW'));
    expect(values(generic, 'name'), contains('android.intent.category.DEFAULT'));
    expect(values(generic, 'mimeType'), genericTypes);
    expect(values(generic, 'scheme'), {'content'});
    expect(values(generic, 'host'), {'*'});
    expect(values(generic, 'pathSuffix'), {'.fb2', '.fb2.zip', '.epub'});
    for (final filter in filters) {
      expect(values(filter, 'mimeType'), isNot(contains('text/plain')));
      expect(values(filter, 'mimeType').any((type) => type.contains('*')), isFalse);
      expect(filter, isNot(contains('.txt')));
    }
  });

  test('Android: SEND принимает книжные MIME, не перехватывает любые архивы и двоичные файлы', () {
    final send = filters.singleWhere((filter) => filter.contains('android.intent.action.SEND'));
    expect(values(send, 'name'), contains('android.intent.category.DEFAULT'));
    expect(values(send, 'mimeType'), bookTypes);
    expect(values(send, 'mimeType').intersection(genericTypes), isEmpty);
    expect(send, isNot(contains('android:scheme')));
    expect(send, isNot(contains('android:path')));
  });

  test('Android: входящие URI не становятся маршрутами Flutter; разрешений памяти нет', () {
    expect(manifest, contains('android:launchMode="singleTask"'));
    expect(manifest, isNot(contains('android:taskAffinity=""')));
    expect(manifest, contains('android:name="flutter_deeplinking_enabled" android:value="false"'));
    for (final permission in ['READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE', 'MANAGE_EXTERNAL_STORAGE']) {
      expect(manifest, isNot(contains(permission)));
    }
  });
}
