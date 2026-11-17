import 'package:material_ui/material_ui.dart';

import '../book/model.dart';
import '../playback/voice_sample.dart';
import '../tts/voices.dart';
import 'common.dart';
import 'services.dart';

/// Voice choice (FR-V1, FR-V2). With [book] — the book's own voice (the first row is "As in settings"),
/// without — the app voice. The probe phrase is in the book language; for the app voice — in the interface language.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key, required this.services, this.book});

  final AppServices services;
  final Book? book;

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  static const _asSettings = '';

  AppServices get s => widget.services;

  @override
  void initState() {
    super.initState();
    // Opening the voice screen pauses listening (FR-V1) — after the first frame, not in the middle of building.
    WidgetsBinding.instance.addPostFrameCallback((_) => s.narration.pause());
  }

  @override
  void dispose() {
    s.sampler.stop();
    super.dispose();
  }

  String get _value {
    final book = widget.book;
    if (book == null) return s.settings.voice;
    return s.library.bookVoice(book.id) ?? _asSettings;
  }

  String _language(BuildContext context) => widget.book?.language ?? context.l10n.localeName;

  /// The voice that voices the book of this screen (or the book of the current listening — for the app voice).
  String _effectiveVoice() {
    final bookId = widget.book?.id ?? s.narration.bookId;
    return (bookId == null ? null : s.library.bookVoice(bookId)) ?? s.settings.voice;
  }

  void _select(String? v) {
    // A touch on the already selected row changes nothing and does not restart the session (rule j).
    if (v == null || v == _value) return;
    final before = _effectiveVoice();
    final book = widget.book;
    if (book == null) {
      s.settings.voice = v;
    } else {
      s.library.setBookVoice(book.id, v == _asSettings ? null : v);
    }
    // A voice change — a new session from the current segment with the previous intent (FR-V2); the same voice under
    // another row ("As in settings" and the same one explicitly) does not change the audio.
    if (_effectiveVoice() != before) s.narration.restartSession();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final book = widget.book;
    final female = allVoices.where((v) => v.female).toList();
    final male = allVoices.where((v) => !v.female).toList();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.voice),
          Text(book == null ? l10n.voiceForApp : l10n.voiceForBook(book.title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ]),
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([s.library, s.settings, s.sampler]),
          builder: (context, _) => RadioGroup<String>(
            groupValue: _value,
            onChanged: _select,
            child: CustomScrollView(slivers: [
              if (book != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: _VoiceTile(
                      value: _asSettings,
                      selected: _value == _asSettings,
                      title: l10n.voiceAsSettings,
                      subtitle: l10n.voiceNow(s.settings.voice),
                    ),
                  ),
                ),
              _header(context, l10n.female(female.length)),
              _list(context, female),
              _header(context, l10n.male(male.length)),
              _list(context, male),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Text(l10n.probeNote(s.sampler.phraseFor(_language(context))),
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String text) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 24, 6),
        child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
      ),
    );
  }

  /// On a narrow screen with a large font "Probe" is an icon button: the voice name and character are not broken
  /// mid-word.
  bool _compact(BuildContext context) =>
      MediaQuery.sizeOf(context).width / MediaQuery.textScalerOf(context).scale(1) < 340;

  Widget _list(BuildContext context, List<Voice> voices) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverList.builder(
          itemCount: voices.length,
          itemBuilder: (context, i) {
            final v = voices[i];
            final sampling = s.sampler.voice == v.name ? s.sampler.state : SampleState.idle;
            return _VoiceTile(
              key: Key('voice-${v.name}'),
              value: v.name,
              selected: _value == v.name,
              title: v.name,
              subtitle: voiceCharacter(context.l10n, v.character),
              error: sampling == SampleState.failed ? s.sampler.errorMessage : null,
              trailing: _ProbeButton(
                key: Key('probe-${v.name}'),
                compact: _compact(context),
                state: sampling,
                progress: s.sampler.progress,
                onPressed: () => sampling == SampleState.loading || sampling == SampleState.playing
                    ? s.sampler.stop()
                    : s.sampler.play(VoiceProfile(voiceId: v.name, model: s.settings.modelId),
                        bookLanguage: _language(context)),
              ),
            );
          },
        ),
      );
}

class _VoiceTile extends StatelessWidget {
  const _VoiceTile({
    super.key,
    required this.value,
    required this.selected,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.error,
  });

  final String value;
  final bool selected;
  final String title;
  final String subtitle;
  final Widget? trailing;

  /// A permanent probe error — Google's text as is.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // On the highlight the secondary color in sepia gives contrast 4.2 — the selected row's label in the primary color.
    final sub = TextStyle(color: selected ? scheme.onSurface : null);
    return ListTile(
      selected: selected,
      contentPadding: const EdgeInsets.only(left: 4, right: 8),
      leading: Radio<String>(value: value),
      title: Text(title),
      subtitle: error == null
          ? Text(subtitle, style: sub)
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(subtitle, style: sub),
              Text('${context.l10n.probeFailed}. ${context.l10n.google(error!)}',
                  key: const Key('probe-error'), style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
            ]),
      trailing: trailing,
      onTap: () => RadioGroup.maybeOf<String>(context)?.onChanged(value),
    );
  }
}

class _ProbeButton extends StatelessWidget {
  const _ProbeButton(
      {super.key, required this.state, required this.progress, required this.onPressed, this.compact = false});

  final SampleState state;
  final double progress;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = Text(context.l10n.probe);
    if (compact) {
      final busy = state == SampleState.loading || state == SampleState.playing;
      final icon = busy
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  value: state == SampleState.playing ? progress : null, strokeWidth: 2.5, color: scheme.onPrimary),
            )
          : Icon(state == SampleState.failed ? Icons.refresh_rounded : Icons.play_arrow_rounded);
      return busy
          ? IconButton.filled(tooltip: context.l10n.probe, onPressed: onPressed, icon: icon)
          : IconButton.filledTonal(tooltip: context.l10n.probe, onPressed: onPressed, icon: icon);
    }
    // Touch target at least 48 dp (FR-R8): standard density and a minimum of 48.
    final style = FilledButton.styleFrom(minimumSize: const Size(48, 48), visualDensity: VisualDensity.standard);
    if (state == SampleState.idle || state == SampleState.failed) {
      return FilledButton.tonalIcon(
        style: style,
        onPressed: onPressed,
        icon: Icon(state == SampleState.failed ? Icons.refresh_rounded : Icons.play_arrow_rounded, size: 20),
        label: label,
      );
    }
    return FilledButton.icon(
      style: style,
      onPressed: onPressed,
      icon: SizedBox(
        width: 18,
        height: 18,
        child: state == SampleState.loading
            ? CircularProgressIndicator(strokeWidth: 2.5, color: scheme.onPrimary)
            : CircularProgressIndicator(
                value: progress,
                strokeWidth: 2.5,
                color: scheme.onPrimary,
                backgroundColor: scheme.onPrimary.withValues(alpha: 0.3),
              ),
      ),
      label: label,
    );
  }
}
