import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../book/model.dart';
import '../library/library.dart';
import '../reader/page_style.dart';

/// Названия книг — гарнитурой книги (NOTES.md).
TextStyle bookTitleStyle(BuildContext context, double size, {FontWeight weight = FontWeight.w700}) => TextStyle(
      fontFamily: bookFontFamily,
      fontSize: size,
      height: 1.3,
      fontWeight: weight,
      color: Theme.of(context).colorScheme.onSurface,
    );

/// Скрыты ли системные панели (экран чтения без панелей). Рамка прототипа в браузере рисует по нему строку
/// состояния; на телефоне то же делает система.
final ValueNotifier<bool> systemBarsHidden = ValueNotifier(false);

void setImmersive(bool hidden) {
  void apply() {
    if (systemBarsHidden.value == hidden) return;
    systemBarsHidden.value = hidden;
    if (!kIsWeb) {
      SystemChrome.setEnabledSystemUIMode(hidden ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
  }

  // Из initState и dispose нельзя менять слушаемое значение посреди кадра — откладываем на его конец.
  final phase = SchedulerBinding.instance.schedulerPhase;
  if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
    apply();
  } else {
    SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}

/// Название главы с родительским разделом: «Дама с собачкой · II».
String chapterLabel(Book book, int chapter) {
  final ch = book.chapters[chapter];
  if (ch.level > 1) {
    for (var j = chapter - 1; j >= 0; j--) {
      if (book.chapters[j].level < ch.level) return '${book.chapters[j].title} · ${ch.title}';
    }
  }
  return ch.title;
}

class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.entry, required this.width, this.radius = 8, this.elevated = true});

  final ShelfEntry entry;
  final double width;
  final double radius;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = width * 1.45;
    final cover = entry.cover;
    final child = cover != null
        ? Image(image: cover, width: width, height: height, fit: BoxFit.cover)
        : Container(
            width: width,
            height: height,
            color: scheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: Text(
              entry.title.characters.first.toUpperCase(),
              style: bookTitleStyle(context, width * 0.42).copyWith(color: scheme.onSurfaceVariant),
            ),
          );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: elevated
            ? [
                BoxShadow(color: scheme.shadow.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 4)),
                BoxShadow(color: scheme.shadow.withValues(alpha: 0.08), blurRadius: 2, offset: const Offset(0, 1)),
              ]
            : null,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: child),
    );
  }
}

/// Надпись раздела в списках и листах.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 8)});

  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

/// Две кнопки: в ряд поровну, а если подписи не помещаются — столбцом во всю ширину.
class ButtonPair extends StatelessWidget {
  const ButtonPair({super.key, required this.first, required this.second, required this.labels});

  final Widget first;
  final Widget second;

  /// Подписи кнопок — чтобы оценить нужную ширину.
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final style = Theme.of(context).textTheme.labelLarge ?? const TextStyle(fontSize: 14);
    return LayoutBuilder(builder: (context, c) {
      var need = 0.0;
      for (final l in labels) {
        final tp = TextPainter(text: TextSpan(text: l, style: style), textDirection: TextDirection.ltr, textScaler: scaler)
          ..layout();
        need = need < tp.width ? tp.width : need;
        tp.dispose();
      }
      // Иконка 18 + зазор 8 + поля кнопки 2 × 24.
      final perButton = need + 18 + 8 + 48;
      if (perButton * 2 + 8 <= c.maxWidth) {
        return Row(children: [Expanded(child: first), const SizedBox(width: 8), Expanded(child: second)]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [first, const SizedBox(height: 8), second]);
    });
  }
}
