import 'dart:ui';

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

  static const dark = AppColors(
    background: Color(0xFF080808),
    primaryText: Colors.white,
    secondaryText: Color(0x8CFFFFFF),
    glass: Color(0x12FFFFFF),
    rim: Color(0x2EFFFFFF),
    shadow: Color(0x80000000),
  );

  static const light = AppColors(
    background: Color(0xFFF2F4F4),
    primaryText: Color(0xFF0B1211),
    secondaryText: Color(0x850B1211),
    glass: Color(0x99FFFFFF),
    rim: Color(0xE6FFFFFF),
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

/// Material, a tint with some body, a specular rim, and a soft drop shadow.
/// Every raised surface in the app sits on this.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = R.card,
    this.elevated = true,
    this.padding,
    this.blur = 24,
  });

  final Widget child;
  final double radius;
  final bool elevated;
  final EdgeInsets? padding;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final shape = BorderRadius.circular(radius);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: elevated
            ? [BoxShadow(color: colors.shadow, blurRadius: 24, offset: const Offset(0, 10))]
            : const [],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: colors.glass,
              borderRadius: shape,
              border: Border.all(color: colors.rim, width: 0.9),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

String formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
