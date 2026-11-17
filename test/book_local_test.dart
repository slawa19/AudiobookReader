import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/book_samples.dart';

void main() {
  final dir = Directory('test/local_books');
  test('FR-B7: invariants on every local book of the owner', () {
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) => RegExp(
            r'\.(fb2|zip|epub)$',
            caseSensitive: false,
          ).hasMatch(f.path),
        )
        .toList();
    expect(files, isNotEmpty, reason: 'The folder exists but has no books');
    for (final file in files) {
      checked(file.readAsBytesSync());
    }
  }, skip: !dir.existsSync() ? 'test/local_books/ is missing' : false);
}
