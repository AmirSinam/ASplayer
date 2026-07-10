import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/library_store.dart';
import '../theme.dart';
import '../widgets/common.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final app = context.watch<AppState>();
    final store = context.watch<LibraryStore>();
    final s = app.s;

    // Uses the four newest covers when the library has them, gradients otherwise.
    final covers = store.tracks.take(4).toList();
    Widget tile(int index, double height) => SizedBox(
          height: height,
          child: Artwork(
            track: index < covers.length ? covers[index] : null,
            radius: R.tile,
          ),
        );

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 48, 12, 0),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: tile(0, 190)),
                    const SizedBox(width: 10),
                    Expanded(child: tile(1, 226)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: tile(2, 218)),
                    const SizedBox(width: 10),
                    Expanded(child: tile(3, 180)),
                  ],
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.3, 0.62, 0.8],
                colors: [
                  Colors.transparent,
                  colors.background.withValues(alpha: 0.85),
                  colors.background,
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 0, 26, 44),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.onboardLine1,
                    style: TextStyle(
                      fontSize: 33,
                      height: 1.28,
                      fontWeight: FontWeight.w800,
                      color: colors.primaryText,
                    ),
                  ),
                  Text(
                    s.onboardLine2,
                    style: const TextStyle(
                      fontSize: 33,
                      height: 1.28,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    s.onboardBody,
                    style: TextStyle(fontSize: 13.5, height: 1.8, color: colors.secondaryText),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: app.finishOnboarding,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: onAccent,
                        padding: const EdgeInsets.symmetric(vertical: 17),
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        s.start,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
