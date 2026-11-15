import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../book/model.dart';
import '../library/library.dart';
import '../reader/page_style.dart';
import '../tts/voices.dart';
import 'l10n/app_localizations.dart';

/// Строки интерфейса — только из ARB (lib/screens/l10n), в коде экранов текста нет.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Адреса, на которые ведут кнопки (не строки интерфейса).
const billingUrl = 'https://aistudio.google.com/billing';
const keyUrl = 'https://aistudio.google.com/apikey';

/// Названия книг — гарнитурой книги (NOTES.md).
TextStyle bookTitleStyle(BuildContext context, double size, {FontWeight weight = FontWeight.w700}) => TextStyle(
      fontFamily: bookFontFamily,
      fontSize: size,
      height: 1.3,
      fontWeight: weight,
      color: Theme.of(context).colorScheme.onSurface,
    );

/// Защита от касания вдогонку (решение A проверки жестов 2026-11-14, А§8.1): после того как слой под пальцем
/// сменился — панели чтения ↔ панель плеера, открылся или закрылся лист или диалог, исчезла панель плеера или
/// строка скачивания, сменился экран, — новые элементы управления и страница под ними столько времени не принимают
/// касаний. Второе касание двойного нажатия приходит через 100–250 мс; два осмысленных нажатия — реже.
const layerSettleTime = Duration(milliseconds: 350);

/// Свежий слой (лист, диалог): первые [layerSettleTime] касания поглощаются — второе касание двойного нажатия,
/// открывшего лист, не нажимает то, что встало под палец, и не закрывает лист через затемнение.
class FreshLayerGuard extends StatefulWidget {
  const FreshLayerGuard({super.key, required this.child});

  final Widget child;

  @override
  State<FreshLayerGuard> createState() => _FreshLayerGuardState();
}

class _FreshLayerGuardState extends State<FreshLayerGuard> {
  bool _absorbing = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(layerSettleTime, () {
      if (mounted) setState(() => _absorbing = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AbsorbPointer(absorbing: _absorbing, child: widget.child);
}

/// Первая версия — только портретная ориентация (решение F проверки жестов; спека 001, «Не делаем»). Закреплено и
/// в манифесте Android (`android:screenOrientation="portrait"`).
const allowedOrientations = [DeviceOrientation.portraitUp];

void lockPortrait() {
  if (kIsWeb) return;
  SystemChrome.setPreferredOrientations(allowedOrientations);
}

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

/// Подпись только для показа: у безымянной главы — первый непустой блок её текста.
/// Модель книги не меняется. Берём до 12 слов для однострочной подписи, чтобы
/// шапка не раскладывала целиком блок в сотни тысяч знаков; виджет добавляет обрезку по ширине.
String chapterLabel(Book book, int chapter, {bool includeParent = true}) {
  final ch = book.chapters[chapter];
  if (ch.title.trim().isEmpty) {
    for (var i = ch.firstBlock; i < ch.endBlock; i++) {
      final words = RegExp(r'\S+').allMatches(book.blocks[i].text).take(13).map((m) => m.group(0)!).toList();
      if (words.isNotEmpty) {
        return words.length > 12 ? '${words.take(12).join(' ')}…' : words.join(' ');
      }
    }
    return '';
  }
  if (includeParent && ch.level > 1) {
    for (var j = chapter - 1; j >= 0; j--) {
      if (book.chapters[j].level < ch.level) {
        final parent = book.chapters[j].title;
        return parent.trim().isEmpty ? ch.title : '$parent · ${ch.title}';
      }
    }
  }
  return ch.title;
}

/// Объём на диске по локали: «96 МБ», «1,2 ГБ».
String formatBytes(AppLocalizations l10n, int bytes) {
  final mb = bytes / (1024 * 1024);
  if (mb >= 1024) return l10n.gigabytes(mb / 1024);
  return l10n.megabytes(mb.round());
}

/// Одинаковое округление на полке, внизу чтения и у ползунка. Значение 1 зарезервировано
/// для дочитанной книги (FR-L4); малая ненулевая позиция может показываться как 0 %.
double progressForDisplay(double fraction) => fraction >= 1 ? 1 : (fraction * 100).round().clamp(0, 99) / 100;

/// «Новая» у неоткрытой; числовая подпись общая для полки и чтения.
String shelfProgress(AppLocalizations l10n, double? fraction) {
  if (fraction == null) return l10n.progressNew;
  return l10n.percent(progressForDisplay(fraction));
}

/// Название месяца в именительном падеже с заглавной буквы: «Ноябрь», «November», «Listopad».
String monthName(AppLocalizations l10n, DateTime month) {
  final s = DateFormat.LLLL(l10n.localeName).format(month);
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

String voiceCharacter(AppLocalizations l10n, VoiceCharacter c) => switch (c) {
      VoiceCharacter.soft => l10n.voiceCharSoft,
      VoiceCharacter.breezy => l10n.voiceCharBreezy,
      VoiceCharacter.bright => l10n.voiceCharBright,
      VoiceCharacter.calm => l10n.voiceCharCalm,
      VoiceCharacter.smooth => l10n.voiceCharSmooth,
      VoiceCharacter.clear => l10n.voiceCharClear,
      VoiceCharacter.mature => l10n.voiceCharMature,
      VoiceCharacter.firm => l10n.voiceCharFirm,
      VoiceCharacter.upbeat => l10n.voiceCharUpbeat,
      VoiceCharacter.youthful => l10n.voiceCharYouthful,
      VoiceCharacter.forward => l10n.voiceCharForward,
      VoiceCharacter.warm => l10n.voiceCharWarm,
      VoiceCharacter.gentle => l10n.voiceCharGentle,
      VoiceCharacter.friendly => l10n.voiceCharFriendly,
      VoiceCharacter.gravelly => l10n.voiceCharGravelly,
      VoiceCharacter.informative => l10n.voiceCharInformative,
      VoiceCharacter.breathy => l10n.voiceCharBreathy,
      VoiceCharacter.excitable => l10n.voiceCharExcitable,
      VoiceCharacter.lively => l10n.voiceCharLively,
      VoiceCharacter.knowledgeable => l10n.voiceCharKnowledgeable,
      VoiceCharacter.even => l10n.voiceCharEven,
      VoiceCharacter.easygoing => l10n.voiceCharEasygoing,
      VoiceCharacter.conversational => l10n.voiceCharConversational,
    };

String addFailureText(AppLocalizations l10n, AddFailure f) => switch (f) {
      AddFailure.unsupported => l10n.addFailedUnsupported,
      AddFailure.unreadable => l10n.addFailedUnreadable,
      AddFailure.protected => l10n.addFailedProtected,
    };

/// Языки интерфейса: код → название на самом языке.
List<(String code, String name)> interfaceLanguages(AppLocalizations l10n) => [
      ('ru', l10n.langRu),
      ('en', l10n.langEn),
      ('pl', l10n.langPl),
      ('de', l10n.langDe),
    ];

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
              (entry.title.characters.firstOrNull ?? '').toUpperCase(),
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

/// Сообщает размер ребёнка после раскладки — чтобы страница кончалась над панелью, высота которой зависит от
/// состояния, языка и масштаба шрифта.
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({super.key, required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, RenderMeasureSize renderObject) => renderObject.onChange = onChange;
}

class RenderMeasureSize extends RenderProxyBox {
  RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    final s = size;
    if (s != _last) {
      _last = s;
      WidgetsBinding.instance.addPostFrameCallback((_) => onChange(s));
    }
  }
}

/// Чип голоса книги: в нижней панели чтения и в панели плеера.
class VoiceChip extends StatelessWidget {
  const VoiceChip({super.key, required this.voiceName, required this.onPressed});

  final String voiceName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(Icons.record_voice_over_rounded, color: scheme.primary),
      label: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(voiceName, maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 2),
        Icon(Icons.expand_more_rounded, size: 18, color: scheme.onSurfaceVariant),
      ]),
      tooltip: context.l10n.voice,
      onPressed: onPressed,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      shape: const StadiumBorder(),
      side: BorderSide(color: scheme.outlineVariant),
    );
  }
}

/// Лист с ручкой, который не выходит за экран: при нехватке высоты (узкий экран, крупный шрифт) прокручивается.
Future<T?> showScrollableSheet<T>(BuildContext context, WidgetBuilder builder, {Color? barrierColor}) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    barrierColor: barrierColor,
    builder: (context) => FreshLayerGuard(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: SafeArea(top: false, child: SingleChildScrollView(child: builder(context))),
      ),
    ),
  );
}

/// Заголовок листа.
Widget sheetTitle(BuildContext context, String text, {String? subtitle}) {
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
