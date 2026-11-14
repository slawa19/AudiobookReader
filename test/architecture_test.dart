import 'dart:io';
import 'dart:math' as math;

import 'package:audiobook_reader/app/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Разрешённые прямые импорты между модулями — ARCHITECTURE.md, раздел 2 (FR-E5).
const allowed = <String, Set<String>>{
  'app': {'screens', 'reader', 'playback', 'library', 'tts', 'audio', 'book', 'platform'},
  'screens': {'reader', 'playback', 'library', 'audio', 'tts', 'book'},
  'reader': {'book'},
  'playback': {'tts', 'audio', 'library', 'book'},
  'library': {'book'},
  'tts': {'book'},
  'platform': {'audio', 'library'},
  'audio': {},
  'book': {},
};

final _import = RegExp(r'''^import\s+'([^']+)';''', multiLine: true);

/// Модули, которые импортирует файл [file] модуля [module].
Set<String> importedModules(File file, String module) {
  final out = <String>{};
  for (final m in _import.allMatches(file.readAsStringSync())) {
    final uri = m.group(1)!;
    String? target;
    if (uri.startsWith('package:audiobook_reader/')) {
      target = uri.substring('package:audiobook_reader/'.length).split('/').first;
    } else if (!uri.contains(':')) {
      final resolved = File.fromUri(file.uri.resolve(uri)).absolute.path.replaceAll('\\', '/');
      final i = resolved.indexOf('/lib/');
      if (i >= 0) target = resolved.substring(i + 5).split('/').first;
    }
    if (target != null && target != module && !target.endsWith('.dart')) out.add(target);
  }
  return out;
}

/// Относительная яркость по WCAG 2.x.
double _luminance(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('модули импортируют только разрешённое (А§2)', () {
    final violations = <String>[];
    var files = 0;
    for (final dir in Directory('lib').listSync().whereType<Directory>()) {
      final module = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
      expect(allowed.containsKey(module), isTrue, reason: 'каталог lib/$module не описан в А§2');
      for (final f in dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        files++;
        for (final target in importedModules(f, module)) {
          if (!allowed[module]!.contains(target)) violations.add('${f.path}: $module → $target');
        }
      }
    }
    expect(files, greaterThan(15));
    expect(violations, isEmpty);
  });

  test('проверка импортов не вакуумна: запрещённый импорт находится', () {
    final tmp = Directory.systemTemp.createTempSync('imports');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final f = File('${tmp.path}/x.dart')..writeAsStringSync("import 'package:audiobook_reader/screens/strings.dart';\n");
    expect(importedModules(f, 'reader'), {'screens'});
    expect(allowed['reader']!.contains('screens'), isFalse);
  });

  test('модули book и tts — чистый Dart, без Flutter (А§2)', () {
    for (final module in ['book', 'tts']) {
      for (final f in Directory('lib/$module').listSync(recursive: true).whereType<File>()) {
        expect(f.readAsStringSync().contains('package:flutter'), isFalse, reason: f.path);
        expect(f.readAsStringSync().contains('package:material_ui'), isFalse, reason: f.path);
      }
    }
  });

  group('контраст текста в палитрах ≥ 4,5 (WCAG AA)', () {
    for (final p in [lightPalette, sepiaPalette, darkPalette]) {
      test(p.name, () {
        final s = schemeFor(p);
        final pairs = <String, (Color, Color)>{
          'текст на фоне': (s.onSurface, s.surface),
          'второстепенный на фоне': (s.onSurfaceVariant, s.surface),
          'акцент на фоне': (s.primary, s.surface),
          'текст на кнопке': (s.onPrimary, s.primary),
          'текст на подсветке': (s.onPrimaryContainer, s.primaryContainer),
          // «второстепенный на подсветке» (ink2 на hl) в сепии — 4,20, ниже порога. Палитра закреплена владельцем,
          // поэтому эта пара в интерфейсе не используется: подпись выбранной строки рисуется цветом ink.
          'текст на панели': (s.onSurface, s.surfaceContainer),
          'второстепенный на панели': (s.onSurfaceVariant, s.surfaceContainer),
          'акцент на панели': (s.primary, s.surfaceContainer),
          'текст на тональной кнопке': (s.onSecondaryContainer, s.secondaryContainer),
          'текст на выделенном фоне': (s.onSurface, s.surfaceContainerHighest),
        };
        for (final e in pairs.entries) {
          final c = contrast(e.value.$1, e.value.$2);
          expect(c, greaterThanOrEqualTo(4.5), reason: '${p.name}: ${e.key} — ${c.toStringAsFixed(2)}');
        }
      });
    }

    test('формула контраста верна на известных парах', () {
      expect(contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)), moreOrLessEquals(21, epsilon: 0.05));
      expect(contrast(const Color(0xFF777777), const Color(0xFFFFFFFF)), moreOrLessEquals(4.48, epsilon: 0.05));
    });
  });
}
