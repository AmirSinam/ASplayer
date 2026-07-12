import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/library_store.dart';
import '../models.dart';
import '../theme.dart';
import 'import_device_button.dart';

class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.track,
    this.radius = R.row,
    this.size,
    this.cacheWidth,
  });

  final Track? track;
  final double radius;
  final double? size;

  /// Overrides the decode width. When null it is derived from [size]; a null
  /// result (no size given) decodes at full resolution — reserve that for the
  /// one big player cover, never for list thumbnails.
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    final path = track == null ? null : store.coverPathOf(track!);

    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.35), accent.withValues(alpha: 0.08)],
        ),
      ),
      child: const Center(child: Icon(Icons.music_note, color: accent, size: 20)),
    );

    Widget child;
    if (path == null) {
      child = fallback;
    } else {
      // Decode the cover only as large as it is shown. A full-resolution album
      // art scaled into a 48px tile burns memory and decode time and was the main
      // source of list jank. A missing file falls back via errorBuilder, which
      // also drops the synchronous existsSync() that used to run every build.
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final decodeWidth = cacheWidth ?? (size != null ? (size! * dpr).round() : null);
      child = Image.file(
        File(path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        cacheWidth: decodeWidth,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}

/// The blurred cover behind everything. Glass needs something to refract.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.track});

  final Track? track;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final store = context.read<LibraryStore>();
    final path = track == null ? null : store.coverPathOf(track!);
    final file = path == null ? null : File(path);

    if (file == null || !file.existsSync()) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.2,
            colors: [accent.withValues(alpha: 0.18), colors.background],
          ),
        ),
        child: const SizedBox.expand(),
      );
    }

    // Decode the cover tiny, then let BoxFit stretch it — a 32px image scaled to
    // full screen is already a smooth blur, so the expensive large-sigma filter
    // isn't needed. RepaintBoundary keeps it off the per-frame repaint path.
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: colors.background),
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Opacity(
              opacity: Theme.of(context).brightness == Brightness.dark ? 0.5 : 0.3,
              child: Image.file(
                file,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: 32,
                filterQuality: FilterQuality.low,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GlassChip extends StatelessWidget {
  const GlassChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: selected ? onAccent : colors.secondaryText,
        ),
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: selected
          ? DecoratedBox(
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(999)),
              child: text,
            )
          : Glass(radius: 999, elevated: false, child: text),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.onMore});

  final String title;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: colors.primaryText),
        ),
        const Spacer(),
        if (onMore != null)
          IconButton(
            onPressed: onMore,
            icon: Icon(Icons.chevron_right, size: 20, color: colors.secondaryText),
          ),
      ],
    );
  }
}

class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.isCurrent,
    this.onFavorite,
    this.trailing,
  });

  final Track track;
  final bool isCurrent;
  final VoidCallback? onFavorite;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final s = context.watch<AppState>().s;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Artwork(track: track, size: 48),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: isCurrent ? accent : colors.primaryText,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  track.artistName(s),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: colors.secondaryText),
                ),
              ],
            ),
          ),
          if (onFavorite != null)
            IconButton(
              onPressed: onFavorite,
              icon: Icon(
                track.favorite ? Icons.favorite : Icons.favorite_border,
                size: 18,
                color: track.favorite ? accent : colors.secondaryText,
              ),
            ),
          if (trailing != null)
            trailing!
          else
            Text(
              formatDuration(track.duration),
              style: TextStyle(fontSize: 12.5, color: colors.secondaryText),
            ),
        ],
      ),
    );
  }
}

class SongCard extends StatelessWidget {
  const SongCard({super.key, required this.track, this.width = 148});

  final Track track;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;

    return SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: 0.78,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(R.tile),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Artwork(track: track, radius: R.tile, cacheWidth: 450),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xCC000000)],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artistName(s),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Color(0xA8FFFFFF)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Forced left-to-right: in Persian the app runs right-to-left, but a drag's
/// local x is always measured from the physical left edge.
class ScrubBar extends StatelessWidget {
  const ScrubBar({super.key, required this.progress, required this.onScrub, this.thumb = true});

  final double progress;
  final ValueChanged<double> onScrub;
  final bool thumb;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          void handle(Offset local) => onScrub((local.dx / width).clamp(0.0, 1.0));

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => handle(d.localPosition),
            onHorizontalDragUpdate: (d) => handle(d.localPosition),
            child: SizedBox(
              height: 24,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: colors.secondaryText.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Container(
                    height: 3,
                    width: width * progress.clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  if (thumb)
                    Positioned(
                      left: (width * progress.clamp(0.0, 1.0)) - 6,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Color(0x55000000), blurRadius: 4)],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class EmptyLibrary extends StatelessWidget {
  const EmptyLibrary({super.key, required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final s = context.watch<AppState>().s;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50),
      child: Column(
        children: [
          const Icon(Icons.download_outlined, size: 40, color: accent),
          const SizedBox(height: 14),
          Text(
            s.emptyTitle,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: colors.primaryText),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              s.emptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colors.secondaryText),
            ),
          ),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: const ImportDeviceButton(),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: onImport,
            style: TextButton.styleFrom(foregroundColor: colors.secondaryText),
            child: Text(s.importFromFiles),
          ),
        ],
      ),
    );
  }
}

/// A tiny animated equalizer — a few bars bobbing when a song is playing,
/// frozen flat when paused. Purely decorative.
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({
    super.key,
    required this.playing,
    this.color = accent,
    this.barCount = 4,
    this.height = 16,
  });

  final bool playing;
  final Color color;
  final int barCount;
  final double height;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _sync();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) _sync();
  }

  void _sync() => widget.playing ? _c.repeat() : _c.stop();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(widget.barCount, (i) {
            final phase = i / widget.barCount;
            final t = widget.playing
                ? (0.35 + 0.65 * (0.5 + 0.5 * sin((_c.value + phase) * 2 * pi)))
                : 0.35;
            return Container(
              width: 3,
              height: widget.height * t,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ),
    );
  }
}
