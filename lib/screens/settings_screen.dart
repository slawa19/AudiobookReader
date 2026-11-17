import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../playback/tariffs.dart';
import '../tts/voices.dart';
import 'common.dart';
import 'l10n/app_localizations.dart';
import 'licenses.dart';
import 'services.dart';
import 'voice_screen.dart';

/// Settings are one screen (CONCEPT §3): key, voice, model, interface language, spent, space for narration.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.services, this.focusKey = false, this.openModel = false});

  final AppServices services;

  /// "Listen" without a key and "Change key" after a key rejection lead here straight to the key field (FR-P7): the
  /// field is open for input even if a key is saved.
  final bool focusKey;

  /// A 404 response for the model — "Choose model" opens the choice at once.
  final bool openModel;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _keyController = TextEditingController();
  final _keyFocus = FocusNode();
  bool _editingKey = false;

  AppServices get s => widget.services;

  @override
  void initState() {
    super.initState();
    _editingKey = widget.focusKey;
    // Left the field (a tap elsewhere, another item) — a non-empty key is saved (gesture review decision E, FR-P7).
    _keyFocus.addListener(() {
      if (!_keyFocus.hasFocus) _keepTypedKey();
    });
    if (widget.openModel) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _chooseModel());
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  Future<void> _chooseModel() async {
    final picked = await showScrollableSheet<TtsModel>(
      context,
      (context) => _ModelSheet(current: TtsModel.byId(s.settings.modelId), tariffs: s.tariffs),
    );
    // A touch on the already selected model changes nothing and does not restart the session (rule j).
    if (picked != null && picked.id != s.settings.modelId) {
      s.settings.modelId = picked.id;
      s.narration.restartSession();
    }
  }

  Future<void> _chooseLanguage() async {
    final picked = await showScrollableSheet<String>(context, (context) => _LanguageSheet(current: s.settings.language));
    // An empty string — "Same as system".
    if (picked != null) s.settings.language = picked.isEmpty ? null : picked;
  }

  Future<void> _clear() async {
    final l10n = context.l10n;
    final size = formatBytes(l10n, s.audio.totalBytes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          icon: const Icon(Icons.music_off_rounded),
          title: Text(l10n.clearTitle),
          content: Text(l10n.clearBody(size)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
            FilledButton(
              key: const Key('clear-confirm'),
              style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.clear),
            ),
          ],
        );
      },
    );
    // One controller command: the session, "Download chapter", chapter readiness, probes and audio (FR-M3, A§4).
    if (ok ?? false) s.narration.clearAllNarration();
  }

  void _saveKey() {
    // "Done" on an empty field does not touch the key: the interface has no key deletion (rule j).
    if (_keyController.text.trim().isNotEmpty) s.settings.apiKey = _keyController.text;
    _keyController.clear();
    setState(() => _editingKey = false);
  }

  /// Entered in the field but not confirmed by the button: on leaving the field or the screen a non-empty value is
  /// saved, an empty one does not touch the key (gesture review decision E, FR-P7).
  void _keepTypedKey() {
    if (_keyController.text.trim().isEmpty) return;
    s.settings.apiKey = _keyController.text;
    _keyController.clear();
    if (mounted) setState(() => _editingKey = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    // Leaving the screen — by the "Back" arrow or the system "Back" — saves the entered key.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _keepTypedKey();
      },
      child: _scaffold(context, theme, scheme, l10n),
    );
  }

  Widget _scaffold(BuildContext context, ThemeData theme, ColorScheme scheme, AppLocalizations l10n) {
    return Scaffold(
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([s.settings, s.audio]),
          builder: (context, _) {
            final settings = s.settings;
            final showKeyField = !settings.hasApiKey || _editingKey;
            final voice = voiceByName(settings.voice);
            final model = TtsModel.byId(settings.modelId);
            final spent = s.spentByMonth();
            final languageName = settings.language == null
                ? l10n.asSystem
                : interfaceLanguages(l10n).firstWhere((e) => e.$1 == settings.language, orElse: () => ('', l10n.asSystem)).$2;
            return CustomScrollView(slivers: [
              SliverAppBar.large(title: Text(l10n.settings)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList.list(children: [
                  if (s.fakeTts)
                    Padding(
                      key: const Key('fake-voice'),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(l10n.fakeVoice, style: theme.textTheme.titleSmall),
                    ),
                  if (!settings.hasApiKey)
                    Container(
                      key: const Key('need-key'),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.key_rounded, color: scheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(l10n.needKey,
                              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer)),
                        ),
                      ]),
                    ),
                  _Group(children: [
                    if (showKeyField)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: TextField(
                          key: const Key('key-field'),
                          controller: _keyController,
                          focusNode: _keyFocus,
                          autofocus: widget.focusKey || _editingKey,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: l10n.geminiKey,
                            hintText: l10n.pasteKey,
                            prefixIcon: const Icon(Icons.key_rounded),
                            suffixIcon: Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: TextButton(
                                onPressed: () async {
                                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                                  if (data?.text != null) _keyController.text = data!.text!;
                                  if (_keyController.text.isNotEmpty) _saveKey();
                                },
                                child: Text(l10n.paste),
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _saveKey(),
                        ),
                      )
                    else
                      ListTile(
                        leading: const Icon(Icons.key_rounded),
                        title: Text(l10n.geminiKey),
                        subtitle: Text('•••• ${settings.apiKeyTail}'),
                        trailing: IconButton(
                          key: const Key('key-change'),
                          tooltip: l10n.change,
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => setState(() => _editingKey = true),
                        ),
                      ),
                    ListTile(
                      leading: const Icon(Icons.open_in_new_rounded),
                      title: Text(l10n.whereKey, style: TextStyle(color: scheme.primary)),
                      onTap: () => s.openUrl(context, keyUrl),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _Group(children: [
                    ListTile(
                      key: const Key('settings-voice'),
                      leading: const Icon(Icons.record_voice_over_rounded),
                      title: Text(l10n.voice),
                      subtitle: Text('${voice.name} — ${voiceCharacter(l10n, voice.character)}'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => VoiceScreen(services: s))),
                    ),
                    ListTile(
                      key: const Key('settings-model'),
                      leading: const Icon(Icons.graphic_eq_rounded),
                      title: Text(l10n.model),
                      subtitle: Text('${model.label} · ${l10n.perHour(s.tariffs.dollarsPerHour(model))}'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _chooseModel,
                    ),
                    ListTile(
                      key: const Key('settings-language'),
                      leading: const Icon(Icons.translate_rounded),
                      title: Text(l10n.language),
                      subtitle: Text(languageName),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _chooseLanguage,
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _Group(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(l10n.spent, style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary)),
                    ),
                    for (var i = 0; i < spent.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(children: [
                          Expanded(
                            child: Text(monthName(l10n, spent[i].month),
                                style: theme.textTheme.bodyLarge
                                    ?.copyWith(color: i == 0 ? scheme.onSurface : scheme.onSurfaceVariant)),
                          ),
                          Text(l10n.money(spent[i].dollars),
                              style: (i == 0 ? theme.textTheme.titleMedium : theme.textTheme.bodyLarge)
                                  ?.copyWith(color: i == 0 ? scheme.onSurface : scheme.onSurfaceVariant)),
                        ]),
                      ),
                    const SizedBox(height: 8),
                  ]),
                  const SizedBox(height: 12),
                  _Group(children: [
                    ListTile(
                      leading: const Icon(Icons.download_done_rounded),
                      title: Text(l10n.storage),
                      subtitle: Text(formatBytes(l10n, s.audio.totalBytes), key: const Key('storage-size')),
                      trailing: s.audio.totalBytes > 0
                          ? TextButton(key: const Key('clear'), onPressed: _clear, child: Text(l10n.clear))
                          : null,
                    ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(l10n.storageNote, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                  const SizedBox(height: 20),
                  _Group(children: [
                    ListTile(
                      key: const Key('settings-licenses'),
                      leading: const Icon(Icons.description_outlined),
                      title: Text(l10n.licenses),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => openLicenses(context),
                    ),
                  ]),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

/// A settings group is a rounded card, like in modern Android settings.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card.filled(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }
}

class _ModelSheet extends StatelessWidget {
  const _ModelSheet({required this.current, required this.tariffs});

  final TtsModel current;
  final Tariffs tariffs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    String note(TtsModel m) => m == TtsModel.flash ? l10n.byDefault : l10n.thirdCheaper;
    return RadioGroup<TtsModel>(
      groupValue: current,
      onChanged: (m) => Navigator.pop(context, m),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sheetTitle(context, l10n.model),
        for (final m in TtsModel.values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ListTile(
              key: Key('model-${m.name}'),
              selected: m == current,
              leading: Radio<TtsModel>(value: m),
              title: Text(m.label),
              subtitle: Text('${l10n.perHour(tariffs.dollarsPerHour(m))} · ${note(m)}',
                  style: m == current ? TextStyle(color: scheme.onSurface) : null),
              onTap: () => Navigator.pop(context, m),
            ),
          ),
        if (tariffs.beforePriceChange)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Text(
              l10n.price2027(TtsModel.flash.dollarsPerHourFrom2027, TtsModel.flashLite.dollarsPerHourFrom2027),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          const SizedBox(height: 24),
      ]),
    );
  }
}

/// "Language": "Same as system" and the five interface languages, each named in itself. Returns the language code or
/// an empty string for "Same as system".
class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet({required this.current});

  final String? current;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return RadioGroup<String>(
      groupValue: current ?? '',
      onChanged: (v) => Navigator.pop(context, v),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sheetTitle(context, l10n.language),
        for (final (code, name) in [('', l10n.asSystem), ...interfaceLanguages(l10n)])
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ListTile(
              key: Key('language-${code.isEmpty ? 'system' : code}'),
              selected: (current ?? '') == code,
              leading: Radio<String>(value: code),
              title: Text(name, style: (current ?? '') == code ? TextStyle(color: scheme.onSurface) : null),
              onTap: () => Navigator.pop(context, code),
            ),
          ),
        const SizedBox(height: 16),
      ]),
    );
  }
}
