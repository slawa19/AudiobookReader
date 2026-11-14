import 'package:material_ui/material_ui.dart';

import '../book/model.dart';
import '../library/settings.dart';
import '../playback/narration.dart';
import '../reader/page_style.dart';
import 'strings.dart';

/// Превью темы в листе «Вид текста»: фон и цвет текста. Палитры живут в `app`, поэтому их передают сюда.
typedef ThemePreview = ({Color bg, Color ink, Color line});

Widget _sheetTitle(BuildContext context, String text, {String? subtitle}) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(text, style: theme.textTheme.titleLarge),
      if (subtitle != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
    ]),
  );
}

/// «Вид текста» (FR-R6): размер и тема применяются сразу; страница за листом видна почти без затемнения.
Future<void> showTextAppearanceSheet(BuildContext context, AppSettings settings, Map<ThemeChoice, ThemePreview> previews) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.06),
    builder: (context) => ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              key: const Key('appearance-sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sheetTitle(context, S.textAppearance),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Text(S.size, style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    IconButton(
                      key: const Key('font-smaller'),
                      tooltip: 'Мельче',
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
                        // ignore: deprecated_member_use
                        year2023: false,
                        onChanged: (v) => settings.fontStep = v.round(),
                      ),
                    ),
                    IconButton(
                      key: const Key('font-larger'),
                      tooltip: 'Крупнее',
                      onPressed: settings.fontStep < fontSteps.length - 1 ? () => settings.fontStep = settings.fontStep + 1 : null,
                      icon: Text('A', style: TextStyle(fontFamily: bookFontFamily, fontSize: 26, color: scheme.onSurface)),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
                  child: Text(S.theme, style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (choice, label) in const [
                        (ThemeChoice.system, S.themeSystem),
                        (ThemeChoice.light, S.themeLight),
                        (ThemeChoice.sepia, S.themeSepia),
                        (ThemeChoice.dark, S.themeDark),
                      ])
                        Expanded(
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
                  ),
                ),
              ],
            ),
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
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (selected) ...[
                Icon(Icons.check_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 2),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : null,
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Скорость (FR-P5): шесть значений, меняет плеер без нового синтеза.
Future<void> showSpeedSheet(BuildContext context, AppSettings settings, NarrationController narration) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (context) => ListenableBuilder(
      listenable: narration,
      builder: (context, _) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _sheetTitle(context, S.speed),
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
                        label: S.speedLabel(sp),
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
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (context) {
      final theme = Theme.of(context);
      final current = narration.sleepTimer;
      String? subtitle;
      if (current != null) {
        subtitle = current.kind == SleepKind.endOfChapter
            ? S.sleepActiveChapter
            : S.sleepActive((current.remaining(narration.now()).inSeconds / 60).ceil());
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
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _sheetTitle(context, S.sleepTimer, subtitle: subtitle),
            const SizedBox(height: 4),
            for (final m in const [15, 30, 60])
              _Option(
                key: Key('sleep-$m'),
                label: S.sleepMinutes(m),
                selected: selected == m,
                onTap: () => set(SleepTimer.minutes(m, narration.now())),
              ),
            _Option(
              key: const Key('sleep-chapter'),
              label: S.sleepEndOfChapter,
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
                  label: Text(S.sleepOff, style: theme.textTheme.labelLarge),
                ),
              ),
          ]),
        ),
      );
    },
  );
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
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
          child: SingleChildScrollView(
            key: const Key('note-sheet'),
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(S.note(number), style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary)),
              const SizedBox(height: 10),
              for (final b in note.blocks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    b.text,
                    textScaler: TextScaler.noScaling,
                    style: style.body.copyWith(color: scheme.onSurface),
                  ),
                ),
            ]),
          ),
        ),
      );
    },
  );
}

String _noteNumber(Book book, String noteId) {
  for (final b in book.blocks) {
    for (final s in b.spans) {
      if (s.noteId == noteId) return b.text.substring(s.start, s.end);
    }
  }
  return '';
}
