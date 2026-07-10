import 'package:flutter/material.dart';

/// Tiffany reads well on both grounds, so the accent never changes.
const accent = Color(0xFF0ABAB5);
const onAccent = Color(0xFF03211F);

class AppColors {
  const AppColors({
    required this.background,
    required this.primaryText,
    required this.secondaryText,
    required this.glass,
    required this.rim,
    required this.shadow,
  });

  final Color background;
  final Color primaryText;
  final Color secondaryText;
  final Color glass;
  final Color rim;
  final Color shadow;

  // Glass is a touch more opaque than before: without a live blur softening the
  // background, a stronger fill keeps cards defined and text readable.
  static const dark = AppColors(
    background: Color(0xFF080808),
    primaryText: Colors.white,
    secondaryText: Color(0x8CFFFFFF),
    glass: Color(0x1FFFFFFF),
    rim: Color(0x33FFFFFF),
    shadow: Color(0x80000000),
  );

  static const light = AppColors(
    background: Color(0xFFF2F4F4),
    primaryText: Color(0xFF0B1211),
    secondaryText: Color(0x850B1211),
    glass: Color(0xB3FFFFFF),
    rim: Color(0xFFFFFFFF),
    shadow: Color(0x1F0B1211),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

ThemeData appTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark ? AppColors.dark : AppColors.light;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: colors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
    ),
    splashFactory: InkRipple.splashFactory,
  );
}

/// Radii used across the app.
class R {
  static const card = 30.0;
  static const tile = 22.0;
  static const row = 14.0;
}

/// A frosted surface: a translucent fill with a soft top-light sheen, a
/// specular rim, and an optional drop shadow.
///
/// It deliberately does NOT use a live `BackdropFilter`. A real per-surface blur
/// is one of the most expensive things in Flutter, and the app draws dozens of
/// these at once — that was the main source of jank. The app already sits on a
/// heavily blurred backdrop, so a translucent fill reads as glass on its own.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = R.card,
    this.elevated = true,
    this.padding,
  });

  final Widget child;
  final double radius;
  final bool elevated;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final shape = BorderRadius.circular(radius);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: shape,
        border: Border.all(color: colors.rim, width: 0.9),
        boxShadow: elevated
            ? [BoxShadow(color: colors.shadow, blurRadius: 22, offset: const Offset(0, 10))]
            : const [],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [
                  colors.glass,
                  Color.alphaBlend(Colors.white.withValues(alpha: 0.04), colors.glass),
                ]
              : [
                  Color.alphaBlend(Colors.white.withValues(alpha: 0.30), colors.glass),
                  colors.glass,
                ],
        ),
      ),
      child: child,
    );
  }
}

String formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
