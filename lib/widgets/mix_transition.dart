import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// The on-screen "mixing" overlay shown while an audio crossfade runs. It sits
/// on top of the cover and blends the outgoing artwork into the incoming one,
/// driven by [progress] (0→1, the same ramp the audio uses, so the two stay in
/// step and it freezes automatically when playback pauses).
///
/// Layers, back to front:
///   1. outgoing cover dissolving into blur and scaling up as it leaves
///   2. incoming cover arriving sharp and settling to full size
///   3. a tint wash + glowing rim that peak at the midpoint of the mix
///   4. an equalizer-style wave bridging the two tracks
///   5. a light sweep travelling across as the blend advances
class MixTransition extends StatefulWidget {
  const MixTransition({
    super.key,
    required this.outgoing,
    required this.incoming,
    required this.progress,
    required this.tint,
    this.radius = R.card,
  });

  final Track outgoing;
  final Track incoming;
  final ValueListenable<double> progress;
  final Color tint;
  final double radius;

  @override
  State<MixTransition> createState() => _MixTransitionState();
}

class _MixTransitionState extends State<MixTransition> with SingleTickerProviderStateMixin {
  // A free-running controller for the lively 60fps decoration (bars + shimmer),
  // independent of the audio-synced macro blend.
  late final AnimationController _ambient;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
  }

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(widget.radius);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([widget.progress, _ambient]),
        builder: (context, _) {
          final p = widget.progress.value.clamp(0.0, 1.0);
          final glow = sin(p * pi); // 0 → 1 (mid) → 0
          final phase = _ambient.value;

          return ClipRRect(
            borderRadius: shape,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. outgoing: dissolve into blur, drift up in scale, fade away.
                Opacity(
                  opacity: (1 - Curves.easeIn.transform(p)).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 1 + 0.06 * p,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 12 * p, sigmaY: 12 * p),
                      child: Artwork(track: widget.outgoing, radius: widget.radius, cacheWidth: 800),
                    ),
                  ),
                ),

                // 2. incoming: arrive sharp, settle from slightly small to full.
                Opacity(
                  opacity: Curves.easeOut.transform(p),
                  child: Transform.scale(
                    scale: 0.94 + 0.06 * p,
                    child: Artwork(track: widget.incoming, radius: widget.radius, cacheWidth: 800),
                  ),
                ),

                // 3a. a wash of the cover colour, strongest mid-mix.
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: shape,
                      gradient: RadialGradient(
                        radius: 1.1,
                        colors: [
                          widget.tint.withValues(alpha: 0.30 * glow),
                          widget.tint.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),

                // 3b. a glowing rim that swells at the peak of the blend.
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: shape,
                      border: Border.all(color: widget.tint.withValues(alpha: 0.55 * glow), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: widget.tint.withValues(alpha: 0.45 * glow),
                          blurRadius: 34 * glow,
                          spreadRadius: 2 * glow,
                        ),
                      ],
                    ),
                  ),
                ),

                // 4. an equalizer wave across the seam between the two tracks.
                Center(
                  child: SizedBox(
                    height: 64,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _MixWavePainter(phase: phase, intensity: glow, color: Colors.white),
                    ),
                  ),
                ),

                // 5. a soft light sweep travelling across as the mix advances.
                Align(
                  alignment: Alignment(-1.3 + 2.6 * p, 0),
                  child: FractionallySizedBox(
                    widthFactor: 0.3,
                    heightFactor: 1,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white.withValues(alpha: 0.22 * glow),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A row of rounded bars whose heights ripple with [phase] — a stylised mixer
/// waveform. [intensity] (0→1) scales how tall and how opaque it reads.
class _MixWavePainter extends CustomPainter {
  _MixWavePainter({required this.phase, required this.intensity, required this.color});

  final double phase;
  final double intensity;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0.01) return;
    const count = 18;
    final gap = size.width / count * 0.4;
    final barWidth = size.width / count - gap;
    final mid = size.height / 2;
    final paint = Paint()..color = color.withValues(alpha: 0.55 * intensity);

    for (var i = 0; i < count; i++) {
      final wave = 0.35 + 0.65 * (0.5 + 0.5 * sin(phase * 2 * pi + i * 0.7));
      final h = size.height * wave * intensity;
      final x = i * (barWidth + gap) + gap / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, mid - h / 2, barWidth, h),
        Radius.circular(barWidth),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_MixWavePainter old) =>
      old.phase != phase || old.intensity != intensity;
}
