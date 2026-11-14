// Текст для речи (ARCHITECTURE.md, раздел 3): текст блока без структурных знаков сносок (`noteRef`) и без знака
// ударения U+0301, с соответствием смещений обратно в `Block.text`. Чистый Dart.
//
// Минимальная версия для прототипа: по ней ищутся границы предложений (старт «Слушать», А§5) — знак сноски после
// точки не прячет начало следующего предложения. Настоящее приложение строит по ней и отрезки (А§6.1).

import 'model.dart';

const _stress = '́';

class SpeechText {
  const SpeechText(this.text, this._toBlock);

  /// То, что произносится.
  final String text;

  /// Смещение в `Block.text` для каждого смещения в [text] и для его конца (длина `text.length + 1`).
  final List<int> _toBlock;

  /// Смещение в `Block.text`, соответствующее смещению [i] текста для речи.
  int toBlock(int i) => _toBlock[i.clamp(0, _toBlock.length - 1)];

  /// Первое смещение текста для речи, которое в блоке стоит не раньше [blockOffset].
  int fromBlock(int blockOffset) {
    for (var i = 0; i < _toBlock.length; i++) {
      if (_toBlock[i] >= blockOffset) return i;
    }
    return text.length;
  }
}

SpeechText speechText(Block block) {
  final skip = List<bool>.filled(block.text.length, false);
  for (final s in block.spans) {
    if (s.style != SpanStyle.noteRef) continue;
    for (var i = s.start; i < s.end && i < skip.length; i++) {
      skip[i] = true;
    }
  }
  final out = StringBuffer();
  final map = <int>[];
  for (var i = 0; i < block.text.length; i++) {
    if (skip[i] || block.text[i] == _stress) continue;
    out.write(block.text[i]);
    map.add(i);
  }
  map.add(block.text.length);
  return SpeechText(out.toString(), map);
}
