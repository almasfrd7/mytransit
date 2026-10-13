import 'package:flutter/material.dart';

/// App-wide theme selection: written by the Settings screen, read by MyApp.
final ValueNotifier<ThemeMode> themeModeNotifier =
ValueNotifier<ThemeMode>(ThemeMode.system);

/// Semantic status colours.
class Tone {
  static const ok = Color(0xFF16A34A);
  static const info = Color(0xFF0EA5E9);
  static const warn = Color(0xFFF59E0B);
  static const bad = Color(0xFFDC2626);
  static const idle = Color(0xFF64748B);
}

class Brand {
  static const indigo = Color(0xFF4F46E5);
  static const violet = Color(0xFF8B5CF6);
  static const teal = Color(0xFF0D9488);
  static const mint = Color(0xFF2DD4BF);
  static const amber = Color(0xFFF59E0B);
  static const orange = Color(0xFFFB923C);

  static bool isDark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static List<Color> heroColors(BuildContext c) => isDark(c)
      ? const [Color(0xFF312E81), Color(0xFF581C87)]
      : const [Color(0xFF4F46E5), Color(0xFF8B5CF6)];

  static Color card(BuildContext c) =>
      isDark(c) ? const Color(0xFF151B2B) : Colors.white;

  static Color background(Brightness b) => b == Brightness.dark
      ? const Color(0xFF0B0F1A)
      : const Color(0xFFF4F5FB);
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.indigo,
    brightness: brightness,
  );
  final bg = Brand.background(brightness);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
  );
  final t = base.textTheme;

  return base.copyWith(
    scaffoldBackgroundColor: bg,
    textTheme: t.copyWith(
      headlineMedium: t.headlineMedium
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineSmall: t.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: dark ? const Color(0xFF1C2338) : const Color(0xFFE9EAF6),
      selectedColor: scheme.primaryContainer,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: WidgetStatePropertyAll(
          dark ? const Color(0xFF151B2B) : Colors.white),
      elevation: const WidgetStatePropertyAll(0),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      )),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 1,
    ),
  );
}