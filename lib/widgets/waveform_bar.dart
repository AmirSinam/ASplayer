import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// A waveform-style seek bar. The bars are derived from a seed so a given song
/// always looks the same, the played portion fills with the accent, and while
/// playing the bars breathe subtly. Drag or tap anywhere to seek.
///
/// These are decorative heights, not real audio peaks — reading sample data is
/// a heavier job left for later.
class WaveformBar extends StatefulWidget {
  const WaveformBar({
    super.key,
    required this.seed,
    required this.progress,
    required this.playing,
    required this.onSeek,
    this.height = 48,
    this.barCount = 56,
  });

  final int seed;
  final double progress;
  final bool playing;
  final ValueChanged<double> onSeek;
  final double height;
  final int barCount;

  @override
  State<WaveformBar> createState() => _WaveformBarState();
}

class _WaveformBarState extends State<WaveformBar> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final List<double> _heights;

  @override
  void initState() {
    super.initState();
    _heights = _buildHeights(widget.seed, widget.barCount);
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _syncPulse();
  }

  @override
  void didUpdateWidget(WaveformBar old) {
    super.didUpdateWidget(old);
    if (old.seed != widget.seed) {
      _heights
        ..clear()
        ..addAll(_buildHeights(widget.seed, widget.barCount));
    }
    if (old.playing != widget.playing) _syncPulse();
  }

  void _syncPulse() {
    if (widget.playing) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
  }

  /// Deterministic 0.18–1.0 heights, mildly eased so the row reads as a wave
  /// rather than noise.
  static List<double> _buildHeights(int seed, int count) {
    final random = Random(seed);
    return List.generate(count, (i) {
      final base = 0.18 + random.nextDouble() * 0.82;
      final swell = 0.5 + 0.5 * sin(i / count * pi);
      return (base * 0.6 + swell * 0.4).clamp(0.14, 1.0);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          void seek(Offset local) => widget.onSeek((local.dx / width).clamp(0.0, 1.0));

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => seek(d.localPosition),
            onHorizontalDragUpdate: (d) => seek(d.localPosition),
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => CustomPaint(
                size: Size(width, widget.height),
                painter: _WaveformPainter(
                  heights: _heights,
                  progress: widget.progress.clamp(0.0, 1.0),
                  pulse: widget.playing ? _pulse.value : 0,
                  playedColor: accent,
                  restColor: colors.secondaryText.withValues(alpha: 0.30),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.heights,
    required this.progress,
    required this.pulse,
    required this.playedColor,
    required this.restColor,
  });

  final List<double> heights;
  final double progress;
  final double pulse;
  final Color playedColor;
  final Color restColor;

  @override
  void paint(Canvas canvas, Size size) {
    final count = heights.length;
    final gap = size.width / count * 0.42;
    final barWidth = size.width / count - gap;
    final mid = size.height / 2;
    final playedBars = progress * count;

    for (var i = 0; i < count; i++) {
      final played = i < playedBars;

      // Played bars nearest the playhead breathe the most; the rest sit still.
      final nearHead = played ? (1 - (playedBars - i).clamp(0, 6) / 6) : 0;
      final breathe = 1 + pulse * 0.22 * nearHead;

      final h = (size.height * heights[i] * breathe).clamp(3.0, size.height);
      final x = i * (barWidth + gap) + gap / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, mid - h / 2, barWidth, h),
        Radius.circular(barWidth),
      );

      canvas.drawRRect(rect, Paint()..color = played ? playedColor : restColor);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || old.pulse != pulse;
}
