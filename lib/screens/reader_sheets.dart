import 'package:material_ui/material_ui.dart';

import '../book/model.dart';
import '../library/settings.dart';
import '../playback/narration.dart';
import '../reader/page_style.dart';
import 'common.dart';

/// Превью темы в листе «Вид текста»: фон и цвет текста. Палитры живут в `app`, поэтому их передают сюда.
typedef ThemePreview = ({Color bg, Color ink, Color line});

/// «Вид текста» (FR-R6): размер и тема применяются сразу; страница за листом видна почти без затемнения.
Future<void> showTextAppearanceSheet(BuildContext context, AppSettings settings, Map<ThemeChoice, ThemePreview> previews) {
  return showScrollableSheet<void>(
    context,
    barrierColor: Colors.black.withValues(alpha: 0.06),
    (context) => ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final l10n = context.l10n;
        final tiles = [
          (ThemeChoice.system, l10n.asSystem),
          (ThemeChoice.light, l10n.themeLight),
          (ThemeChoice.sepia, l10n.themeSepia),
          (ThemeChoice.dark, l10n.themeDark),
        ];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            key: const Key('appearance-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sheetTitle(context, l10n.textAppearance),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text(l10n.size, style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  IconButton(
                    key: const Key('font-smaller'),
                    tooltip: l10n.smaller,
                    onPressed: settings.fontStep > 0 ? () => settings.fontStep = settings.fontStep - 1 : null,
                    icon: Text('A', style: TextStyle(fontFamily: bookFontFamily, fontSize: 15, color: scheme.onSurface)),
                  ),
                  Expanded(
                    child: Slider(
                      key: const Key('font-slider'),
                      value: settings.fontStep.toDouble(),
                      min: 0,
                      max: (fontSteps.length - 1).toDouble(),
                      divisions: fontSteps.length - 1,
                      // Внешний вид Material 3 2024 года; флаг помечен устаревшим, но другого способа включить его нет.
                      // ignore: deprecated_member_use
                      year2023: false,
                      onChanged: (v) => settings.fontStep = v.round(),
                    ),
                  ),
                  IconButton(
                    key: const Key('font-larger'),
                    tooltip: l10n.larger,
                    onPressed:
                        settings.fontStep < fontSteps.length - 1 ? () => settings.fontStep = settings.fontStep + 1 : null,
                    icon: Text('A', style: TextStyle(fontFamily: bookFontFamily, fontSize: 26, color: scheme.onSurface)),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
                child: Text(l10n.theme, style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LayoutBuilder(builder: (context, c) {
                  // Четыре плитки в ряд, если самое длинное слово подписи помещается в плитку; иначе — по две
                  // (узкий экран, крупный шрифт, длинные слова): слово не рвётся посередине.
                  final labelStyle = theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700);
                  final scaler = MediaQuery.textScalerOf(context);
                  var longest = 0.0;
                  for (final (_, label) in tiles) {
                    for (final word in label.split(' ')) {
                      final tp = TextPainter(
                          text: TextSpan(text: word, style: labelStyle), textDirection: TextDirection.ltr, textScaler: scaler)
                        ..layout();
                      if (tp.width > longest) longest = tp.width;
                      tp.dispose();
                    }
                  }
                  final perRow = longest + 8 + 2 <= c.maxWidth / 4 ? 4 : 2;
                  final w = c.maxWidth / perRow;
                  return Wrap(
                    children: [
                      for (final (choice, label) in tiles)
                        SizedBox(
                          width: w,
                          child: _ThemeTile(
                            key: Key('theme-${choice.name}'),
                            label: label,
                            selected: settings.theme == choice,
                            preview: previews[choice]!,
                            split: choice == ThemeChoice.system ? previews[ThemeChoice.dark] : null,
                            onTap: () => settings.theme = choice,
                          ),
                        ),
                    ],
                  );
                }),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    super.key,
    required this.label,
    required this.selected,
    required this.preview,
    required this.onTap,
    this.split,
  });

  final String label;
  final bool selected;
  final ThemePreview preview;
  final ThemePreview? split;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(18);
    Widget aa(ThemePreview p) => Center(
          child: Text('Aa', style: TextStyle(fontFamily: bookFontFamily, fontSize: 20, color: p.ink)),
        );
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 64,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: selected ? scheme.primary : preview.line, width: selected ? 3 : 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(selected ? 15 : 17),
                child: split == null
                    ? ColoredBox(color: preview.bg, child: aa(preview))
                    : Row(children: [
                        Expanded(child: ColoredBox(color: preview.bg, child: const SizedBox.expand())),
                        Expanded(child: ColoredBox(color: split!.bg, child: const SizedBox.expand())),
                      ]),
              ),
            ),
            const SizedBox(height: 6),
            if (selected) Icon(Icons.check_rounded, size: 16, color: scheme.primary),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : null,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Скорость (FR-P5): шесть значений, меняет плеер без нового синтеза.
Future<void> showSpeedSheet(BuildContext context, AppSettings settings, NarrationController narration) {
  return showScrollableSheet<void>(
    context,
    (context) => ListenableBuilder(
      listenable: narration,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          sheetTitle(context, context.l10n.speed),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: LayoutBuilder(builder: (context, c) {
              final w = (c.maxWidth - 16) / 3;
              return Wrap(spacing: 8, runSpacing: 8, children: [
                for (final sp in speeds)
                  SizedBox(
                    width: w,
                    child: _Choice(
                      key: Key('speed-$sp'),
                      label: context.l10n.speedValue(sp),
                      selected: narration.speed == sp,
                      onTap: () {
                        narration.setSpeed(sp);
                        settings.speed = sp;
                        Navigator.pop(context);
                      },
                    ),
                  ),
              ]);
            }),
          ),
        ]),
      ),
    ),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(selected ? 16 : 28)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Center(
              child: Text(label,
                  style: theme.textTheme.titleMedium?.copyWith(color: selected ? scheme.onPrimary : scheme.onSurface)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Таймер сна (FR-D1): 15, 30, 60 минут, «до конца главы», «выключить».
Future<void> showSleepSheet(BuildContext context, NarrationController narration) {
  return showScrollableSheet<void>(context, (context) {
    final l10n = context.l10n;
    final current = narration.sleepTimer;
    String? subtitle;
    if (current != null) {
      subtitle = current.kind == SleepKind.endOfChapter
          ? l10n.sleepActiveChapter
          : l10n.sleepActive((current.remaining(narration.now()).inSeconds / 60).ceil());
    }
    void set(SleepTimer? t) {
      narration.setSleepTimer(t);
      Navigator.pop(context);
    }

    final selected = current == null
        ? null
        : current.kind == SleepKind.endOfChapter
            ? -1
            : current.minutes;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sheetTitle(context, l10n.sleepTimer, subtitle: subtitle),
        const SizedBox(height: 4),
        for (final m in const [15, 30, 60])
          _Option(
            key: Key('sleep-$m'),
            label: l10n.sleepMinutes(m),
            selected: selected == m,
            onTap: () => set(SleepTimer.minutes(m, narration.now())),
          ),
        _Option(
          key: const Key('sleep-chapter'),
          label: l10n.sleepEndOfChapter,
          selected: selected == -1,
          onTap: () => set(SleepTimer.endOfChapter(narration.now())),
        ),
        if (current != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: FilledButton.tonalIcon(
              key: const Key('sleep-off'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => set(null),
              icon: const Icon(Icons.close_rounded),
              label: Text(l10n.sleepOff),
            ),
          ),
      ]),
    );
  });
}

class _Option extends StatelessWidget {
  const _Option({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListTile(
        selected: selected,
        title: Text(label),
        trailing: selected ? Icon(Icons.check_rounded, color: scheme.primary) : null,
        onTap: onTap,
      ),
    );
  }
}

/// Сноска поверх страницы, без перехода (FR-R3).
Future<void> showNoteSheet(BuildContext context, {required Book book, required String noteId, required PageStyle style}) {
  final note = book.notes[noteId];
  if (note == null) return Future.value();
  final number = _noteNumber(book, noteId);
  return showScrollableSheet<void>(context, (context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      key: const Key('note-sheet'),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.l10n.note(number), style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary)),
        const SizedBox(height: 10),
        for (final b in note.blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(b.text, textScaler: TextScaler.noScaling, style: style.body.copyWith(color: scheme.onSurface)),
          ),
      ]),
    );
  });
}

String _noteNumber(Book book, String noteId) {
  for (final b in book.blocks) {
    for (final s in b.spans) {
      if (s.noteId == noteId) return b.text.substring(s.start, s.end);
    }
  }
  return '';
}
