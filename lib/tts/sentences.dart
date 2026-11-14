// Границы предложений — то же правило, что в делении на отрезки (ARCHITECTURE.md, А§6.1, правило 2). Правило
// общее, по форме текста, без списков слов. Чистый Dart.
//
// Граница — там, где после знака конца (. ! ? …), возможно закрывающих кавычек и скобок, идёт пробельный знак, и:
//  (i)  точка стоит не после слова из одной буквы: «г. Москве», «А. С. Пушкин», «т. е.» — не конец;
//  (ii) следующее слово (после пробела, а если там тире с пробелом — после тире) начинается с прописной буквы, цифры
//       или открывающей кавычки или скобки; строчная буква — предложение продолжается: «…потом заговорил»,
//       «— Стой! — крикнул он». Для письменностей без регистра правило (ii) не применяется.
// Остаточные ошибки — сокращения длиннее одной буквы («см. рис. 3») — принятое ограничение: старт чуть раньше или
// чуть позже, текст не теряется.
//
// Границы ищутся в тексте для речи (без знаков сносок, `speechText`, А§3) и переводятся обратно в смещения блока.

import '../book/model.dart';
import '../book/speech_text.dart';

const _enders = {'.', '!', '?', '…'};
const _closers = {'»', '"', '”', '’', ')', ']'};
const _openers = {'«', '"', '“', '„', '‘', '(', '['};
const _dashes = {'—', '–', '-'};

bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t' || c == ' ' || c == '\r';

bool _isLetter(String c) => c.toUpperCase() != c.toLowerCase();

bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

/// (ii): может ли с [c] начинаться новое предложение. Строчная буква — нет; прописная, цифра, открывающая кавычка
/// или скобка — да; буква без регистра (письменности без прописных) и прочие знаки правилом (ii) не проверяются.
bool _canStart(String c) {
  if (_isDigit(c) || _openers.contains(c)) return true;
  if (_isLetter(c)) return c == c.toUpperCase();
  return true;
}

/// Смещения начал предложений в [text] (кодовые единицы UTF-16), по возрастанию. Первое — 0, если текст не пуст.
List<int> sentenceStarts(String text) {
  if (text.isEmpty) return const [];
  final out = <int>[0];
  for (var i = 1; i < text.length; i++) {
    if (_isSpace(text[i]) || !_isSpace(text[i - 1])) continue;
    // Перед пробелами — конец предыдущего предложения?
    var j = i - 1;
    while (j >= 0 && _isSpace(text[j])) {
      j--;
    }
    while (j >= 0 && _closers.contains(text[j])) {
      j--;
    }
    if (j < 0 || !_enders.contains(text[j])) continue;
    // (i) точка после слова из одной буквы — инициал или сокращение, не конец.
    if (text[j] == '.' && j >= 1 && _isLetter(text[j - 1]) && (j == 1 || !_isLetter(text[j - 2]))) continue;
    // (ii) следующее слово — с прописной, цифры или открывающей кавычки; после тире с пробелом — слово за тире.
    var k = i;
    if (_dashes.contains(text[k]) && k + 1 < text.length && _isSpace(text[k + 1])) {
      k++;
      while (k < text.length && _isSpace(text[k])) {
        k++;
      }
      if (k >= text.length) continue;
    }
    if (!_canStart(text[k])) continue;
    out.add(i);
  }
  return out;
}

/// Начало предложения, в котором стоит смещение [offset].
int sentenceStartAt(String text, int offset) {
  var best = 0;
  for (final s in sentenceStarts(text)) {
    if (s > offset) break;
    best = s;
  }
  return best;
}

/// Начала предложений блока — по тексту для речи, в смещениях `Block.text`.
List<int> blockSentenceStarts(Block block) {
  final speech = speechText(block);
  return [for (final s in sentenceStarts(speech.text)) speech.toBlock(s)];
}

/// Начало предложения блока, в котором стоит смещение блока [offset].
int blockSentenceStartAt(Block block, int offset) {
  var best = 0;
  for (final s in blockSentenceStarts(block)) {
    if (s > offset) break;
    best = s;
  }
  return best;
}
