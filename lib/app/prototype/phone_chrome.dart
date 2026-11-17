import 'package:material_ui/material_ui.dart';

import '../../screens/common.dart';

/// Prototype only: the status bar and the gesture pill over the app, so that in the browser and in screenshots
/// the screen looks like a phone in edge-to-edge mode. On a phone Android draws this.
/// In immersive mode (reading screen without panels) both are hidden, the way the system hides them.
class PhoneChrome extends StatelessWidget {
  const PhoneChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFF2EEE8) : const Color(0xFF1C1A17);
    return ValueListenableBuilder<bool>(
      valueListenable: systemBarsHidden,
      child: child,
      builder: (context, hidden, child) => Stack(children: [
        child!,
        if (padding.top > 0)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: padding.top,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: hidden ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    Text('12:30',
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: ink,
                          decoration: TextDecoration.none,
                        )),
                    const Spacer(),
                    Icon(Icons.signal_cellular_alt_rounded, size: 16, color: ink),
                    const SizedBox(width: 4),
                    Icon(Icons.wifi_rounded, size: 16, color: ink),
                    const SizedBox(width: 4),
                    Icon(Icons.battery_full_rounded, size: 16, color: ink),
                  ]),
                ),
              ),
            ),
          ),
        if (padding.bottom > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: padding.bottom,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: hidden ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: Center(
                  child: Container(
                    width: 108,
                    height: 4,
                    decoration:
                        BoxDecoration(color: ink.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
