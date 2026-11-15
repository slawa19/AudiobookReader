import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final filters = RegExp(r'<intent-filter>[\s\S]*?</intent-filter>')
      .allMatches(manifest)
      .map((match) => match.group(0)!)
      .toList();

  Set<String> values(String filter, String attribute) =>
      RegExp('android:$attribute="([^"]+)"').allMatches(filter).map((match) => match.group(1)!).toSet();

  const bookTypes = {
    'application/epub+zip',
    'application/x-fictionbook+xml',
    'application/x-fictionbook',
    'application/x-fictionbook+zip',
    'application/fb2',
    'application/fb2+zip',
  };
  const genericTypes = {'application/zip', 'application/x-zip-compressed', 'application/xml', 'text/xml'};

  test('Android: точные разрешения воспроизведения; незашифрованный HTTP запрещён', () {
    final permissions = RegExp(r'<uses-permission(?:-sdk-\d+)?\b[^>]*>')
        .allMatches(manifest)
        .map((match) => values(match.group(0)!, 'name').single)
        .toList();
    expect(
      permissions,
      unorderedEquals([
        'android.permission.INTERNET',
        'android.permission.WAKE_LOCK',
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
      ]),
    );
    final application = RegExp(r'<application\b[^>]*>').firstMatch(manifest)!.group(0)!;
    expect(values(application, 'usesCleartextTraffic'), {'false'});
    // Без отдельного networkSecurityConfig нет исключений, разрешающих HTTP по доменам.
    expect(values(application, 'networkSecurityConfig'), isEmpty);
    final services = RegExp(r'<service\b[^>]*>').allMatches(manifest).toList();
    expect(services, hasLength(1));
    expect(values(services.single.group(0)!, 'name'), {'com.ryanheise.audioservice.AudioService'});
    expect(values(services.single.group(0)!, 'foregroundServiceType'), {'mediaPlayback'});
    expect(manifest, contains('android.intent.action.MEDIA_BUTTON'));
  });

  test('Android: непрозрачный URI MediaStore с octet-stream принимается, архивы и XML требуют суффикс', () {
    final opaque = Uri.parse('content://media/external/file/20334');
    bool accepts(Uri uri, String type) => filters.any((filter) {
      if (!filter.contains('android.intent.action.VIEW')) return false;
      final suffixes = values(filter, 'pathSuffix');
      return values(filter, 'scheme').contains(uri.scheme) &&
          values(filter, 'mimeType').contains(type) &&
          (suffixes.isEmpty || suffixes.any(uri.path.endsWith));
    });
    expect(accepts(opaque, 'application/octet-stream'), isTrue);
    expect(accepts(opaque, 'application/x-fictionbook+xml'), isTrue);
    for (final type in genericTypes) {
      expect(accepts(opaque, type), isFalse, reason: type);
      expect(accepts(Uri.parse('content://files/book.fb2'), type), isTrue, reason: type);
      expect(accepts(Uri.parse('content://files/data.xml'), type), isFalse, reason: type);
    }
    expect(accepts(Uri.parse('file:///book.fb2'), 'application/octet-stream'), isFalse);
  });

  test('Android: резервное копирование выключено', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
  });

  test('Android: облако и перенос исключают все хранилища', () {
    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final content = RegExp('<$section>([\\s\\S]*?)</$section>').firstMatch(rules)?.group(1);
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
        expect(content, contains('<exclude domain="$domain" path="." />'), reason: '$section: $domain');
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
    expect(values(typed, 'mimeType'), {...bookTypes, 'application/octet-stream'});
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

  test('Android: SEND принимает книжные MIME и octet-stream, но не любые архивы и XML', () {
    final send = filters.singleWhere((filter) => filter.contains('android.intent.action.SEND'));
    expect(values(send, 'name'), contains('android.intent.category.DEFAULT'));
    expect(values(send, 'mimeType'), {...bookTypes, 'application/octet-stream'});
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
