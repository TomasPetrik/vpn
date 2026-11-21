import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cyber_shield_colors.dart';

abstract final class CyberShieldTheme {
  static const String _inter = 'Inter';
  static const String _mono = 'JetBrainsMono';

  static ThemeData dark() {
    final base = ThemeData.dark().textTheme;
    final inter = base.apply(
      fontFamily: _inter,
      bodyColor: CyberShieldColors.onSurface,
      displayColor: CyberShieldColors.onSurface,
    );
    final colorScheme = const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: CyberShieldColors.primary,
      onPrimary: CyberShieldColors.onPrimary,
      primaryContainer: CyberShieldColors.primaryContainer,
      onPrimaryContainer: CyberShieldColors.onPrimaryContainer,
      secondary: CyberShieldColors.secondary,
      onSecondary: Color(0xFF003739),
      secondaryContainer: CyberShieldColors.secondaryContainer,
      onSecondaryContainer: CyberShieldColors.onSecondaryContainer,
      tertiary: CyberShieldColors.tertiary,
      onTertiary: Color(0xFF003824),
      tertiaryContainer: CyberShieldColors.tertiaryContainer,
      onTertiaryContainer: CyberShieldColors.onTertiaryContainer,
      error: CyberShieldColors.error,
      onError: CyberShieldColors.onError,
      errorContainer: CyberShieldColors.errorContainer,
      onErrorContainer: Color(0xFFFFDAD6),
      surface: CyberShieldColors.surface,
      onSurface: CyberShieldColors.onSurface,
      onSurfaceVariant: CyberShieldColors.onSurfaceVariant,
      outline: CyberShieldColors.outline,
      outlineVariant: CyberShieldColors.outlineVariant,
      surfaceContainerLowest: CyberShieldColors.surfaceContainerLowest,
      surfaceContainerLow: CyberShieldColors.surfaceContainerLow,
      surfaceContainer: CyberShieldColors.surfaceContainer,
      surfaceContainerHigh: CyberShieldColors.surfaceContainerHigh,
      surfaceContainerHighest: CyberShieldColors.surfaceContainerHighest,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      fontFamily: _inter,
      scaffoldBackgroundColor: CyberShieldColors.background,
      canvasColor: CyberShieldColors.background,
      textTheme: inter,
      appBarTheme: AppBarTheme(
        backgroundColor: CyberShieldColors.surfaceContainerLowest.withValues(
          alpha: 0.8,
        ),
        foregroundColor: CyberShieldColors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: const TextStyle(
          fontFamily: _inter,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.01 * 18,
          color: CyberShieldColors.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: CyberShieldColors.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CyberShieldColors.primaryContainer,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: _inter,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: CyberShieldColors.surfaceContainerHigh,
        contentTextStyle: TextStyle(
          fontFamily: _inter,
          color: CyberShieldColors.onSurface,
        ),
      ),
      dividerColor: CyberShieldColors.outlineVariant.withValues(alpha: 0.4),
    );
  }

  static TextStyle labelBadge({Color? color}) => TextStyle(
        fontFamily: _inter,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        height: 14 / 11,
        letterSpacing: 0.06 * 11,
        color: color ?? CyberShieldColors.onSurfaceVariant,
      );

  static TextStyle labelCode({Color? color, FontWeight? weight}) => TextStyle(
        fontFamily: _mono,
        fontSize: 13,
        fontWeight: weight ?? FontWeight.w500,
        height: 18 / 13,
        letterSpacing: 0.02 * 13,
        color: color ?? CyberShieldColors.onSurfaceVariant,
      );

  static TextStyle metricStat({Color? color}) => TextStyle(
        fontFamily: _mono,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 32 / 28,
        letterSpacing: -0.02 * 28,
        color: color ?? CyberShieldColors.onSurface,
      );

  static TextStyle headlineSm({Color? color}) => TextStyle(
        fontFamily: _inter,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 24 / 18,
        letterSpacing: -0.01 * 18,
        color: color ?? CyberShieldColors.onSurface,
      );

  static TextStyle bodySm({Color? color}) => TextStyle(
        fontFamily: _inter,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 16 / 12,
        letterSpacing: 0.01 * 12,
        color: color ?? CyberShieldColors.onSurfaceVariant,
      );
}
