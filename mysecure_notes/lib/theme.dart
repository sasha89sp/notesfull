import 'package:flutter/material.dart';

/// Палитра и тема приложения (минималистичный «нативный» стиль, как в Noteplan).
/// Светлая: фон #FAFAF9, сайдбар #F4F4F5, панели #FFFFFF, текст #18181B, акцент индиго #4F46E5.
/// Тёмная: фон #09090B, текст #FAFAFA, разделители #27272A, акцент #818CF8.
class AppColors {
  final Color bg, sidebar, panel, text, text2, muted, divider, accent, hover, checkBorder;
  final Color tagFg, tagBg, linkBg;
  const AppColors({
    required this.bg,
    required this.sidebar,
    required this.panel,
    required this.text,
    required this.text2,
    required this.muted,
    required this.divider,
    required this.accent,
    required this.hover,
    required this.checkBorder,
    required this.tagFg,
    required this.tagBg,
    required this.linkBg,
  });

  static const light = AppColors(
    bg: Color(0xFFFAFAF9),
    sidebar: Color(0xFFF4F4F5),
    panel: Color(0xFFFFFFFF),
    text: Color(0xFF18181B),
    text2: Color(0xFF71717A),
    muted: Color(0xFFA1A1AA),
    divider: Color(0xFFE4E4E7),
    accent: Color(0xFF4F46E5),
    hover: Color(0xFFF4F4F5),
    checkBorder: Color(0xFFD4D4D8),
    tagFg: Color(0xFFD97706),
    tagBg: Color(0xFFFEF3C7),
    linkBg: Color(0xFFEEF2FF),
  );

  static const dark = AppColors(
    bg: Color(0xFF09090B),
    sidebar: Color(0xFF111113),
    panel: Color(0xFF18181B),
    text: Color(0xFFFAFAFA),
    text2: Color(0xFFA1A1AA),
    muted: Color(0xFF71717A),
    divider: Color(0xFF27272A),
    accent: Color(0xFF818CF8),
    hover: Color(0xFF1F1F23),
    checkBorder: Color(0xFF3F3F46),
    tagFg: Color(0xFFFBBF24),
    tagBg: Color(0x33D97706),
    linkBg: Color(0x33818CF8),
  );

  static AppColors of(Brightness b) => b == Brightness.dark ? dark : light;
}

const _fonts = ['SF Pro Text', 'Segoe UI', 'Roboto', 'Helvetica Neue', 'Arial'];

ThemeData buildTheme(Brightness b) {
  final c = AppColors.of(b);
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF4F46E5), brightness: b).copyWith(
    primary: c.accent,
    onPrimary: dark ? const Color(0xFF09090B) : Colors.white,
    surface: c.panel,
    onSurface: c.text,
    outline: c.divider,
    outlineVariant: c.divider,
    surfaceContainerHighest: c.sidebar,
    surfaceTint: Colors.transparent,
  );
  final base = ThemeData(brightness: b, useMaterial3: true);
  final tt = base.textTheme
      .apply(bodyColor: c.text, displayColor: c.text, fontFamily: 'Inter', fontFamilyFallback: _fonts)
      .copyWith(
        titleLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.3),
        titleMedium: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4),
        bodyLarge: const TextStyle(fontSize: 15, height: 1.6),
        bodyMedium: const TextStyle(fontSize: 15, height: 1.5),
        bodySmall: TextStyle(fontSize: 12, height: 1.4, color: c.text2),
        labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      );
  final r8 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.panel,
    fontFamily: 'Inter',
    fontFamilyFallback: _fonts,
    textTheme: tt,
    hoverColor: c.hover,
    highlightColor: Colors.transparent,
    dividerColor: c.divider,
    dividerTheme: DividerThemeData(color: c.divider, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.text, fontFamily: 'Inter', fontFamilyFallback: _fonts),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: c.panel, surfaceTintColor: Colors.transparent),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.sidebar,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.accent.withOpacity(0.14),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12, color: c.text2)),
    ),
    cardTheme: CardThemeData(
      color: c.panel,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: c.divider)),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: WidgetStateBorderSide.resolveWith((s) =>
          s.contains(WidgetState.selected) ? BorderSide.none : BorderSide(width: 1.5, color: c.checkBorder)),
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.accent : Colors.transparent),
      checkColor: const WidgetStatePropertyAll(Colors.white),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.divider)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.divider)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.accent, width: 1.5)),
      hintStyle: TextStyle(color: c.muted),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionColor: c.accent.withOpacity(0.25),
      selectionHandleColor: c.accent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    popupMenuTheme: PopupMenuThemeData(color: c.panel, surfaceTintColor: Colors.transparent, shape: r8),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF27272A) : const Color(0xFF18181B),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: r8,
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: r8, backgroundColor: c.accent, foregroundColor: scheme.onPrimary)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: r8, side: BorderSide(color: c.divider), foregroundColor: c.text)),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.accent, shape: r8)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: c.accent, foregroundColor: scheme.onPrimary, elevation: 2),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStatePropertyAll(c.muted.withOpacity(0.5)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: dark ? const Color(0xFF27272A) : const Color(0xFF18181B), borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  );
}
