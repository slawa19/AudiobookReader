import 'package:material_ui/material_ui.dart';

import '../book/model.dart';
import '../playback/voice_sample.dart';
import '../tts/voices.dart';
import 'common.dart';
import 'services.dart';

/// Выбор голоса (FR-V1, FR-V2). С [book] — свой голос книги (первая строка — «Как в настройках»),
/// без — голос приложения. Фраза пробы — на языке книги; для голоса приложения — на языке интерфейса.
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
    // Открытие экрана голоса ставит прослушивание на паузу (FR-V1) — после первого кадра, не посреди построения.
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
                padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + MediaQuery.paddingOf(context).bottom),
                child: Text(l10n.probeNote(s.sampler.phraseFor(_language(context))),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
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

  /// На узком экране с крупным шрифтом «Проба» — кнопка-значок: имя и характер голоса не рвутся посреди слова.
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
                    : s.sampler.play(v.name, bookLanguage: _language(context)),
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

  /// Постоянная ошибка пробы — текст Google как есть.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // На подсветке второстепенный цвет в сепии даёт контраст 4,2 — подпись выбранной строки основным цветом.
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
    // Цель касания не меньше 48 dp (FR-R8): стандартная плотность и минимум 48.
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
