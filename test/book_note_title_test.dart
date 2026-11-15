import 'dart:convert';

import 'package:audiobook_reader/book/parse.dart';
import 'package:flutter_test/flutter_test.dart';

/// Знак сноски FB2 (`title` её раздела) не входит в текст сноски — найдено на книге владельца 2026-11-15.
void main() {
  List<String> noteText(String notes) {
    final book = parseBook(utf8.encode(
      '<FictionBook xmlns:l="http://www.w3.org/1999/xlink"><body><section><p>Текст'
      '<a type="note" l:href="#n1">[1]</a>.</p></section></body><body name="notes">$notes</body></FictionBook>',
    )).book;
    return [for (final b in book.notes['n1']!.blocks) b.text];
  }

  test('title раздела сноски — знак, в текст сноски не идёт', () {
    expect(noteText('<section id="n1"><title><p>1</p></title><p>Пояснение.</p></section>'), ['Пояснение.']);
  });

  test('сноска без title остаётся как есть', () {
    expect(noteText('<section id="n1"><p>1</p><p>Пояснение.</p></section>'), ['1', 'Пояснение.']);
  });

  test('сноска из одного title не становится пустой', () {
    expect(noteText('<section id="n1"><title><p>Пояснение.</p></title></section>'), ['Пояснение.']);
  });
}
