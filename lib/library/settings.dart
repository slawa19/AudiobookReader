import 'package:flutter/foundation.dart';

import 'secret_store.dart';

/// Theme: "same as system" by default (FR-R6).
enum ThemeChoice { system, light, sepia, dark }

/// Book text size steps (docs/mockup/NOTES.md): font size and line height, dp. The default is the third.
/// On screen both values are additionally multiplied by the system font scale (owner's decision 2026-11-14, FR-R6).
const fontSteps = <({double size, double lineHeight})>[
  (size: 14, lineHeight: 24),
  (size: 15, lineHeight: 26),
  (size: 16, lineHeight: 27),
  (size: 18, lineHeight: 30),
  (size: 20, lineHeight: 34),
  (size: 22, lineHeight: 37),
];
const defaultFontStep = 2;

/// Player speeds (FR-P5).
const speeds = <double>[0.75, 1, 1.25, 1.5, 1.75, 2];

/// App settings (А§4). FileLibrary saves them to settings.json; the prototype — in memory.
///
/// The voice and model are stored as strings: `library` does not know the `tts` module (А§2). Defaults are passed by
/// `app`.
class AppSettings extends ChangeNotifier {
  AppSettings({
    required this._voice,
    required this._modelId,
    this._apiKey,
    this._secretStore,
  });

  final SecretStore? _secretStore;
  Future<void> _secretWriter = Future.value();
  bool _secretWriteFailed = false;

  ThemeChoice _theme = ThemeChoice.system;
  int _fontStep = defaultFontStep;
  double _speed = 1;
  String _voice;
  String _modelId;
  String? _apiKey;
  String? _language;

  ThemeChoice get theme => _theme;
  int get fontStep => _fontStep;
  double get speed => _speed;
  String get voice => _voice;
  String get modelId => _modelId;

  /// Interface language: a language code or `null` — "Same as system" (the phone language; if unsupported — English).
  String? get language => _language;

  /// The key does not get here: a separate protected storage keeps it.
  Map<String, Object?> toJson() => {
    'theme': theme.name,
    'fontStep': fontStep,
    'speed': speed,
    'voice': voice,
    'modelId': modelId,
    'language': language,
  };

  void restore(Map<String, Object?> json) {
    _theme = ThemeChoice.values.where((v) => v.name == json['theme']).firstOrNull ?? _theme;
    if (json['fontStep'] case final int step) _fontStep = step.clamp(0, fontSteps.length - 1);
    if (json['speed'] case final num value) _speed = value.toDouble();
    if (json['voice'] case final String value) _voice = value;
    if (json['modelId'] case final String value) _modelId = value;
    _language = json['language'] is String ? json['language']! as String : null;
    notifyListeners();
  }

  /// In the real app the key lies in the protected storage; the screen needs only the tail — at most the last four
  /// characters, for a short key — as many as there are.
  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;
  String? get apiKey => _apiKey;
  String get apiKeyTail {
    final key = _apiKey;
    if (key == null || key.isEmpty) return '';
    return key.length <= 4 ? key : key.substring(key.length - 4);
  }

  set theme(ThemeChoice v) => _set(() => _theme = v);
  set language(String? v) => _set(() => _language = v);
  set fontStep(int v) =>
      _set(() => _fontStep = v.clamp(0, fontSteps.length - 1));
  set speed(double v) => _set(() => _speed = v);
  set voice(String v) => _set(() => _voice = v);
  set modelId(String v) => _set(() => _modelId = v);
  set apiKey(String? v) {
    final value = v?.replaceAll(RegExp(r'[\s\p{Cc}\p{Default_Ignorable_Code_Point}]', unicode: true), '');
    _apiKey = value == null || value.isEmpty ? null : value;
    final store = _secretStore;
    if (store != null && value != null && value.isNotEmpty) {
      // The value is captured at the time of the change; quick edits are written in order.
      _secretWriter = _secretWriter.then((_) async {
        try {
          await store.write(value);
        } catch (_) {
          // Neither the original error nor its stack may carry the key into diagnostics.
          _secretWriteFailed = true;
        }
      });
    }
    notifyListeners();
  }

  /// Called by the library before the app is ready. A read failure after
  /// data recovery leaves the field empty for re-entering the key.
  Future<void> loadApiKey() async {
    final store = _secretStore;
    if (store == null) return;
    try {
      final value = (await store.read())?.trim();
      _apiKey = value == null || value.isEmpty ? null : value;
    } catch (_) {
      _apiKey = null;
    }
  }

  /// Waits for the key to be written. Also called by FileLibrary.flush().
  Future<void> flushApiKey() async {
    await _secretWriter;
    if (_secretWriteFailed) {
      _secretWriteFailed = false;
      throw const SecretStoreException();
    }
  }

  void _set(void Function() f) {
    f();
    notifyListeners();
  }
}
