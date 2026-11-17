import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../library/settings.dart';

/// Palette tokens of the former mock-up (docs/mockup/NOTES.md, "Palette"). The palette and fonts are taken from the
/// mock-up by the owner's decision 2026-11-14; only the components and composition are new.
class Palette {
  const Palette({
    required this.name,
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.ink,
    required this.ink2,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.hl,
    required this.scrim,
  });

  final String name;
  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color ink;
  final Color ink2;
  final Color line;
  final Color accent;
  final Color onAccent;
  final Color hl;
  final Color scrim;
}

const lightPalette = Palette(
  name: 'light',
  brightness: Brightness.light,
  bg: Color(0xFFF8F4EC),
  surface: Color(0xFFFFFDF9),
  ink: Color(0xFF221D17),
  ink2: Color(0xFF675E54),
  line: Color(0xFFE3DBCE),
  accent: Color(0xFFA8431F),
  onAccent: Color(0xFFFFFDF9),
  hl: Color(0xFFF3DFCF),
  scrim: Color(0x6B221D17), // ink × 0.42
);

const sepiaPalette = Palette(
  name: 'sepia',
  brightness: Brightness.light,
  bg: Color(0xFFF0E4CC),
  surface: Color(0xFFF7EDDA),
  ink: Color(0xFF3A2D1F),
  ink2: Color(0xFF6B5A45),
  line: Color(0xFFDCCBAE),
  accent: Color(0xFF9A3D1B),
  onAccent: Color(0xFFFFF8EC),
  hl: Color(0xFFE6C9AC),
  scrim: Color(0x6B3A2D1F), // ink × 0.42
);

const darkPalette = Palette(
  name: 'dark',
  brightness: Brightness.dark,
  bg: Color(0xFF16130F),
  surface: Color(0xFF221D18),
  ink: Color(0xFFE8E0D2),
  ink2: Color(0xFFA09584),
  line: Color(0xFF383029),
  accent: Color(0xFFE08A5B),
  onAccent: Color(0xFF16130F),
  hl: Color(0xFF3D2B1F),
  scrim: Color(0x8C000000), // #000 × 0.55
);

Palette paletteFor(ThemeChoice choice, Brightness platform) => switch (choice) {
      ThemeChoice.light => lightPalette,
      ThemeChoice.sepia => sepiaPalette,
      ThemeChoice.dark => darkPalette,
      ThemeChoice.system => platform == Brightness.dark ? darkPalette : lightPalette,
    };

/// Mapping of tokens to Material 3 roles. Roles that the palette lacks are derived from it by blending.
ColorScheme schemeFor(Palette p) {
  final dark = p.brightness == Brightness.dark;
  return ColorScheme(
    brightness: p.brightness,
    primary: p.accent,
    onPrimary: p.onAccent,
    primaryContainer: p.hl,
    onPrimaryContainer: p.ink,
    primaryFixed: p.hl,
    onPrimaryFixed: p.ink,
    secondary: p.accent,
    onSecondary: p.onAccent,
    secondaryContainer: p.hl,
    onSecondaryContainer: p.ink,
    tertiary: p.ink2,
    onTertiary: p.bg,
    tertiaryContainer: Color.lerp(p.surface, p.line, 0.6),
    onTertiaryContainer: p.ink,
    error: dark ? const Color(0xFFF2B8B5) : const Color(0xFFB3261E),
    onError: dark ? const Color(0xFF601410) : const Color(0xFFFFFFFF),
    errorContainer: dark ? const Color(0xFF8C1D18) : const Color(0xFFF9DEDC),
    onErrorContainer: dark ? const Color(0xFFF9DEDC) : const Color(0xFF410E0B),
    surface: p.bg,
    onSurface: p.ink,
    onSurfaceVariant: p.ink2,
    surfaceDim: Color.lerp(p.bg, p.line, 0.5),
    surfaceBright: p.surface,
    surfaceContainerLowest: p.surface,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: Color.lerp(p.surface, p.line, 0.35),
    surfaceContainerHighest: Color.lerp(p.surface, p.line, 0.7),
    outline: Color.lerp(p.ink2, p.line, 0.25),
    outlineVariant: p.line,
    shadow: const Color(0xFF000000),
    scrim: p.scrim,
    inverseSurface: p.ink,
    onInverseSurface: p.bg,
    inversePrimary: dark ? lightPalette.accent : darkPalette.accent,
    surfaceTint: const Color(0x00000000),
  );
}

/// With edge-to-edge, Flutter draws the background. Android must not add its own gray
/// scrim behind the three-button bar; icon brightness follows the selected app theme.
SystemUiOverlayStyle systemBarsFor(Brightness brightness) => SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  statusBarBrightness: brightness,
  statusBarIconBrightness: brightness == Brightness.dark ? Brightness.light : Brightness.dark,
  systemNavigationBarIconBrightness: brightness == Brightness.dark ? Brightness.light : Brightness.dark,
  systemNavigationBarContrastEnforced: false,
  systemStatusBarContrastEnforced: false,
);

ThemeData buildTheme(Palette p) {
  final scheme = schemeFor(p);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: p.brightness,
    fontFamily: 'Roboto',
    // The prototype is viewed in a desktop browser: behavior and density are those of an Android phone.
    platform: TargetPlatform.android,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    scaffoldBackgroundColor: p.bg,
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    appBarTheme: AppBarThemeData(
      systemOverlayStyle: systemBarsFor(p.brightness),
      backgroundColor: p.bg,
      foregroundColor: p.ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      modalBackgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.ink2.withValues(alpha: 0.4),
      modalBarrierColor: p.scrim,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      barrierColor: p.scrim,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.ink2,
      selectedColor: p.ink,
      selectedTileColor: p.hl,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.accent,
      foregroundColor: p.onAccent,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.accent,
      linearTrackColor: p.line,
      circularTrackColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: p.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(color: p.bg, fontSize: 13, fontFamily: 'Roboto'),
    ),
  );
}
