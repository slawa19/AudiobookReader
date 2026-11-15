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
    'text/plain',
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
    expect(accepts(opaque, 'text/plain'), isTrue);
    expect(accepts(Uri.parse('content://files/book.txt'), 'text/plain'), isTrue);
    expect(accepts(Uri.parse('content://files/book.txt'), 'application/octet-stream'), isTrue);
    expect(accepts(opaque, 'image/png'), isFalse);
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

  test('Android: общие MIME в VIEW ограничены расширениями FB2/EPUB, TXT имеет свой MIME', () {
    final generic = filters.singleWhere((filter) => filter.contains('android:pathSuffix'));
    expect(generic, contains('android.intent.action.VIEW'));
    expect(values(generic, 'name'), contains('android.intent.category.DEFAULT'));
    expect(values(generic, 'mimeType'), genericTypes);
    expect(values(generic, 'scheme'), {'content'});
    expect(values(generic, 'host'), {'*'});
    expect(values(generic, 'pathSuffix'), {'.fb2', '.fb2.zip', '.epub'});
    for (final filter in filters) {
      expect(values(filter, 'mimeType').any((type) => type.contains('*')), isFalse);
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

  test('Android: выбор файла включает TXT и octet-stream; SEND не читает EXTRA_TEXT', () {
    final channel = File(
      'android/app/src/main/kotlin/io/github/slawa19/audiobook_reader/IncomingFilesChannel.kt',
    ).readAsStringSync();
    final types = RegExp(r'putExtra\(Intent.EXTRA_MIME_TYPES, arrayOf\(([\s\S]*?)\)\)')
        .firstMatch(channel)!
        .group(1)!;
    expect(RegExp(r'"([^"]+)"').allMatches(types).map((m) => m.group(1)).toSet(), {
      ...bookTypes,
      ...genericTypes,
      'application/octet-stream',
    });
    expect(channel, contains('Intent.ACTION_VIEW -> intent.data'));
    expect(channel, contains('Intent.ACTION_SEND -> streamUri(intent)'));
    expect(channel, contains('Intent.EXTRA_STREAM'));
    expect(channel, isNot(contains('Intent.EXTRA_TEXT')));
    expect(channel, contains('if (uri == null || uri.scheme != "content")'));
  });

  test('Android: входящие URI не становятся маршрутами Flutter; разрешений памяти нет', () {
    expect(manifest, contains('android:launchMode="singleTask"'));
    expect(manifest, isNot(contains('android:taskAffinity=""')));
    expect(manifest, contains('android:name="flutter_deeplinking_enabled" android:value="false"'));
    for (final permission in ['READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE', 'MANAGE_EXTERNAL_STORAGE']) {
      expect(manifest, isNot(contains(permission)));
    }
  });

  test('Android: SEND без файла и VIEW без data молча завершаются до copy и emit', () {
    final channel = File(
      'android/app/src/main/kotlin/io/github/slawa19/audiobook_reader/IncomingFilesChannel.kt',
    ).readAsStringSync();
    final accept = channel.split('fun accept(intent: Intent) {')[1].split('private fun streamUri')[0];
    expect(accept, contains('Intent.ACTION_VIEW -> intent.data'));
    expect(accept, contains('Intent.ACTION_SEND -> streamUri(intent)'));
    expect(accept, contains('intent.clipData'));
    // Обе ветви проходят общую проверку: пустой URI не попадает в рабочую очередь.
    expect(accept, matches(RegExp(r'else -> return\s*\}\s*\?: return\s*copy\(uri, ::emit\)')));
    expect(accept, isNot(contains('Result.failure')));
    expect(accept, isNot(contains('sink')));
  });
}
