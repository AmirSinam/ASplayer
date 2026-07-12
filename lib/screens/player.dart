import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../audio/player_controller.dart';
import '../data/library_store.dart';
import '../l10n.dart';
import '../lyrics.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/track_sheet.dart';
import '../widgets/waveform_bar.dart';
import 'edit_track.dart';
import 'library.dart';
import 'lyrics_screen.dart';
import 'queue.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with TickerProviderStateMixin {
  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
  static const _sleepMinutes = [15, 30, 45, 60];

  // Drives the slow aura rotation behind the artwork.
  late final AnimationController _aura;

  // Drives the gentle up-and-down float of the artwork.
  late final AnimationController _float;

  // Plays the heart burst when the cover is double-tapped.
  late final AnimationController _heart;

  // Horizontal offset while the user is dragging the cover to change tracks.
  double _dragX = 0;

  // The colour pulled from the current cover — the whole screen tints to it.
  // Starts at tiffany and falls back to it for grey covers.
  Color _tint = accent;
  String? _tintForId;

  // Which heart to flash on the last double-tap (liked vs. unliked).
  IconData _heartIcon = Icons.favorite;

  @override
  void initState() {
    super.initState();
    _aura = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
    _float = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
    _heart = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  }

  @override
  void dispose() {
    _aura.dispose();
    _float.dispose();
    _heart.dispose();
    super.dispose();
  }

  // MARK: - Live cover colour

  /// Pulls a vivid colour out of the cover so the halo, glow and controls can
  /// echo it. Greyscale covers keep the tiffany accent.
  Future<void> _loadTint(Track track) async {
    final path = context.read<LibraryStore>().coverPathOf(track);
    var tint = accent;
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) {
        try {
          final palette = await PaletteGenerator.fromImageProvider(
            FileImage(file),
            size: const Size(72, 72),
            maximumColorCount: 8,
          );
          final picked = palette.vibrantColor?.color ??
              palette.lightVibrantColor?.color ??
              palette.dominantColor?.color;
          if (picked != null) tint = _usableTint(picked);
        } catch (_) {
          // A decode failure just leaves the accent in place.
        }
      }
    }
    if (mounted) setState(() => _tint = tint);
  }

  /// Nudges a raw cover colour into a range that stays visible on both the
  /// near-black and near-white grounds. Near-grey colours aren't worth tinting.
  Color _usableTint(Color raw) {
    final hsl = HSLColor.fromColor(raw);
    if (hsl.saturation < 0.12) return accent;
    return hsl
        .withSaturation(hsl.saturation.clamp(0.4, 0.85))
        .withLightness(hsl.lightness.clamp(0.5, 0.68))
        .toColor();
  }

  /// Readable ink for text/icons sitting on a [_tint] fill.
  Color get _onTint => _tint.computeLuminance() > 0.5 ? onAccent : Colors.white;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final app = context.watch<AppState>();
    final store = context.read<LibraryStore>();
    final player = context.watch<PlayerController>();
    final s = app.s;
    final track = player.current;

    if (track == null) return const Scaffold(body: SizedBox.shrink());

    // Recompute the tint whenever the song changes.
    if (track.id != _tintForId) {
      _tintForId = track.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadTint(track));
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(child: Backdrop(track: track)),
          // A faint wash of the cover colour over the whole screen.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.3,
                    colors: [_tint.withValues(alpha: 0.14), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                children: [
                  _topBar(context, player, s, colors, track),
                  Expanded(child: _artwork(track, player)),
                  if (player.sleepRemaining != null) _sleepBadge(s, player),
                  const SizedBox(height: 6),
                  _currentLine(player, track),
                  _titleRow(track, s, colors, store),
                  const SizedBox(height: 12),
                  _seek(player, s, colors, track),
                  const SizedBox(height: 14),
                  _controls(player, colors),
                  const SizedBox(height: 10),
                  _quickActions(context, player, track, s, colors),
                  _upNextStrip(context, player, s, colors),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - Top bar

  Widget _topBar(BuildContext context, PlayerController player, Strings s,
      AppColors colors, Track track) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.expand_more, color: colors.primaryText),
        ),
        const Spacer(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            EqualizerBars(playing: player.playing, height: 14, color: _tint),
            const SizedBox(width: 8),
            Text(
              s.nowPlaying,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colors.primaryText),
            ),
          ],
        ),
        const Spacer(),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_horiz, color: colors.primaryText),
          onSelected: (value) async {
            switch (value) {
              case 'edit':
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => EditTrackScreen(track: track)));
              case 'queue':
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QueueScreen()),
                );
              case 'speed':
                _showSpeedSheet(context, player, s);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'edit', child: Text(s.editSong)),
            PopupMenuItem(value: 'queue', child: Text(s.queue)),
            PopupMenuItem(value: 'speed', child: Text(s.playbackSpeed)),
          ],
        ),
      ],
    );
  }

  // MARK: - Artwork: floating, swipe-to-change, double-tap to favourite

  void _onDragEnd(PlayerController player, double width) {
    // A third of the way across, or a firm flick, commits to the next/previous.
    final threshold = width * 0.28;
    if (_dragX <= -threshold) {
      player.next();
    } else if (_dragX >= threshold) {
      player.previous();
    }
    setState(() => _dragX = 0);
  }

  void _onDoubleTapCover(Track track) {
    context.read<LibraryStore>().toggleFavorite(track);
    setState(() => _heartIcon = track.favorite ? Icons.favorite : Icons.heart_broken);
    _heart.forward(from: 0);
  }

  Widget _artwork(Track track, PlayerController player) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () => _onDoubleTapCover(track),
                onHorizontalDragUpdate: (d) => setState(() => _dragX += d.delta.dx),
                onHorizontalDragEnd: (_) => _onDragEnd(player, width),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // A soft halo in the cover's colour that slowly turns while a
                    // song plays.
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _aura,
                        builder: (context, child) => Transform.rotate(
                          angle: _aura.value * 2 * pi,
                          child: child,
                        ),
                        child: FractionallySizedBox(
                          widthFactor: 1.06,
                          heightFactor: 1.06,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(R.card + 16),
                              gradient: SweepGradient(
                                colors: [
                                  _tint.withValues(alpha: 0.0),
                                  _tint.withValues(alpha: 0.35),
                                  _tint.withValues(alpha: 0.0),
                                  _tint.withValues(alpha: 0.22),
                                  _tint.withValues(alpha: 0.0),
                                ],
                                stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // The cover: floats up and down, follows the drag, tilts
                    // slightly toward the direction it is being pulled, and
                    // fades as it approaches the commit threshold.
                    AnimatedBuilder(
                      animation: _float,
                      builder: (context, child) {
                        final floatY = sin(_float.value * 2 * pi) * 8;
                        final dragT = (_dragX / width).clamp(-1.0, 1.0);
                        return Transform.translate(
                          offset: Offset(_dragX, floatY),
                          child: Transform.rotate(
                            angle: dragT * 0.08,
                            child: Opacity(opacity: 1 - dragT.abs() * 0.35, child: child),
                          ),
                        );
                      },
                      child: AnimatedScale(
                        scale: player.playing ? 1.0 : 0.94,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOut,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(R.card),
                            boxShadow: [
                              BoxShadow(
                                color: _tint.withValues(alpha: 0.28),
                                blurRadius: 48,
                                spreadRadius: -8,
                                offset: const Offset(0, 16),
                              ),
                            ],
                          ),
                          child: Artwork(track: track, radius: R.card, cacheWidth: 1000),
                        ),
                      ),
                    ),

                    // The heart that pops on a double-tap, then fades away.
                    _heartBurst(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _heartBurst() {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _heart,
        builder: (context, child) {
          if (_heart.isDismissed) return const SizedBox.shrink();
          final t = _heart.value;
          // Pop up quickly, hold, then fade and drift up a touch.
          final scale = t < 0.3 ? Curves.easeOutBack.transform(t / 0.3) : 1.0;
          final opacity = t < 0.6 ? 1.0 : (1 - (t - 0.6) / 0.4);
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.6 + scale * 0.7,
              child: child,
            ),
          );
        },
        child: Icon(
          _heartIcon,
          size: 96,
          color: Colors.white,
          shadows: const [BoxShadow(color: Color(0x66000000), blurRadius: 24)],
        ),
      ),
    );
  }

  // MARK: - Sleep badge

  Widget _sleepBadge(Strings s, PlayerController player) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bedtime, size: 14, color: _tint),
          const SizedBox(width: 6),
          Text(
            s.sleepsIn(formatDuration(player.sleepRemaining!)),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _tint),
          ),
        ],
      ),
    );
  }

  // MARK: - Title + format badge + favourite

  Widget _titleRow(Track track, Strings s, AppColors colors, LibraryStore store) {
    final format = _formatLabel(track);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  if (format != null) ...[
                    const SizedBox(width: 8),
                    _formatBadge(format, colors),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              _artistLabel(track, s, colors),
            ],
          ),
        ),
        _HeartButton(track: track, store: store, tint: _tint),
      ],
    );
  }

  Widget _artistLabel(Track track, Strings s, AppColors colors) {
    final label = Text(
      track.artistName(s),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13.5, color: colors.secondaryText),
    );
    if (track.artist.trim().isEmpty) return label;
    return GestureDetector(
      onTap: () => _openArtist(context, track, s),
      child: label,
    );
  }

  Widget _formatBadge(String format, AppColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _tint.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        format,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _tint),
      ),
    );
  }

  String? _formatLabel(Track track) {
    final name = track.fileName;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return null;
    final ext = name.substring(dot + 1).toUpperCase();
    return ext.length <= 4 ? ext : null;
  }

  void _openArtist(BuildContext context, Track track, Strings s) {
    final names = splitArtists(track.artist);
    if (names.isEmpty) return;
    if (names.length == 1) {
      _pushArtist(context, names.first);
    } else {
      final colors = AppColors.of(context);
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: colors.background,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: names
                .map((name) => ListTile(
                      leading: Icon(Icons.person_outline, color: _tint),
                      title: Text(name, style: TextStyle(color: colors.primaryText)),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pushArtist(context, name);
                      },
                    ))
                .toList(),
          ),
        ),
      );
    }
  }

  void _pushArtist(BuildContext context, String name) {
    final store = context.read<LibraryStore>();
    final lower = name.toLowerCase();
    final tracks = store.tracks
        .where((t) => splitArtists(t.artist).any((a) => a.toLowerCase() == lower))
        .toList();
    if (tracks.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupDetail(title: name, tracks: tracks)),
    );
  }

  // MARK: - Current lyric line (under the cover)

  Widget _currentLine(PlayerController player, Track track) {
    if (!track.hasLyrics) return const SizedBox.shrink();
    final lyrics = Lyrics.parse(track.lyrics);
    if (!lyrics.synced) return const SizedBox.shrink();

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snapshot) {
        final i = lyrics.activeIndex(snapshot.data ?? Duration.zero);
        final text = i >= 0 ? lyrics.lines[i].text : '';
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => LyricsScreen(track: track)),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              text,
              key: ValueKey(text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _tint,
              ),
            ),
          ),
        );
      },
    );
  }

  // MARK: - Moments (bookmarks)

  void _showMoments(BuildContext context, PlayerController player, Track track, Strings s) {
    final store = context.read<LibraryStore>();
    final colors = AppColors.of(context);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.background,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.add_circle, color: _tint),
                title: Text(s.saveMoment),
                onTap: () async {
                  await store.addBookmark(track, player.position.inMilliseconds);
                  setSheet(() {});
                },
              ),
              const Divider(height: 1),
              if (track.bookmarksMs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(s.noMoments, style: TextStyle(color: colors.secondaryText)),
                )
              else
                ...track.bookmarksMs.map((ms) => ListTile(
                      leading: Icon(Icons.bookmark, color: _tint),
                      title: Text(formatDuration(Duration(milliseconds: ms)),
                          style: TextStyle(color: colors.primaryText)),
                      trailing: IconButton(
                        icon: Icon(Icons.close, size: 18, color: colors.secondaryText),
                        onPressed: () async {
                          await store.removeBookmark(track, ms);
                          setSheet(() {});
                        },
                      ),
                      onTap: () {
                        player.seek(Duration(milliseconds: ms));
                        Navigator.pop(sheetContext);
                      },
                    )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: - Waveform seek + speed pill

  Widget _seek(PlayerController player, Strings s, AppColors colors, Track track) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final total = player.duration;
        final progress =
            total.inMilliseconds == 0 ? 0.0 : position.inMilliseconds / total.inMilliseconds;

        return Column(
          children: [
            RepaintBoundary(
              child: WaveformBar(
                seed: track.id.hashCode,
                progress: progress,
                playing: player.playing,
                onSeek: player.seekToFraction,
                color: _tint,
              ),
            ),
            const SizedBox(height: 6),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatDuration(position),
                    style: TextStyle(fontSize: 11.5, color: colors.secondaryText),
                  ),
                  _speedPill(context, player, s),
                  Text(
                    formatDuration(total),
                    style: TextStyle(fontSize: 11.5, color: colors.secondaryText),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _speedPill(BuildContext context, PlayerController player, Strings s) {
    final active = player.speed != 1.0;
    return GestureDetector(
      onTap: () => _showSpeedSheet(context, player, s),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: active ? _tint.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.speed, size: 13, color: active ? _tint : AppColors.of(context).secondaryText),
            const SizedBox(width: 4),
            Text(
              '${player.speed}×',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: active ? _tint : AppColors.of(context).secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - Transport controls

  Widget _controls(PlayerController player, AppColors colors) {
    return Glass(
      radius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: player.toggleShuffle,
            icon: Icon(Icons.shuffle, color: player.shuffle ? _tint : colors.secondaryText),
          ),
          IconButton(
            onPressed: player.previous,
            iconSize: 32,
            icon: Icon(Icons.skip_previous, color: colors.primaryText),
          ),
          GestureDetector(
            onTap: player.toggle,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.4),
                  radius: 1.1,
                  colors: [Color.lerp(_tint, Colors.white, 0.28)!, _tint],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _tint.withValues(alpha: 0.5),
                    blurRadius: 24,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Icon(
                player.playing ? Icons.pause : Icons.play_arrow,
                color: _onTint,
                size: 34,
              ),
            ),
          ),
          IconButton(
            onPressed: player.next,
            iconSize: 32,
            icon: Icon(Icons.skip_next, color: colors.primaryText),
          ),
          IconButton(
            onPressed: player.cycleRepeat,
            icon: Icon(
              player.repeat == Repeat.one ? Icons.repeat_one : Icons.repeat,
              color: player.repeat == Repeat.off ? colors.secondaryText : _tint,
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - Quick actions

  Widget _quickActions(
      BuildContext context, PlayerController player, Track track, Strings s, AppColors colors) {
    Widget action(IconData icon, String label, VoidCallback onTap, {bool active = false}) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 21, color: active ? _tint : colors.secondaryText),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: active ? _tint : colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        action(Icons.lyrics_outlined, s.lyrics, () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => LyricsScreen(track: track)));
        }, active: track.hasLyrics),
        action(Icons.bookmark_outline, s.moments, () => _showMoments(context, player, track, s),
            active: track.bookmarksMs.isNotEmpty),
        action(Icons.playlist_add, s.addToPlaylist, () => showAddToPlaylist(context, track)),
        action(Icons.bedtime_outlined, s.sleepTimer, () => _showSleepSheet(context, player, s),
            active: player.sleepRemaining != null),
        action(Icons.ios_share, s.share, () => _shareTrack(context, track)),
      ],
    );
  }

  void _shareTrack(BuildContext context, Track track) {
    final path = context.read<LibraryStore>().filePathOf(track);
    final file = File(path);
    if (!file.existsSync()) return;
    Share.shareXFiles([XFile(path)], subject: track.title);
  }

  // MARK: - Up next strip

  Widget _upNextStrip(
      BuildContext context, PlayerController player, Strings s, AppColors colors) {
    final upcoming = player.upNext;
    if (upcoming.isEmpty) return const SizedBox.shrink();
    final next = upcoming.first;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const QueueScreen()),
        ),
        child: Glass(
          radius: R.tile,
          elevated: false,
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Artwork(track: next, size: 40, radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.upNext,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: _tint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      next.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.queue_music, size: 20, color: colors.secondaryText),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: - Sheets

  void _showSleepSheet(BuildContext context, PlayerController player, Strings s) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.of(context).background,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._sleepMinutes.map((minutes) => ListTile(
                  leading: Icon(Icons.bedtime_outlined, color: _tint),
                  title: Text(s.minutesLabel(minutes)),
                  onTap: () {
                    player.startSleepTimer(minutes);
                    Navigator.pop(sheetContext);
                  },
                )),
            if (player.sleepRemaining != null)
              ListTile(
                leading: const Icon(Icons.close, color: Colors.redAccent),
                title: Text(s.cancelTimer),
                onTap: () {
                  player.cancelSleepTimer();
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showSpeedSheet(BuildContext context, PlayerController player, Strings s) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.of(context).background,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _speeds
              .map((speed) => ListTile(
                    leading: Icon(
                      player.speed == speed ? Icons.check_circle : Icons.speed,
                      color: _tint,
                    ),
                    title: Text(speed == 1.0 ? s.normalSpeed : '$speed×'),
                    onTap: () {
                      player.setSpeed(speed);
                      Navigator.pop(sheetContext);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _HeartButton extends StatelessWidget {
  const _HeartButton({required this.track, required this.store, required this.tint});

  final Track track;
  final LibraryStore store;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return IconButton(
      onPressed: () => store.toggleFavorite(track),
      iconSize: 26,
      icon: Icon(
        track.favorite ? Icons.favorite : Icons.favorite_border,
        color: track.favorite ? tint : colors.secondaryText,
      ),
    );
  }
}
