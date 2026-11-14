// Независимая проверка начала предложения для тестов места старта (FR-P3). Написана заново регулярными
// выражениями по тексту правил А§6.1 («знак конца и пробел»; (i) не после слова из одной буквы; (ii) дальше —
// прописная, цифра или открывающая кавычка, в том числе после тире с пробелом), а не вызовом
// `lib/tts/sentences.dart`: иначе тест сверял бы производственную функцию с ней самой (ревью логики 2026-11-14).

import 'package:audiobook_reader/book/model.dart';
import 'package:audiobook_reader/book/speech_text.dart';
import 'package:audiobook_reader/library/library.dart';
import 'package:audiobook_reader/reader/pagination.dart';

final _end = RegExp(r'(\p{L}*)([.!?…])[»"”’)\]]*[ \t\n\r ]+$', unicode: true);
final _start = RegExp(r'^(?:[—–-][  ]+)?[\p{Lu}0-9«"“„‘(\[]', unicode: true);

/// Начинается ли предложение в тексте для речи [text] на смещении [s].
bool looksLikeSentenceStart(String text, int s) {
  if (s == 0) return text.isNotEmpty;
  if (s >= text.length || RegExp(r'\s').hasMatch(text[s])) return false;
  final m = _end.firstMatch(text.substring(0, s));
  if (m == null) return false;
  if (m.group(2) == '.' && m.group(1)!.length == 1) return false;
  return _start.hasMatch(text.substring(s));
}

/// Первое начало предложения, стоящее на странице [page], — перебором каждого смещения.
ReadingPosition? firstSentenceStartOnPage(Book book, BookPageLayout page) {
  for (final f in page.fragments) {
    final block = book.blocks[f.block];
    if (f.isImage || !block.isSpoken) continue;
    final speech = speechText(block);
    for (var i = speech.fromBlock(f.start); i < speech.text.length; i++) {
      final at = speech.toBlock(i);
      if (at >= f.end) break;
      if (looksLikeSentenceStart(speech.text, i)) return ReadingPosition(f.block, at);
    }
  }
  return null;
}
