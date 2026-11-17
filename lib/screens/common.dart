import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../library/library.dart';
import '../reader/page_style.dart';
import '../tts/voices.dart';
import 'l10n/app_localizations.dart';

/// Interface strings come only from the ARB (lib/screens/l10n); there is no text in the screen code.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Addresses the buttons lead to (not interface strings).
const billingUrl = 'https://aistudio.google.com/billing';
const keyUrl = 'https://aistudio.google.com/apikey';

/// Book titles use the book typeface (NOTES.md).
TextStyle bookTitleStyle(BuildContext context, double size, {FontWeight weight = FontWeight.w700}) => TextStyle(
      fontFamily: bookFontFamily,
      fontSize: size,
      height: 1.3,
      fontWeight: weight,
      color: Theme.of(context).colorScheme.onSurface,
    );

/// Protection against a follow-up touch (gesture review decision A 2026-11-14, А§8.1): after the layer under the finger
/// changed — reading panels ↔ player panel, a sheet or dialog opened or closed, the player panel or the
/// download row disappeared, the screen changed — the new controls and the page beneath them accept no
/// touches for this long. The second tap of a double tap arrives after 100–250 ms; two deliberate taps — less often.
const layerSettleTime = Duration(milliseconds: 350);

/// A fresh layer (sheet, dialog): the first [layerSettleTime] of touches are absorbed — the second tap of a double tap
/// that opened the sheet does not press what appeared under the finger and does not close the sheet through the scrim.
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

/// The first version is portrait only (gesture review decision F; spec 001, "Out of scope"). Also pinned
/// in the Android manifest (`android:screenOrientation="portrait"`).
const allowedOrientations = [DeviceOrientation.portraitUp];

void lockPortrait() {
  if (kIsWeb) return;
  SystemChrome.setPreferredOrientations(allowedOrientations);
}

/// Whether the system panels are hidden (the reading screen without panels). The prototype frame in the browser draws
/// the status bar by it; on a phone the system does the same.
final ValueNotifier<bool> systemBarsHidden = ValueNotifier(false);

void setImmersive(bool hidden) {
  void apply() {
    if (systemBarsHidden.value == hidden) return;
    systemBarsHidden.value = hidden;
    if (!kIsWeb) {
      SystemChrome.setEnabledSystemUIMode(hidden ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
  }

  // From initState and dispose the observed value cannot be changed in the middle of a frame — defer to its end.
  final phase = SchedulerBinding.instance.schedulerPhase;
  if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
    apply();
  } else {
    SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}

/// A size on disk by locale: "96 МБ", "1,2 ГБ".
String formatBytes(AppLocalizations l10n, int bytes) {
  final mb = bytes / (1024 * 1024);
  if (mb >= 1024) return l10n.gigabytes(mb / 1024);
  return l10n.megabytes(mb.round());
}

/// The same rounding on the shelf, at the bottom of reading and at the slider. The value 1 is reserved
/// for a finished book (FR-L4); a small non-zero position may be shown as 0 %.
double progressForDisplay(double fraction) => fraction >= 1 ? 1 : (fraction * 100).round().clamp(0, 99) / 100;

/// "New" for an unopened one; the numeric label is shared by the shelf and reading.
String shelfProgress(AppLocalizations l10n, double? fraction) {
  if (fraction == null) return l10n.progressNew;
  return l10n.percent(progressForDisplay(fraction));
}

/// A month name in the nominative case with a capital letter: "Ноябрь", "November", "Listopad".
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

/// Interface languages: code → name in the language itself.
List<(String code, String name)> interfaceLanguages(AppLocalizations l10n) => [
      ('ru', l10n.langRu),
      ('en', l10n.langEn),
      ('pl', l10n.langPl),
      ('de', l10n.langDe),
      ('uk', l10n.langUk),
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

/// Two buttons: side by side in equal parts, and if the labels do not fit — in a column of full width.
class ButtonPair extends StatelessWidget {
  const ButtonPair({super.key, required this.first, required this.second, required this.labels});

  final Widget first;
  final Widget second;

  /// Button labels — to estimate the needed width.
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
      // Icon 18 + gap 8 + button padding 2 × 24.
      final perButton = need + 18 + 8 + 48;
      if (perButton * 2 + 8 <= c.maxWidth) {
        return Row(children: [Expanded(child: first), const SizedBox(width: 8), Expanded(child: second)]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [first, const SizedBox(height: 8), second]);
    });
  }
}

/// Measures an error message, end of book or a download. The control panel is not measured:
/// its constant height does not depend on state and following.
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

/// The book voice chip: in the reading bottom panel and in the player panel.
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

/// A sheet with a handle that does not extend beyond the screen: when height is lacking (narrow screen, large font) it
/// scrolls.
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

/// A sheet title.
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
