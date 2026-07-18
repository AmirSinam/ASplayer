import 'package:flutter/material.dart';

import '../theme.dart';

/// The four intents an in-app notice can carry. Each maps to one accent colour
/// and icon so notices read consistently across the app.
enum SnackKind { success, error, warning, info }

/// Shows an in-app notice styled to the current theme (light/dark), replacing
/// Flutter's default SnackBar look. One accent per [kind], a glassy themed
/// surface, a leading icon badge, rounded corners and a soft shadow.
///
/// Kept as a single entry point so every notice in the app is consistent and
/// automatically follows a theme change.
void showAppSnack(
  BuildContext context,
  String message, {
  SnackKind kind = SnackKind.info,
  IconData? icon,
  Duration duration = const Duration(seconds: 3),
}) {
  final colors = AppColors.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;

  final (accentColor, kindIcon) = switch (kind) {
    SnackKind.success => (accent, Icons.check_circle_rounded),
    SnackKind.error => (const Color(0xFFE5484D), Icons.error_rounded),
    SnackKind.warning => (const Color(0xFFF5A623), Icons.warning_amber_rounded),
    SnackKind.info => (accent, Icons.info_rounded),
  };

  // A solid, theme-aware surface — a touch tinted toward the accent so it feels
  // part of the app rather than a stock toast. Text stays high-contrast.
  final surface = dark
      ? Color.alphaBlend(accentColor.withValues(alpha: 0.10), const Color(0xFF10191A))
      : Color.alphaBlend(accentColor.withValues(alpha: 0.06), Colors.white);

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      duration: duration,
      padding: EdgeInsets.zero,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.45 : 0.14),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon ?? kindIcon, color: accentColor, size: 18),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                message,
                style: TextStyle(
                  color: colors.primaryText,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
