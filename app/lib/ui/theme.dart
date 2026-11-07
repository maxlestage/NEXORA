import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Les couleurs de NEXORA.
abstract final class Nx {
  static const cyan = Color(0xFF22D3EE);
  static const violet = Color(0xFF8B5CF6);
  static const magenta = Color(0xFFF472B6);
  static const green = Color(0xFF34D399);
  static const amber = Color(0xFFFBBF24);
  static const red = Color(0xFFF87171);
  static const ink = Color(0xFF07070D);
  static const panel = Color(0xFF10101A);
  static const panel2 = Color(0xFF171726);
  static const line = Color(0x22FFFFFF);

  static const gradient = LinearGradient(
    colors: [cyan, violet, magenta],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const mono = 'monospace';
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Nx.violet,
    brightness: b,
    primary: dark ? Nx.cyan : const Color(0xFF0E7490),
    secondary: Nx.violet,
    tertiary: Nx.magenta,
    surface: dark ? Nx.ink : const Color(0xFFF7F7FB),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: b,
    scaffoldBackgroundColor: dark ? Nx.ink : const Color(0xFFF7F7FB),
    visualDensity: VisualDensity.standard,
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: dark ? Nx.panel : Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: dark ? Nx.line : const Color(0x14000000)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xF00B0B14) : Colors.white,
      indicatorColor: Nx.cyan.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(
        base.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? Nx.panel2 : const Color(0xFFEFEFF6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: dark ? Nx.line : const Color(0x14000000)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? Nx.panel : Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? Nx.panel : Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
