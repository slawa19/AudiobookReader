import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../library/settings.dart';
import '../playback/narration.dart';
import '../tts/voices.dart';
import 'common.dart';

/// The player panel at the bottom of the reading screen (FR-P1, FR-P5–P8, FR-D1). States without audio are named in
/// words right in the panel (FR-P6) — without pop-ups. The chapter title is not repeated here: it is in the reading
/// header.
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
    required this.onChangeKey,
    required this.onPlay,
    required this.onPrevious,
    required this.onNext,
    this.header,
    this.download,
    required this.bottomInset,
    this.onMessageHeight,
  });

  /// The constant control body without the system inset: 8 + 52 + 4 + 76 + 10.
  static const controlsHeight = 150.0;

  final NarrationController narration;
  final AppSettings settings;
  final String voiceName;

  /// Whether the page follows the voice; if not — the "To reading place" button is in the panel row (FR-P4).
  final bool following;
  final VoidCallback onBackToReading;
  final VoidCallback onClose;
  final VoidCallback onVoice;
  final VoidCallback onSpeed;
  final VoidCallback onSleep;
  final VoidCallback onTopUp;
  final VoidCallback onChooseModel;
  final VoidCallback onChangeKey;

  /// "Listen" (from a pause and from the error panel), "back" and "forward": actions with which the user starts
  /// or changes the audio place themselves. These are controller commands; the screen turns following on by the counter
  /// of explicit controller commands (rule a, А§5) — the same as for commands from the notification and the headset.
  final VoidCallback onPlay;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// The book slider when the reading panels are shown (FR-R5: available during listening too).
  final Widget? header;

  /// The "Download chapter" row while the task runs.
  final Widget? download;

  final double bottomInset;

  /// Only the error message, the end of the book and the download row have a height by content.
  final ValueChanged<double>? onMessageHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = bottomInset;
    final state = narration.state;
    final Widget content;
    if (state == NarrationState.stopped && narration.stopReason == StopReason.error && narration.error != null) {
      final error = narration.error!;
      content = _ErrorContent(
        error: error,
        // The model on which the error happened is unavailable, not the one selected in settings afterwards (review
        // item 11).
        modelLabel: TtsModel.byId(error.modelId ?? settings.modelId).label,
        onClose: onClose,
        onListen: onPlay,
        onTopUp: onTopUp,
        onChooseModel: onChooseModel,
        onChangeKey: onChangeKey,
      );
    } else if (state == NarrationState.stopped) {
      // "Book finished" — only "Close": neither "back/forward" nor "Listen" (rule i).
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
        onPlay: onPlay,
        onPrevious: onPrevious,
        onNext: onNext,
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
          if ((state == NarrationState.stopped || download != null) && onMessageHeight != null)
            MeasureSize(onChange: (s) => onMessageHeight!(s.height), child: body)
          else
            body,
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
    required this.onPlay,
    required this.onPrevious,
    required this.onNext,
  });

  final NarrationController narration;
  final String voiceName;
  final bool following;
  final VoidCallback onBackToReading;
  final VoidCallback onClose;
  final VoidCallback onVoice;
  final VoidCallback onSpeed;
  final VoidCallback onSleep;
  final VoidCallback onPlay;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 52,
          child: LayoutBuilder(builder: (context, constraints) {
            // The place for both icons is constant. The state yields width to the voice, but not to the buttons.
            final voiceWidth = math.min(180.0, (constraints.maxWidth - 96) * 0.55);
            return Row(children: [
              ConstrainedBox(
                constraints: BoxConstraints(minWidth: voiceWidth, maxWidth: constraints.maxWidth - 96),
                child: VoiceChip(
                  key: const Key('voice-chip'), voiceName: voiceName, onPressed: onVoice)),
              Expanded(child: busy ? Tooltip(
                message: state == NarrationState.preparing ? l10n.preparing : l10n.waiting,
                child: Text(
                  state == NarrationState.preparing ? l10n.preparing : l10n.waiting,
                  key: const Key('player-status'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurface),
                ),
              ) : const SizedBox()),
              SizedBox(width: 48, height: 48, child: following ? null : IconButton(
                key: const Key('to-reading-place'),
                tooltip: l10n.toReadingPlace,
                icon: const Icon(Icons.my_location_rounded),
                onPressed: onBackToReading,
              )),
              SizedBox(width: 48, height: 48, child: IconButton(
                key: const Key('player-close'), tooltip: l10n.close,
                icon: const Icon(Icons.close_rounded), onPressed: onClose)),
            ]);
          }),
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
              onPressed: onPrevious,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            _PlayButton(
              playing: wantsToPlay,
              label: wantsToPlay ? l10n.pause : l10n.listen,
              onPressed: wantsToPlay ? narration.pause : onPlay,
            ),
            IconButton(
              key: const Key('next'),
              tooltip: l10n.next,
              iconSize: 30,
              onPressed: onNext,
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

/// The large central button. While audio plays, the circle becomes a rounded square (Material 3 Expressive).
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
    required this.onChangeKey,
  });

  final NarrationError error;
  final String modelLabel;
  final VoidCallback onClose;
  final VoidCallback onListen;
  final VoidCallback onTopUp;
  final VoidCallback onChooseModel;
  final VoidCallback onChangeKey;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Google's text — as is, without translation.
    final (title, body) = switch (error.kind) {
      NarrationErrorKind.payment => (l10n.error402Title, '${l10n.google(error.googleMessage)} ${l10n.error402Body}'),
      NarrationErrorKind.modelNotFound =>
        (l10n.error404Title(modelLabel), '${l10n.google(error.googleMessage)} ${l10n.error404Body}'),
      NarrationErrorKind.badKey => (l10n.errorKeyTitle, '${l10n.google(error.googleMessage)} ${l10n.errorKeyBody}'),
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
      NarrationErrorKind.badKey => ButtonPair(
          labels: [l10n.changeKey, l10n.listen],
          first: FilledButton.icon(
            key: const Key('change-key'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: onChangeKey,
            icon: const Icon(Icons.key_rounded),
            label: Text(l10n.changeKey),
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
