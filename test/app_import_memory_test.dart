import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('импорт передаёт путь и не читает исходник в главном изоляте приложения', () {
    final application = File('lib/app/native_application.dart').readAsStringSync();
    expect(application, isNot(contains('file.readAsBytes()')));
    expect(application, contains('library.addFile('));
    final library = File('lib/library/file_library.dart').readAsStringSync();
    expect(library, isNot(contains('List<int>.of(bytes)')));
  });
}
