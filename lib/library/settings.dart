import 'package:flutter/foundation.dart';

/// Тема: «как в системе» по умолчанию (FR-R6).
enum ThemeChoice { system, light, sepia, dark }

/// Ступени размера текста книги (docs/mockup/NOTES.md): кегль и интерлиньяж, dp. По умолчанию — третья.
/// На экране обе величины ещё умножаются на системный масштаб шрифта (решение владельца 2026-11-14, FR-R6).
const fontSteps = <({double size, double lineHeight})>[
  (size: 14, lineHeight: 24),
  (size: 15, lineHeight: 26),
  (size: 16, lineHeight: 27),
  (size: 18, lineHeight: 30),
  (size: 20, lineHeight: 34),
  (size: 22, lineHeight: 37),
];
const defaultFontStep = 2;

/// Скорости плеера (FR-P5).
const speeds = <double>[0.75, 1, 1.25, 1.5, 1.75, 2];

/// Настройки приложения (А§4). FileLibrary сохраняет их в settings.json; прототип — в памяти.
///
/// Голос и модель хранятся строками: `library` не знает модуля `tts` (А§2). Умолчания передаёт `app`.
class AppSettings extends ChangeNotifier {
  AppSettings({required this._voice, required this._modelId, this._apiKey});

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

  /// Язык интерфейса: код языка или `null` — «Как в системе» (язык телефона; не из поддерживаемых — английский).
  String? get language => _language;

  /// Ключ сюда не попадает: его хранение — отдельная задача платформы.
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

  /// Ключ в настоящем приложении лежит в защищённом хранилище; экрану нужен только хвост — не больше четырёх
  /// последних знаков, у короткого ключа — сколько есть.
  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;
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
  set apiKey(String? v) =>
      _set(() => _apiKey = (v == null || v.trim().isEmpty) ? null : v.trim());

  void _set(void Function() f) {
    f();
    notifyListeners();
  }
}
