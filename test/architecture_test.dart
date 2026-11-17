import 'dart:io';
import 'dart:math' as math;

import 'package:audiobook_reader/app/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Allowed direct imports between modules: ARCHITECTURE.md, section 2 (FR-E5).
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

final _import = RegExp(r"""^(?:import|export)\s+'([^']+)'""", multiLine: true);

/// Modules imported by the file [file] of module [module].
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

/// Relative luminance per WCAG 2.x.
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
  test('importedModules sees import and export with a trailing clause and skips plain text', () {
    final temp = Directory.systemTemp.createTempSync('architecture-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final cases = <String, Set<String>>{
      "import 'package:audiobook_reader/book/model.dart';": {'book'},
      "import 'package:audiobook_reader/tts/engine.dart' as tts;": {'tts'},
      "import 'package:audiobook_reader/audio/audio_store.dart' show AudioStore;": {'audio'},
      "import 'package:audiobook_reader/library/library.dart' hide Library;": {'library'},
      "export 'package:audiobook_reader/reader/pagination.dart';": {'reader'},
      "// import 'package:audiobook_reader/book/model.dart';": {},
      "// export 'package:audiobook_reader/book/model.dart';": {},
      "const text = \"import 'package:audiobook_reader/book/model.dart';\";": {},
      "const text = \"export 'package:audiobook_reader/book/model.dart';\";": {},
    };
    final file = File('${temp.path}/directives.dart');
    for (final entry in cases.entries) {
      file.writeAsStringSync(entry.key);
      expect(importedModules(file, 'app'), entry.value, reason: entry.key);
    }
  });

  test('modules import only what is allowed (A§2)', () {
    final violations = <String>[];
    var files = 0;
    for (final dir in Directory('lib').listSync().whereType<Directory>()) {
      final module = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
      expect(allowed.containsKey(module), isTrue, reason: 'directory lib/$module is not described in A§2');
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

  test('the import check is not vacuous: a forbidden import is found', () {
    final tmp = Directory.systemTemp.createTempSync('imports');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final f = File('${tmp.path}/x.dart')..writeAsStringSync("import 'package:audiobook_reader/screens/strings.dart';\n");
    expect(importedModules(f, 'reader'), {'screens'});
    expect(allowed['reader']!.contains('screens'), isFalse);
  });

  test('modules book and tts are pure Dart, without Flutter (A§2)', () {
    for (final module in ['book', 'tts']) {
      for (final f in Directory('lib/$module').listSync(recursive: true).whereType<File>()) {
        expect(f.readAsStringSync().contains('package:flutter'), isFalse, reason: f.path);
        expect(f.readAsStringSync().contains('package:material_ui'), isFalse, reason: f.path);
      }
    }
  });

  group('text contrast in palettes ≥ 4.5 (WCAG AA)', () {
    for (final p in [lightPalette, sepiaPalette, darkPalette]) {
      test(p.name, () {
        final s = schemeFor(p);
        final pairs = <String, (Color, Color)>{
          'text on background': (s.onSurface, s.surface),
          'secondary on background': (s.onSurfaceVariant, s.surface),
          'accent on background': (s.primary, s.surface),
          'text on button': (s.onPrimary, s.primary),
          'text on highlight': (s.onPrimaryContainer, s.primaryContainer),
          // "secondary on highlight" (ink2 on hl) in sepia is 4.20, below the threshold. The palette is fixed by the
          // owner, so this pair is not used in the UI: the label of the selected row is drawn in the ink colour.
          'text on panel': (s.onSurface, s.surfaceContainer),
          'secondary on panel': (s.onSurfaceVariant, s.surfaceContainer),
          'accent on panel': (s.primary, s.surfaceContainer),
          'text on tonal button': (s.onSecondaryContainer, s.secondaryContainer),
          'text on selected background': (s.onSurface, s.surfaceContainerHighest),
        };
        for (final e in pairs.entries) {
          final c = contrast(e.value.$1, e.value.$2);
          expect(c, greaterThanOrEqualTo(4.5), reason: '${p.name}: ${e.key} — ${c.toStringAsFixed(2)}');
        }
      });
    }

    test('the contrast formula is correct on known pairs', () {
      expect(contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)), moreOrLessEquals(21, epsilon: 0.05));
      expect(contrast(const Color(0xFF777777), const Color(0xFFFFFFFF)), moreOrLessEquals(4.48, epsilon: 0.05));
    });
  });
}
