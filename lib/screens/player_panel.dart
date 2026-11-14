import 'package:material_ui/material_ui.dart';

import '../library/settings.dart';
import '../playback/narration.dart';
import '../tts/voices.dart';
import 'common.dart';

/// Панель плеера внизу экрана чтения (FR-P1, FR-P5–P8, FR-D1). Состояния без звука названы словами прямо в
/// панели (FR-P6) — без всплывающих окон. Название главы здесь не повторяется: оно в шапке чтения.
class PlayerPanel extends StatelessWidget {
  const PlayerPanel({
    super.key,
    required this.narration,
    required this.settings,
    required this.voiceName,
    required this.following,
    required this.onBackToReading,
    required this.onClose,
    required this.onVoice,
    required this.onSpeed,
    required this.onSleep,
    required this.onTopUp,
    required this.onChooseModel,
    this.header,
    this.download,
    this.onBodyHeight,
  });

  /// Оценка высоты тела панели в обычном состоянии без отступа под жесты: 8 + 52 + 4 + 76 + 10. Точную высоту
  /// экран получает через [onBodyHeight].
  static const controlsHeight = 150.0;

  final NarrationController narration;
  final AppSettings settings;
  final String voiceName;

  /// Следует ли страница за голосом; если нет — в строке панели кнопка «К месту чтения» (FR-P4).
  final bool following;
  final VoidCallback onBackToReading;
  final VoidCallback onClose;
  final VoidCallback onVoice;
  final VoidCallback onSpeed;
  final VoidCallback onSleep;
  final VoidCallback onTopUp;
  final VoidCallback onChooseModel;

  /// Ползунок по книге, когда показаны панели чтения (FR-R5: доступен и во время прослушивания).
  final Widget? header;

  /// Строка «Скачать главу», пока задача идёт.
  final Widget? download;

  /// Высота тела панели (без [header]) — по ней страница кончается над панелью.
  final ValueChanged<double>? onBodyHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final state = narration.state;
    final Widget content;
    if (state == NarrationState.stopped && narration.stopReason == StopReason.error && narration.error != null) {
      content = _ErrorContent(
        error: narration.error!,
        modelLabel: TtsModel.byId(settings.modelId).label,
        onClose: onClose,
        onListen: narration.resume,
        onTopUp: onTopUp,
        onChooseModel: onChooseModel,
      );
    } else if (state == NarrationState.stopped) {
      content = _MessageContent(
          title: context.l10n.endOfBook, body: context.l10n.endOfBookBody, onClose: onClose);
    } else {
      content = _Controls(
        narration: narration,
        voiceName: voiceName,
        following: following,
        onBackToReading: onBackToReading,
        onClose: onClose,
        onVoice: onVoice,
        onSpeed: onSpeed,
        onSleep: onSleep,
      );
    }
    final body = Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 8, bottom + 10),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (download != null) Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: download),
        content,
      ]),
    );
    return Material(
      key: const Key('player-panel'),
      color: scheme.surfaceContainer,
      elevation: 3,
      shadowColor: scheme.shadow.withValues(alpha: 0.5),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (header != null) ...[
            Padding(padding: const EdgeInsets.only(top: 10), child: header!),
            Divider(indent: 24, endIndent: 24, color: scheme.outlineVariant),
          ],
          if (onBodyHeight == null) body else MeasureSize(onChange: (s) => onBodyHeight!(s.height), child: body),
        ]),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.narration,
    required this.voiceName,
    required this.following,
    required this.onBackToReading,
    required this.onClose,
    required this.onVoice,
    required this.onSpeed,
    required this.onSleep,
  });

  final NarrationController narration;
  final String voiceName;
  final bool following;
  final VoidCallback onBackToReading;
  final VoidCallback onClose;
  final VoidCallback onVoice;
  final VoidCallback onSpeed;
  final VoidCallback onSleep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final state = narration.state;
    final busy = state == NarrationState.preparing || state == NarrationState.waiting;
    final wantsToPlay = busy || state == NarrationState.playing;
    final sleep = narration.sleepTimer;
    final sleepLabel = sleep == null
        ? null
        : sleep.kind == SleepKind.endOfChapter
            ? l10n.endOfChapterShort
            : l10n.minutesShort((sleep.remaining(narration.now()).inSeconds / 60).ceil());

    final Widget status = busy
        ? Row(
            key: const Key('player-status'),
            children: [
              const SizedBox(width: 8),
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  state == NarrationState.preparing ? l10n.preparing : l10n.waiting,
                  style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurface),
                ),
              ),
            ],
          )
        : Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              VoiceChip(key: const Key('voice-chip'), voiceName: voiceName, onPressed: onVoice),
              if (!following)
                FilledButton.tonalIcon(
                  key: const Key('to-reading-place'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: onBackToReading,
                  icon: const Icon(Icons.my_location_rounded),
                  label: Text(l10n.toReadingPlace),
                ),
            ],
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(children: [
            Expanded(child: status),
            IconButton(key: const Key('player-close'), tooltip: l10n.close, icon: const Icon(Icons.close_rounded), onPressed: onClose),
          ]),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: 64,
              height: 48,
              child: TextButton(
                key: const Key('speed'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: scheme.onSurface),
                onPressed: onSpeed,
                child: FittedBox(child: Text(l10n.speedValue(narration.speed), style: theme.textTheme.titleSmall)),
              ),
            ),
            IconButton(
              key: const Key('previous'),
              tooltip: l10n.previous,
              iconSize: 30,
              onPressed: narration.previous,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            _PlayButton(
              playing: wantsToPlay,
              label: wantsToPlay ? l10n.pause : l10n.listen,
              onPressed: wantsToPlay ? narration.pause : narration.resume,
            ),
            IconButton(
              key: const Key('next'),
              tooltip: l10n.next,
              iconSize: 30,
              onPressed: narration.next,
              icon: const Icon(Icons.skip_next_rounded),
            ),
            SizedBox(
              width: 64,
              child: InkResponse(
                key: const Key('sleep'),
                radius: 28,
                onTap: onSleep,
                child: Semantics(
                  button: true,
                  label: l10n.sleepTimer,
                  child: SizedBox(
                    height: 48,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(sleep == null ? Icons.bedtime_outlined : Icons.bedtime_rounded,
                            color: sleep == null ? scheme.onSurface : scheme.primary),
                        if (sleepLabel != null)
                          FittedBox(
                            child: Text(sleepLabel,
                                style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary, height: 1.2)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Крупная центральная кнопка. Пока звук идёт, круг становится скруглённым квадратом (Material 3 Expressive).
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.label, required this.onPressed});

  final bool playing;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: AnimatedContainer(
        key: const Key('play-pause'),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(playing ? 24 : 38),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(playing ? 24 : 38)),
            onTap: onPressed,
            child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 40, color: scheme.onPrimary),
          ),
        ),
      ),
    );
  }
}

class _ErrorContent extends StatelessWidget {
  const _ErrorContent({
    required this.error,
    required this.modelLabel,
    required this.onClose,
    required this.onListen,
    required this.onTopUp,
    required this.onChooseModel,
  });

  final NarrationError error;
  final String modelLabel;
  final VoidCallback onClose;
  final VoidCallback onListen;
  final VoidCallback onTopUp;
  final VoidCallback onChooseModel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Текст Google — как есть, без перевода.
    final (title, body) = switch (error.kind) {
      NarrationErrorKind.payment => (l10n.error402Title, '${l10n.google(error.googleMessage)} ${l10n.error402Body}'),
      NarrationErrorKind.modelNotFound =>
        (l10n.error404Title(modelLabel), '${l10n.google(error.googleMessage)} ${l10n.error404Body}'),
      NarrationErrorKind.other => (l10n.errorOtherTitle, l10n.quoted(error.googleMessage)),
    };
    final listen = OutlinedButton.icon(
      key: const Key('error-listen'),
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
      onPressed: onListen,
      icon: const Icon(Icons.play_arrow_rounded),
      label: Text(l10n.listen),
    );
    final Widget actions = switch (error.kind) {
      NarrationErrorKind.payment => ButtonPair(
          labels: [l10n.topUp, l10n.listen],
          first: FilledButton.icon(
            key: const Key('top-up'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: onTopUp,
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(l10n.topUp),
          ),
          second: listen,
        ),
      NarrationErrorKind.modelNotFound => ButtonPair(
          labels: [l10n.chooseModel, l10n.listen],
          first: FilledButton(
            key: const Key('choose-model'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: onChooseModel,
            child: Text(l10n.chooseModel),
          ),
          second: listen,
        ),
      NarrationErrorKind.other => FilledButton.icon(
          key: const Key('error-listen'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: onListen,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(l10n.listen),
        ),
    };
    return _MessageContent(title: title, body: body, onClose: onClose, icon: Icons.error_outline_rounded, actions: actions);
  }
}

class _MessageContent extends StatelessWidget {
  const _MessageContent({required this.title, required this.body, required this.onClose, this.actions, this.icon});

  final String title;
  final String body;
  final VoidCallback onClose;
  final Widget? actions;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4),
      child: Column(
        key: const Key('player-message'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (icon != null)
              Padding(
                padding: const EdgeInsets.only(top: 12, right: 12, left: 4),
                child: Icon(icon, color: scheme.error),
              )
            else
              const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
            ),
            IconButton(
                key: const Key('player-close'),
                tooltip: context.l10n.close,
                icon: const Icon(Icons.close_rounded),
                onPressed: onClose),
          ]),
          Padding(
            padding: EdgeInsets.fromLTRB(icon != null ? 40 : 4, 2, 12, 0),
            child: Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          if (actions != null) Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 0), child: actions),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
