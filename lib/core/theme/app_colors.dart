import 'package:flutter/material.dart';

/// Color tokens from `design.md` §6.
///
/// Do not use raw hex values in widgets; go through [AppTheme] or
/// [StatusColors] so light/dark stay in sync.
abstract final class AppColors {
  // Brand — indigo
  static const Color indigoLight = Color(0xFF4F46E5);
  static const Color indigoDark = Color(0xFFA5B4FC);

  // Light neutrals
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF1F5F9);
  static const Color lightOutline = Color(0xFFE2E8F0);
  static const Color lightOnSurface = Color(0xFF0F172A);
  static const Color lightOnSurfaceVariant = Color(0xFF475569);

  // Dark neutrals
  static const Color darkBackground = Color(0xFF0B0E14);
  static const Color darkSurface = Color(0xFF12151C);
  static const Color darkSurfaceVariant = Color(0xFF1B1F27);
  static const Color darkOutline = Color(0xFF2A2F3A);
  static const Color darkOnSurface = Color(0xFFE6E9EF);
  static const Color darkOnSurfaceVariant = Color(0xFF9AA3B2);

  // Semantic (light)
  static const Color successLight = Color(0xFF16A34A);
  static const Color warningLight = Color(0xFFB45309);
  static const Color errorLight = Color(0xFFDC2626);
  static const Color infoLight = Color(0xFF0284C7);

  // Semantic (dark)
  static const Color successDark = Color(0xFF4ADE80);
  static const Color warningDark = Color(0xFFFBBF24);
  static const Color errorDark = Color(0xFFF87171);
  static const Color infoDark = Color(0xFF38BDF8);

  /// The PDF page is always rendered on white and must never be tinted.
  static const Color pdfPage = Color(0xFFFFFFFF);
}

/// Semantic colors that Material's [ColorScheme] does not model.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.success,
    required this.warning,
    required this.info,
    required this.successContainer,
    required this.warningContainer,
  });

  final Color success;
  final Color warning;
  final Color info;
  final Color successContainer;
  final Color warningContainer;

  static const StatusColors light = StatusColors(
    success: AppColors.successLight,
    warning: AppColors.warningLight,
    info: AppColors.infoLight,
    successContainer: Color(0xFFDCFCE7),
    warningContainer: Color(0xFFFEF3C7),
  );

  static const StatusColors dark = StatusColors(
    success: AppColors.successDark,
    warning: AppColors.warningDark,
    info: AppColors.infoDark,
    successContainer: Color(0xFF14351F),
    warningContainer: Color(0xFF3A2E10),
  );

  @override
  StatusColors copyWith({
    Color? success,
    Color? warning,
    Color? info,
    Color? successContainer,
    Color? warningContainer,
  }) {
    return StatusColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      successContainer: successContainer ?? this.successContainer,
      warningContainer: warningContainer ?? this.warningContainer,
    );
  }

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
    );
  }
}
