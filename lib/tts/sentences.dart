// Границы предложений — то же правило, что в делении на отрезки (ARCHITECTURE.md, А§6.1, правило 2): конец
// предложения — знак конца (. ! ? …), за которым, возможно после закрывающих кавычек и скобок, идёт пробельный
// знак. Отдельной лингвистики нет: правило общее, по форме текста. Чистый Dart.

const _enders = {'.', '!', '?', '…'};
const _closers = {'»', '"', '”', '’', ')', ']'};

bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t' || c == ' ' || c == '\r';

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
    if (j >= 0 && _enders.contains(text[j])) out.add(i);
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
