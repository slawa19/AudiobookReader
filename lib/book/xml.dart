// Небольшое дерево XML. Восстанавливает только незакрытые элементы и неизвестные сущности (А§3).
// DTD не загружается и не исполняется: внешних обращений у разборщика нет.
import 'dart:convert';

import 'html_entities.dart';

class XmlElement {
  XmlElement(this.name, this.attributes, this.parent);
  final String name;
  final Map<String, String> attributes;
  final XmlElement? parent;
  final List<Object> children = [];
  String get local => name.split(':').last;
  Iterable<XmlElement> get elements => children.whereType<XmlElement>();
  Iterable<XmlElement> descendants([String? tag]) sync* {
    for (final e in elements) {
      if (tag == null || e.local == tag) yield e;
      yield* e.descendants(tag);
    }
  }

  XmlElement? child(String tag) =>
      elements.where((e) => e.local == tag).firstOrNull;
  String get text =>
      children.map((c) => c is XmlElement ? c.text : c as String).join();
  String? attr(String name) => attributes[name];
  String? namespaced(String uri, String local) {
    for (final entry in attributes.entries) {
      final parts = entry.key.split(':');
      if (parts.length != 2 || parts.last != local) continue;
      for (XmlElement? e = this; e != null; e = e.parent) {
        final ns = e.attributes['xmlns:${parts.first}'];
        if (ns != null) {
          if (ns == uri) return entry.value;
          break;
        }
      }
    }
    return null;
  }
}

const _cp1251 =
    'ЂЃ‚ѓ„…†‡€‰Љ‹ЊЌЋЏђ‘’“”•–—\u0098™љ›њќћџ'
    '\u00a0ЎўЈ¤Ґ¦§Ё©Є«¬\u00ad®Ї°±Ііґµ¶·ё№є»јЅѕї';

// 0x80..0xFF; undefined byte positions retain their C1 code point.
const _cp1250 =
    '€\u0081‚\u0083„…†‡\u0088‰Š‹ŚŤŽŹ\u0090‘’“”•–—\u0098™š›śťžź'
    '\u00a0ˇ˘Ł¤Ą¦§¨©Ş«¬\u00ad®Ż°±˛ł´µ¶·¸ąş»Ľ˝ľż'
    'ŔÁÂĂÄĹĆÇČÉĘËĚÍÎĎĐŃŇÓÔŐÖ×ŘŮÚŰÜÝŢß'
    'ŕáâăäĺćçčéęëěíîďđńňóôőö÷řůúűüýţ˙';
const _cp1252 =
    '€\u0081‚ƒ„…†‡ˆ‰Š‹Œ\u008dŽ\u008f\u0090‘’“”•–—˜™š›œ\u009džŸ'
    '\u00a0¡¢£¤¥¦§¨©ª«¬\u00ad®¯°±²³´µ¶·¸¹º»¼½¾¿'
    'ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞß'
    'àáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ';

String decodeXml(List<int> bytes) {
  if (bytes.length >= 2 &&
      ((bytes[0] == 255 && bytes[1] == 254) ||
          (bytes[0] == 254 && bytes[1] == 255) ||
          (bytes[0] == 60 && bytes[1] == 0) ||
          (bytes[0] == 0 && bytes[1] == 60))) {
    final le = bytes[0] == 255 || bytes[0] == 60;
    final start = bytes[0] == 255 || bytes[0] == 254 ? 2 : 0;
    if ((bytes.length - start).isOdd) {
      throw const FormatException('XML: odd UTF-16 length');
    }
    return String.fromCharCodes([
      for (var i = start; i < bytes.length; i += 2)
        le ? bytes[i] + (bytes[i + 1] << 8) : (bytes[i] << 8) + bytes[i + 1],
    ]);
  }
  final bom =
      bytes.length >= 3 &&
      bytes[0] == 239 &&
      bytes[1] == 187 &&
      bytes[2] == 191;
  final content = bom ? bytes.sublist(3) : bytes;
  final head = latin1.decode(content);
  final declaration = RegExp(
    r'''^\uFEFF?\s*<\?xml\s+[^?]*encoding\s*=\s*["']([^"']+)["']''',
  ).firstMatch(head);
  final encoding = declaration?.group(1)?.toLowerCase();
  String cp() => String.fromCharCodes(
    content.map(
      (b) => b < 128
          ? b
          : b >= 192
          ? b + 848
          : _cp1251.codeUnitAt(b - 128),
    ),
  );
  if (encoding == 'windows-1251' || encoding == 'cp1251') return cp();
  if (encoding == 'windows-1250' || encoding == 'windows-1252') {
    final table = encoding == 'windows-1250' ? _cp1250 : _cp1252;
    return String.fromCharCodes(
      content.map((b) => b < 128 ? b : table.codeUnitAt(b - 128)),
    );
  }
  if (encoding == 'iso-8859-1') return latin1.decode(bytes);
  if (encoding == 'us-ascii') return ascii.decode(content);
  if (encoding != null &&
      encoding != 'utf-8' &&
      encoding != 'utf8' &&
      encoding != 'us-ascii') {
    throw FormatException('XML: unsupported encoding $encoding');
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    if (encoding == 'utf-8' || encoding == 'utf8') return cp();
    rethrow;
  }
}

const _nameStart =
    r'A-Z_a-z\u00c0-\u00d6\u00d8-\u00f6\u00f8-\u02ff\u0370-\u037d\u037f-\u1fff\u200c-\u200d\u2070-\u218f\u2c00-\u2fef\u3001-\ud7ff\uf900-\ufdcf\ufdf0-\ufffd\u{10000}-\u{effff}';
final _name = RegExp(
  '[:$_nameStart][:\\-0-9.\\u00b7\\u0300-\\u036f\\u203f-\\u2040$_nameStart]*',
  unicode: true,
);
final _space = RegExp(r'[ \t\n\r]');

void _validateNamespaces(XmlElement node) {
  const xml = 'http://www.w3.org/XML/1998/namespace';
  const xmlns = 'http://www.w3.org/2000/xmlns/';
  String? lookup(String prefix) {
    if (prefix == 'xml') return xml;
    for (XmlElement? e = node; e != null; e = e.parent) {
      final value = e.attributes['xmlns:$prefix'];
      if (value != null) return value.isEmpty ? null : value;
    }
    return null;
  }

  final expanded = <String>{};
  for (final name in [node.name, ...node.attributes.keys]) {
    final parts = name.split(':');
    if (parts.length > 2 ||
        parts.any(
          (s) =>
              s.isEmpty ||
              _name.matchAsPrefix(s)?[0] != s ||
              RegExp(r'^[0-9.\-]').hasMatch(s),
        )) {
      throw FormatException('XML: invalid qualified name $name');
    }
    if (parts.length == 2 &&
        parts.first != 'xmlns' &&
        lookup(parts.first) == null) {
      throw FormatException('XML: undeclared prefix ${parts.first}');
    }
  }
  if (node.name.startsWith('xmlns:')) {
    throw const FormatException('XML: reserved element prefix');
  }
  for (final e in node.attributes.entries) {
    if (e.key == 'xmlns' || e.key.startsWith('xmlns:')) {
      final prefix = e.key == 'xmlns' ? '' : e.key.substring(6);
      if (prefix == 'xmlns' ||
          e.value == xmlns ||
          (prefix == 'xml') != (e.value == xml) ||
          (prefix.isNotEmpty && e.value.isEmpty)) {
        throw const FormatException('XML: invalid namespace declaration');
      }
      continue;
    }
    final parts = e.key.split(':');
    final key = '${parts.length == 2 ? lookup(parts.first) : ''}#${parts.last}';
    if (!expanded.add(key)) {
      throw const FormatException('XML: duplicate expanded attribute');
    }
  }
}

String _entities(String source) =>
    source.replaceAllMapped(RegExp(r'&([^;\s<&]*);?'), (m) {
      if (!m[0]!.endsWith(';') || m[1]!.isEmpty) {
        throw const FormatException('XML: malformed entity');
      }
      final s = m[1]!;
      if (htmlEntities.containsKey(s)) return htmlEntities[s]!;
      if (s.startsWith('#')) {
        final n = s.startsWith('#x')
            ? int.tryParse(s.substring(2), radix: 16)
            : int.tryParse(s.substring(1));
        if (n == null ||
            !_xmlChar(n) ||
            !RegExp(r'^#(?:[0-9]+|x[0-9a-fA-F]+)$').hasMatch(s)) {
          throw const FormatException('XML: invalid character reference');
        }
        return String.fromCharCode(n);
      }
      if (_name.firstMatch(s)?[0] != s) {
        throw const FormatException('XML: invalid entity name');
      }
      return m[0]!;
    });

bool _xmlChar(int c) =>
    c == 9 ||
    c == 10 ||
    c == 13 ||
    (c >= 32 && c <= 0xd7ff) ||
    (c >= 0xe000 && c <= 0xfffd) ||
    (c >= 0x10000 && c <= 0x10ffff);

XmlElement parseXml(String input) {
  final source = input
      .replaceFirst(RegExp(r'^\uFEFF'), '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  if (source.runes.any((c) => !_xmlChar(c))) {
    throw const FormatException('XML: invalid character');
  }
  var at = 0;
  final stack = <XmlElement>[];
  XmlElement? root;
  var doctype = false;
  Never fail(String why) => throw FormatException('XML at $at: $why');
  void whitespace() {
    while (at < source.length && _space.hasMatch(source[at])) {
      at++;
    }
  }

  String name() {
    final n = _name.matchAsPrefix(source, at)?[0];
    if (n == null) fail('expected name');
    at += n.length;
    return n;
  }

  void addText(String text) {
    if (stack.isEmpty) {
      if (!RegExp(r'^[ \t\n\r]*$').hasMatch(text)) fail('text outside root');
    } else {
      stack.last.children.add(text);
    }
  }

  while (at < source.length) {
    if (source[at] != '<') {
      final end = source.indexOf('<', at);
      final text = source.substring(at, end < 0 ? source.length : end);
      if (text.contains(']]>')) fail('unexpected CDATA end');
      addText(_entities(text));
      at += text.length;
    } else if (source.startsWith('<!--', at)) {
      final end = source.indexOf('-->', at + 4);
      if (end < 0 ||
          source.substring(at + 4, end).contains('--') ||
          source.substring(at + 4, end).endsWith('-')) {
        fail('invalid comment');
      }
      at = end + 3;
    } else if (source.startsWith('<![CDATA[', at)) {
      if (stack.isEmpty) fail('CDATA outside root');
      final end = source.indexOf(']]>', at + 9);
      if (end < 0) fail('unclosed CDATA');
      addText(source.substring(at + 9, end));
      at = end + 3;
    } else if (source.startsWith('<?', at)) {
      final start = at;
      at += 2;
      final target = name();
      final end = source.indexOf('?>', at);
      if (end < 0) fail('unclosed processing instruction');
      if (at < end && !_space.hasMatch(source[at])) {
        fail('invalid processing instruction');
      }
      if (target.toLowerCase() == 'xml') {
        if (start != 0 ||
            target != 'xml' ||
            !RegExp(
              r'''^\s+version\s*=\s*(['"])1\.[01]\1(\s+encoding\s*=\s*(['"])[A-Za-z][A-Za-z0-9._-]*\3)?(\s+standalone\s*=\s*(['"])(yes|no)\5)?\s*$''',
            ).hasMatch(source.substring(at, end))) {
          fail('invalid XML declaration');
        }
      }
      at = end + 2;
    } else if (source.startsWith('<!DOCTYPE', at)) {
      if (root != null || doctype) fail('unexpected DOCTYPE');
      doctype = true;
      at += 9;
      if (at >= source.length || !_space.hasMatch(source[at])) {
        fail('invalid DOCTYPE');
      }
      whitespace();
      name();
      // Только внешнее объявление. Внутренние DTD не нужны для книжной модели.
      final end = source.indexOf('>', at);
      if (end < 0 ||
          !RegExp(
            r'''^\s*(?:(?:SYSTEM\s+(?:"[^"]*"|'[^']*'))|(?:PUBLIC\s+(?:"[^"]*"|'[^']*')\s+(?:"[^"]*"|'[^']*')))?\s*$''',
          ).hasMatch(source.substring(at, end))) {
        fail('invalid DOCTYPE');
      }
      at = end + 1;
    } else if (source.startsWith('</', at)) {
      at += 2;
      final n = name();
      whitespace();
      if (at >= source.length || source[at++] != '>') {
        fail('invalid closing tag');
      }
      final i = stack.lastIndexWhere((e) => e.name == n);
      if (i < 0) fail('unmatched closing tag $n');
      stack.removeRange(i, stack.length);
    } else {
      at++;
      final n = name();
      final attrs = <String, String>{};
      var selfClosing = false;
      while (true) {
        final before = at;
        whitespace();
        if (source.startsWith('/>', at)) {
          selfClosing = true;
          at += 2;
          break;
        }
        if (at < source.length && source[at] == '>') {
          at++;
          break;
        }
        if (before == at) fail('expected space or tag end');
        final key = name();
        if (attrs.containsKey(key)) fail('duplicate attribute $key');
        whitespace();
        if (at >= source.length || source[at++] != '=') fail('expected =');
        whitespace();
        if (at >= source.length || (source[at] != '"' && source[at] != "'")) {
          fail('expected quoted attribute');
        }
        final quote = source[at++];
        final end = source.indexOf(quote, at);
        if (end < 0 || source.substring(at, end).contains('<')) {
          fail('invalid attribute');
        }
        attrs[key] = _entities(source.substring(at, end));
        at = end + 1;
      }
      final node = XmlElement(n, attrs, stack.lastOrNull);
      _validateNamespaces(node);
      if (stack.isEmpty) {
        if (root != null) fail('multiple roots');
        root = node;
      } else {
        stack.last.children.add(node);
      }
      if (!selfClosing) stack.add(node);
    }
  }
  if (root == null) fail('missing root');
  return root;
}
