import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Перед каждым файлом тестов загружает все шрифты из FontManifest (Merriweather, Roboto, значки Material):
/// иначе в снимках экранов текст рисуется прямоугольниками тестового шрифта.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<Object?>;
  for (final f in manifest) {
    final family = (f! as Map<String, Object?>)['family']! as String;
    final loader = FontLoader(family.startsWith('packages/') ? family.split('/').last : family);
    for (final font in (f as Map<String, Object?>)['fonts']! as List<Object?>) {
      loader.addFont(rootBundle.load((font! as Map<String, Object?>)['asset']! as String));
    }
    await loader.load();
  }
  await testMain();
}
