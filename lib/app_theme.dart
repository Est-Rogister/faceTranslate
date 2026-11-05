import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const primary = Color(0xFF5B5FD6);
  static const success = Color(0xFF087F5B);

  static ThemeData get light => _build(
    brightness: Brightness.light,
    background: const Color(0xFFF9FAFB),
    surface: Colors.white,
    surfaceSoft: const Color(0xFFF1F3F8),
    ink: const Color(0xFF171A25),
    muted: const Color(0xFF5F6678),
    border: const Color(0xFFDFE3EC),
    primaryColor: primary,
    error: const Color(0xFFC93434),
  );

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    background: const Color(0xFF1F2937),
    surface: const Color(0xFF273345),
    surfaceSoft: const Color(0xFF303D50),
    ink: const Color(0xFFF5F7FB),
    muted: const Color(0xFFC1C8D4),
    border: const Color(0xFF465367),
    primaryColor: const Color(0xFF8588F3),
    error: const Color(0xFFFF8585),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceSoft,
    required Color ink,
    required Color muted,
    required Color border,
    required Color primaryColor,
    required Color error,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primaryColor,
      onPrimary: Colors.white,
      secondary: success,
      onSecondary: Colors.white,
      error: error,
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
      surfaceContainer: surfaceSoft,
      onSurfaceVariant: muted,
      outline: border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      splashFactory: InkSparkle.splashFactory,
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
        fontFamily: 'sans-serif',
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brightness == Brightness.light
            ? const Color(0xFF252938)
            : Colors.white,
        contentTextStyle: TextStyle(
          color: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF171A25),
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

abstract final class AppTone {
  static Color success(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
      ? const Color(0xFF087F5B)
      : const Color(0xFF58D8AD);

  static Color successSoft(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
      ? const Color(0xFFE5F7F0)
      : const Color(0xFF254B43);

  static Color warning(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
      ? const Color(0xFFA95B00)
      : const Color(0xFFFFC067);

  static Color primarySoft(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
      ? const Color(0xFFECECFF)
      : const Color(0xFF383B68);
}
