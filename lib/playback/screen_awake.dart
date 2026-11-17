/// Platform port: keep the screen on only for the duration of a download on screen.
abstract interface class ScreenAwakePort {
  void setEnabled(bool enabled);
}
