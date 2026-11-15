/// Порт платформы: удерживать экран включённым только на время скачивания на экране.
abstract interface class ScreenAwakePort {
  void setEnabled(bool enabled);
}
