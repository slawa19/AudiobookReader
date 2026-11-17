import 'dart:convert';

import 'package:audiobook_reader/book/parse.dart';
import 'package:flutter_test/flutter_test.dart';

/// The FB2 note marker (the `title` of its section) is not part of the note text — found on the owner's book on
/// 2026-11-15.
void main() {
  List<String> noteText(String notes) {
    final book = parseBook(utf8.encode(
      '<FictionBook xmlns:l="http://www.w3.org/1999/xlink"><body><section><p>Текст'
      '<a type="note" l:href="#n1">[1]</a>.</p></section></body><body name="notes">$notes</body></FictionBook>',
    )).book;
    return [for (final b in book.notes['n1']!.blocks) b.text];
  }

  test('the title of a note section is a marker, it does not go into the note text', () {
    expect(noteText('<section id="n1"><title><p>1</p></title><p>Пояснение.</p></section>'), ['Пояснение.']);
  });

  test('a note without title stays as is', () {
    expect(noteText('<section id="n1"><p>1</p><p>Пояснение.</p></section>'), ['1', 'Пояснение.']);
  });

  test('a note consisting of a single title does not become empty', () {
    expect(noteText('<section id="n1"><title><p>Пояснение.</p></title></section>'), ['Пояснение.']);
  });
}
