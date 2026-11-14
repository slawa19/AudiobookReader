import 'package:material_ui/material_ui.dart';

import '../book/model.dart';
import '../playback/voice_sample.dart';
import '../tts/voices.dart';
import 'services.dart';
import 'strings.dart';

/// Выбор голоса (FR-V1, FR-V2). С [book] — свой голос книги (первая строка — «Как в настройках»),
/// без — голос приложения.
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
  void dispose() {
    s.sampler.stop();
    super.dispose();
  }

  String get _value {
    final book = widget.book;
    if (book == null) return s.settings.voice;
    return s.library.bookVoice(book.id) ?? _asSettings;
  }

  void _select(String? v) {
    if (v == null) return;
    final book = widget.book;
    if (book == null) {
      s.settings.voice = v;
    } else {
      s.library.setBookVoice(book.id, v == _asSettings ? null : v);
    }
    // Смена голоса — новый сеанс с текущего отрезка с прежним намерением (FR-V2).
    s.narration.restartSession();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final book = widget.book;
    final female = allVoices.where((v) => v.female).toList();
    final male = allVoices.where((v) => !v.female).toList();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(S.voiceTitle),
          Text(book == null ? S.voiceForApp : S.voiceForBook(book.title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ]),
      ),
      body: ListenableBuilder(
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
                    title: S.voiceAsSettings,
                    subtitle: S.voiceNow(s.settings.voice),
                  ),
                ),
              ),
            _header(context, S.female(female.length)),
            _list(female),
            _header(context, S.male(male.length)),
            _list(male),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + MediaQuery.paddingOf(context).bottom),
                child: Text(S.probeNote, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            ),
          ]),
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

  Widget _list(List<Voice> voices) => SliverPadding(
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
              subtitle: v.character,
              trailing: _ProbeButton(
                key: Key('probe-${v.name}'),
                state: sampling,
                progress: s.sampler.progress,
                onPressed: () => sampling == SampleState.idle ? s.sampler.play(v.name) : s.sampler.stop(),
              ),
            );
          },
        ),
      );
}

class _VoiceTile extends StatelessWidget {
  const _VoiceTile({super.key, required this.value, required this.selected, required this.title, required this.subtitle, this.trailing});

  final String value;
  final bool selected;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      contentPadding: const EdgeInsets.only(left: 4, right: 8),
      leading: Radio<String>(value: value),
      title: Text(title),
      // На подсветке второстепенный цвет в сепии даёт контраст 4,2 — подпись выбранной строки основным цветом.
      subtitle: Text(subtitle, style: selected ? TextStyle(color: Theme.of(context).colorScheme.onSurface) : null),
      trailing: trailing,
      onTap: () => RadioGroup.maybeOf<String>(context)?.onChanged(value),
    );
  }
}

class _ProbeButton extends StatelessWidget {
  const _ProbeButton({super.key, required this.state, required this.progress, required this.onPressed});

  final SampleState state;
  final double progress;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (state == SampleState.idle) {
      return FilledButton.tonalIcon(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 44), visualDensity: VisualDensity.compact),
        onPressed: onPressed,
        icon: const Icon(Icons.play_arrow_rounded, size: 20),
        label: const Text(S.probe),
      );
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size(0, 44), visualDensity: VisualDensity.compact),
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
      label: const Text(S.probe),
    );
  }
}
