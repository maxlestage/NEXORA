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

  /// Les animations : `full`, `reduced` ou `off` (réglé dans Personnaliser).
  static String motion = 'full';

  static bool get animationsOff => motion == 'off';
  static double get motionSpeed => switch (motion) {
    'off' => 0,
    'reduced' => 0.25,
    _ => 1,
  };

  /// La couleur principale du jeu de couleurs choisi.
  static Color accent(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  /// Le dégradé du jeu de couleurs choisi.
  static LinearGradient gradientOf(BuildContext context) =>
      Theme.of(context).extension<NxPalette>()?.gradient ?? gradient;
}

/// Un jeu de couleurs de l'interface.
class AccentPalette {
  const AccentPalette(this.name, this.colors, this.lightPrimary);

  final String name;

  /// Trois couleurs : la principale, puis celles du dégradé.
  final List<Color> colors;

  /// La couleur principale en thème clair (plus foncée, pour le contraste).
  final Color lightPrimary;
}

const List<AccentPalette> accentPalettes = [
  AccentPalette('Néon', [Nx.cyan, Nx.violet, Nx.magenta], Color(0xFF0E7490)),
  AccentPalette('Océan', [
    Color(0xFF38BDF8),
    Color(0xFF2563EB),
    Color(0xFF14B8A6),
  ], Color(0xFF1D4ED8)),
  AccentPalette('Aurore', [
    Color(0xFF34D399),
    Color(0xFF22D3EE),
    Color(0xFFA78BFA),
  ], Color(0xFF047857)),
  AccentPalette('Coucher de soleil', [
    Color(0xFFFB923C),
    Color(0xFFF43F5E),
    Color(0xFFA855F7),
  ], Color(0xFFC2410C)),
  AccentPalette('Rubis', [
    Color(0xFFF87171),
    Color(0xFFEC4899),
    Color(0xFFF59E0B),
  ], Color(0xFFBE123C)),
  AccentPalette('Forêt', [
    Color(0xFF84CC16),
    Color(0xFF10B981),
    Color(0xFF0EA5E9),
  ], Color(0xFF4D7C0F)),
  AccentPalette('Or', [
    Color(0xFFFBBF24),
    Color(0xFFF97316),
    Color(0xFFFB7185),
  ], Color(0xFFB45309)),
  AccentPalette('Monochrome', [
    Color(0xFFE5E7EB),
    Color(0xFF9CA3AF),
    Color(0xFFF9FAFB),
  ], Color(0xFF374151)),
];

/// Les couleurs NEXORA du thème courant (dégradé du jeu de couleurs).
class NxPalette extends ThemeExtension<NxPalette> {
  const NxPalette(this.colors);

  final List<Color> colors;

  LinearGradient get gradient => LinearGradient(
    colors: colors,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  NxPalette copyWith({List<Color>? colors}) => NxPalette(colors ?? this.colors);

  @override
  NxPalette lerp(NxPalette? other, double t) {
    if (other == null) return this;
    return NxPalette([
      for (var i = 0; i < colors.length; i++)
        Color.lerp(colors[i], other.colors[i], t)!,
    ]);
  }
}

ThemeData buildTheme(Brightness b, {int accent = 0, bool oled = false}) {
  final dark = b == Brightness.dark;
  final pal = accentPalettes[accent.clamp(0, accentPalettes.length - 1)];
  final black = dark && oled;
  final bg = black
      ? Colors.black
      : dark
      ? Nx.ink
      : const Color(0xFFF7F7FB);
  final panel = black ? const Color(0xFF0B0B0F) : Nx.panel;
  final panel2 = black ? const Color(0xFF121218) : Nx.panel2;
  final scheme = ColorScheme.fromSeed(
    seedColor: pal.colors[1],
    brightness: b,
    primary: dark ? pal.colors[0] : pal.lightPrimary,
    secondary: pal.colors[1],
    tertiary: pal.colors[2],
    surface: bg,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: b,
    scaffoldBackgroundColor: bg,
    extensions: [NxPalette(pal.colors)],
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
      color: dark ? panel : Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: dark ? Nx.line : const Color(0x14000000)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xF00B0B14) : Colors.white,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(
        base.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? panel2 : const Color(0xFFEFEFF6),
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
      backgroundColor: dark ? panel : Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? panel : Colors.white,
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
