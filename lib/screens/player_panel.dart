import 'package:material_ui/material_ui.dart';

import '../library/settings.dart';
import '../playback/narration.dart';
import '../tts/voices.dart';
import 'common.dart';
import 'strings.dart';

/// Панель плеера внизу экрана чтения (FR-P1, FR-P5–P8, FR-D1). Состояния без звука названы словами прямо в
/// панели (FR-P6) — без всплывающих окон.
class PlayerPanel extends StatelessWidget {
  const PlayerPanel({
    super.key,
    required this.narration,
    required this.settings,
    required this.voiceName,
    required this.chapterTitle,
    required this.onClose,
    required this.onVoice,
    required this.onSpeed,
    required this.onSleep,
    required this.onTopUp,
    required this.onChooseModel,
    this.header,
  });

  /// Высота панели в обычном состоянии без отступа под жесты: 8 + 52 + 4 + 76 + 10.
  static const controlsHeight = 150.0;

  /// Ползунок по книге, когда показаны панели чтения (FR-R5: доступен и во время прослушивания).
  final Widget? header;

  final NarrationController narration;
  final AppSettings settings;
  final String voiceName;
  final String chapterTitle;
  final VoidCallback onClose;
  final VoidCallback onVoice;
  final VoidCallback onSpeed;
  final VoidCallback onSleep;
  final VoidCallback onTopUp;
  final VoidCallback onChooseModel;

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
      content = _MessageContent(title: S.endOfBook, body: S.endOfBookBody, onClose: onClose);
    } else {
      content = _Controls(
        narration: narration,
        voiceName: voiceName,
        chapterTitle: chapterTitle,
        onClose: onClose,
        onVoice: onVoice,
        onSpeed: onSpeed,
        onSleep: onSleep,
      );
    }
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
            header!,
            Divider(indent: 24, endIndent: 24, color: scheme.outlineVariant),
          ],
          Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 8, bottom + 10),
            child: content,
          ),
        ]),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.narration,
    required this.voiceName,
    required this.chapterTitle,
    required this.onClose,
    required this.onVoice,
    required this.onSpeed,
    required this.onSleep,
  });

  final NarrationController narration;
  final String voiceName;
  final String chapterTitle;
  final VoidCallback onClose;
  final VoidCallback onVoice;
  final VoidCallback onSpeed;
  final VoidCallback onSleep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = narration.state;
    final busy = state == NarrationState.preparing || state == NarrationState.waiting;
    final wantsToPlay = busy || state == NarrationState.playing;
    final sleep = narration.sleepTimer;
    final sleepLabel = sleep == null
        ? null
        : sleep.kind == SleepKind.endOfChapter
            ? S.endOfChapterShort
            : S.minutesLeft((sleep.remaining(narration.now()).inSeconds / 60).ceil());

    final Widget status = busy
        ? Row(
            key: const Key('player-status'),
            children: [
              const SizedBox(width: 8),
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  state == NarrationState.preparing ? S.preparing : S.waiting,
                  style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurface),
                ),
              ),
            ],
          )
        : Row(children: [
            ActionChip(
                key: const Key('voice-chip'),
                avatar: Icon(Icons.record_voice_over_rounded, color: scheme.primary),
                label: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(voiceName),
                  const SizedBox(width: 2),
                  Icon(Icons.expand_more_rounded, size: 18, color: scheme.onSurfaceVariant),
                ]),
                tooltip: S.voice,
                onPressed: onVoice,
                shape: const StadiumBorder(),
                side: BorderSide(color: scheme.outlineVariant),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(chapterTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          ]);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 52,
          child: Row(children: [
            Expanded(child: status),
            IconButton(key: const Key('player-close'), tooltip: S.close, icon: const Icon(Icons.close_rounded), onPressed: onClose),
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
                child: FittedBox(child: Text(S.speedLabel(narration.speed), style: theme.textTheme.titleSmall)),
              ),
            ),
            IconButton(
              key: const Key('previous'),
              tooltip: S.previous,
              iconSize: 30,
              onPressed: narration.previous,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            _PlayButton(
              playing: wantsToPlay,
              onPressed: wantsToPlay ? narration.pause : narration.resume,
            ),
            IconButton(
              key: const Key('next'),
              tooltip: S.next,
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
                  label: S.sleepTimer,
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
  const _PlayButton({required this.playing, required this.onPressed});

  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: playing ? S.pause : S.play,
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
    final (title, body) = switch (error.kind) {
      NarrationErrorKind.payment => (S.error402Title, '${S.google(error.googleMessage)} ${S.error402Body}'),
      NarrationErrorKind.modelNotFound =>
        (S.error404Title(modelLabel), '${S.google(error.googleMessage)} ${S.error404Body}'),
      NarrationErrorKind.other => (S.errorOtherTitle, '«${error.googleMessage}»'),
    };
    final listen = OutlinedButton.icon(
      key: const Key('error-listen'),
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
      onPressed: onListen,
      icon: const Icon(Icons.play_arrow_rounded),
      label: const Text(S.listen),
    );
    final Widget actions = switch (error.kind) {
      NarrationErrorKind.payment => ButtonPair(
          labels: const [S.topUp, S.listen],
          first: FilledButton.icon(
            key: const Key('top-up'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: onTopUp,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text(S.topUp),
          ),
          second: listen,
        ),
      NarrationErrorKind.modelNotFound => ButtonPair(
          labels: const [S.chooseModel, S.listen],
          first: FilledButton(
            key: const Key('choose-model'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: onChooseModel,
            child: const Text(S.chooseModel),
          ),
          second: listen,
        ),
      NarrationErrorKind.other => FilledButton.icon(
          key: const Key('error-listen'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: onListen,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text(S.listen),
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
            IconButton(key: const Key('player-close'), tooltip: S.close, icon: const Icon(Icons.close_rounded), onPressed: onClose),
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
