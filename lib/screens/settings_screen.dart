import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../tts/voices.dart';
import 'services.dart';
import 'strings.dart';
import 'voice_screen.dart';

/// Настройки — один экран (CONCEPT §3): ключ, голос, модель, потрачено, место под озвучку.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.services, this.focusKey = false, this.openModel = false});

  final AppServices services;

  /// «Слушать» без ключа приводит сюда с фокусом на поле ключа (FR-P7).
  final bool focusKey;

  /// Ответ 404 на модель — «Выбрать модель» открывает выбор сразу.
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
    final picked = await showModalBottomSheet<TtsModel>(
      context: context,
      useSafeArea: true,
      builder: (context) => _ModelSheet(current: TtsModel.byId(s.settings.modelId)),
    );
    if (picked != null) {
      s.settings.modelId = picked.id;
      s.narration.restartSession();
    }
  }

  Future<void> _clear() async {
    final size = S.mb(s.audio.totalBytes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          icon: const Icon(Icons.music_off_rounded),
          title: const Text(S.clearTitle),
          content: Text(S.clearBody(size)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(S.cancel)),
            FilledButton(
              key: const Key('clear-confirm'),
              style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
              onPressed: () => Navigator.pop(context, true),
              child: const Text(S.clear),
            ),
          ],
        );
      },
    );
    if (ok ?? false) {
      s.clearNarration();
      setState(() {});
    }
  }

  void _saveKey() {
    s.settings.apiKey = _keyController.text;
    _keyController.clear();
    setState(() => _editingKey = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: ListenableBuilder(
        listenable: s.settings,
        builder: (context, _) {
          final settings = s.settings;
          final showKeyField = !settings.hasApiKey || _editingKey;
          final voice = voiceByName(settings.voice);
          final model = TtsModel.byId(settings.modelId);
          final spent = s.spentByMonth();
          return CustomScrollView(slivers: [
            const SliverAppBar.large(title: Text(S.settingsTitle)),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 32 + MediaQuery.paddingOf(context).bottom),
              sliver: SliverList.list(children: [
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
                        child: Text(S.needKey,
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
                          labelText: S.geminiKey,
                          hintText: S.pasteKey,
                          prefixIcon: const Icon(Icons.key_rounded),
                          suffixIcon: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: TextButton(
                              onPressed: () async {
                                final data = await Clipboard.getData(Clipboard.kTextPlain);
                                if (data?.text != null) _keyController.text = data!.text!;
                                if (_keyController.text.isNotEmpty) _saveKey();
                              },
                              child: const Text(S.paste),
                            ),
                          ),
                        ),
                        onSubmitted: (_) => _saveKey(),
                      ),
                    )
                  else
                    ListTile(
                      leading: const Icon(Icons.key_rounded),
                      title: const Text(S.geminiKey),
                      subtitle: Text('•••• ${settings.apiKeyTail}'),
                      trailing: IconButton(
                        key: const Key('key-change'),
                        tooltip: S.change,
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => setState(() => _editingKey = true),
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Icons.open_in_new_rounded),
                    title: Text(S.whereKey, style: TextStyle(color: scheme.primary)),
                    onTap: () => s.openUrl(context, S.keyUrl),
                  ),
                ]),
                const SizedBox(height: 12),
                _Group(children: [
                  ListTile(
                    key: const Key('settings-voice'),
                    leading: const Icon(Icons.record_voice_over_rounded),
                    title: const Text(S.voice),
                    subtitle: Text('${voice.name} — ${voice.character}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => VoiceScreen(services: s))),
                  ),
                  ListTile(
                    key: const Key('settings-model'),
                    leading: const Icon(Icons.graphic_eq_rounded),
                    title: const Text(S.model),
                    subtitle: Text('${model.label} · ${S.perHour(S.dollars(model.dollarsPerHourAt(DateTime(2026, 11, 14))))}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _chooseModel,
                  ),
                ]),
                const SizedBox(height: 12),
                _Group(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(S.spent, style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary)),
                  ),
                  for (var i = 0; i < spent.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(children: [
                        Expanded(
                          child: Text(S.months[spent[i].month.month - 1],
                              style: theme.textTheme.bodyLarge?.copyWith(
                                  color: i == 0 ? scheme.onSurface : scheme.onSurfaceVariant)),
                        ),
                        Text(S.dollars(spent[i].dollars),
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
                    title: const Text(S.storage),
                    subtitle: Text(S.mb(s.audio.totalBytes), key: const Key('storage-size')),
                    trailing: s.audio.totalBytes > 0
                        ? TextButton(key: const Key('clear'), onPressed: _clear, child: const Text(S.clear))
                        : null,
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(S.storageNote, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

/// Группа настроек — скруглённая карточка, как в современных настройках Android.
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
  const _ModelSheet({required this.current});

  final TtsModel current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = DateTime(2026, 11, 14);
    String note(TtsModel m) => m == TtsModel.flash ? S.byDefault : S.thirdCheaper;
    return SafeArea(
      top: false,
      child: RadioGroup<TtsModel>(
        groupValue: current,
        onChanged: (m) => Navigator.pop(context, m),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(S.model, style: theme.textTheme.titleLarge),
          ),
          for (final m in TtsModel.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListTile(
                key: Key('model-${m.name}'),
                selected: m == current,
                leading: Radio<TtsModel>(value: m),
                title: Text(m.label),
                subtitle: Text('${S.perHour(S.dollars(m.dollarsPerHourAt(today)))} · ${note(m)}',
                    style: m == current ? TextStyle(color: scheme.onSurface) : null),
                onTap: () => Navigator.pop(context, m),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Text(
              S.price2027(S.dollars(TtsModel.flash.dollarsPerHourFrom2027), S.dollars(TtsModel.flashLite.dollarsPerHourFrom2027)),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ]),
      ),
    );
  }
}
