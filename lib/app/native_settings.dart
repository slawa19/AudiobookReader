import '../library/settings.dart';

/// Подставному движку ключ не нужен. Все потребители одной настройки получают
/// одно разрешение на озвучку; фиктивный секрет не сохраняется и не показывается.
class NativeSettings extends AppSettings {
  NativeSettings({required super.voice, required super.modelId, super.secretStore, required this.fakeTts});
  final bool fakeTts;
  @override
  bool get hasApiKey => fakeTts || super.hasApiKey;
}
