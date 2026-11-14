import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../book/model.dart';

const bookFontFamily = 'Merriweather';

/// Типографика страницы для одной ступени размера и одного системного масштаба шрифта.
///
/// Размер текста книги = ступень × системный масштаб (решение владельца 2026-11-14, FR-R6): масштаб применён
/// прямо к кеглю и интерлиньяжу здесь, поэтому дальше текст рисуется с [TextScaler.noScaling].
class PageStyle {
  PageStyle({required double fontSize, required double lineHeight, required TextScaler textScaler})
      : fontSize = textScaler.scale(fontSize),
        lineHeight = textScaler.scale(fontSize) * lineHeight / fontSize;

  final double fontSize;
  final double lineHeight;

  /// Красная строка (NOTES: 24 при кегле 16).
  double get indent => fontSize * 1.5;

  /// Отступ стихов и цитат слева.
  double get insetVerse => fontSize * 2;

  /// Где стоит вертикальная линия цитаты внутри отступа.
  double get citeRuleX => fontSize * 0.6;

  double get verseSize => fontSize * 0.92;
  double get verseLineHeight => lineHeight * 0.92;

  TextStyle get body => TextStyle(
        fontFamily: bookFontFamily,
        fontSize: fontSize,
        height: lineHeight / fontSize,
        leadingDistribution: TextLeadingDistribution.even,
      );

  StrutStyle get bodyStrut => StrutStyle(
        fontFamily: bookFontFamily,
        fontSize: fontSize,
        height: lineHeight / fontSize,
        leadingDistribution: TextLeadingDistribution.even,
        forceStrutHeight: true,
      );

  /// Правило оформления (README прототипа, FR-R3): стихи — курсив с отступом; цитата — прямое начертание с тем
  /// же отступом и тонкой линией слева. Кегль у обоих 0,92 основного.
  TextStyle get verse => body.copyWith(fontSize: verseSize, height: verseLineHeight / verseSize, fontStyle: FontStyle.italic);

  TextStyle get cite => body.copyWith(fontSize: verseSize, height: verseLineHeight / verseSize);

  StrutStyle get verseStrut => StrutStyle(
        fontFamily: bookFontFamily,
        fontSize: verseSize,
        height: verseLineHeight / verseSize,
        leadingDistribution: TextLeadingDistribution.even,
        forceStrutHeight: true,
      );

  TextStyle get headingTitle =>
      TextStyle(fontFamily: bookFontFamily, fontSize: fontSize * 1.45, height: 1.3, fontWeight: FontWeight.w700);

  TextStyle get headingSub =>
      TextStyle(fontFamily: bookFontFamily, fontSize: fontSize * 1.08, height: 1.4, fontStyle: FontStyle.italic);

  TextStyle get caption =>
      TextStyle(fontFamily: bookFontFamily, fontSize: fontSize * 0.82, height: 1.45, fontStyle: FontStyle.italic);

  bool isVerseLike(BlockKind k) => k == BlockKind.verse || k == BlockKind.cite;

  TextStyle textStyleFor(BlockKind k) => switch (k) {
        BlockKind.verse => verse,
        BlockKind.cite => cite,
        _ => body,
      };
  StrutStyle strutFor(BlockKind k) => isVerseLike(k) ? verseStrut : bodyStrut;

  /// Строит отрезок текста блока [start, end) с начертаниями. Цвет знака сноски — [noteColor]; на измерение
  /// цвет не влияет, поэтому разбивка и отрисовка зовут одну и ту же функцию.
  List<InlineSpan> spans(Block block, int start, int end, {Color? noteColor}) {
    final cuts = <int>{start, end};
    for (final s in block.spans) {
      if (s.end > start && s.start < end) {
        cuts.add(s.start.clamp(start, end));
        cuts.add(s.end.clamp(start, end));
      }
    }
    final points = cuts.toList()..sort();
    final out = <InlineSpan>[];
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a == b) continue;
      var style = const TextStyle();
      for (final s in block.spans) {
        if (s.start <= a && s.end >= b) {
          switch (s.style) {
            case SpanStyle.italic:
              style = style.copyWith(fontStyle: FontStyle.italic);
            case SpanStyle.bold:
              style = style.copyWith(fontWeight: FontWeight.w700);
            case SpanStyle.noteRef:
            case SpanStyle.sup:
              // Надстрочный знак даёт сам шрифт (функция `sups` у Merriweather есть); кегль не уменьшаем.
              style = style.copyWith(
                fontWeight: FontWeight.w700,
                color: s.style == SpanStyle.noteRef ? noteColor : null,
                fontFeatures: const [ui.FontFeature.superscripts()],
              );
            case SpanStyle.sub:
              style = style.copyWith(fontFeatures: const [ui.FontFeature.subscripts()]);
          }
        }
      }
      out.add(TextSpan(text: block.text.substring(a, b), style: style));
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is PageStyle && other.fontSize == fontSize && other.lineHeight == lineHeight;

  @override
  int get hashCode => Object.hash(fontSize, lineHeight);
}
