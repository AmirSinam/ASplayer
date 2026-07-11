import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  // Horizontal offset while the user is dragging the cover to change tracks.
  double _dragX = 0;

  @override
  void initState() {
    super.initState();
    _aura = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
    _float = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _aura.dispose();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final app = context.watch<AppState>();
    final store = context.read<LibraryStore>();
    final player = context.watch<PlayerController>();
    final s = app.s;
    final track = player.current;

    if (track == null) return const Scaffold(body: SizedBox.shrink());

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(child: Backdrop(track: track)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  _topBar(context, player, s, colors, track),
                  Expanded(child: _artwork(track, player)),
                  if (player.sleepRemaining != null) _sleepBadge(s, player),
                  const SizedBox(height: 6),
                  _currentLine(player, track),
                  _titleRow(track, s, colors, store),
                  const SizedBox(height: 14),
                  _seek(player, s, colors, track),
                  const SizedBox(height: 18),
                  _controls(player, colors),
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
            EqualizerBars(playing: player.playing, height: 14),
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
              case 'lyrics':
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => LyricsScreen(track: track)));
              case 'moments':
                _showMoments(context, player, track, s);
              case 'edit':
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => EditTrackScreen(track: track)));
              case 'queue':
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QueueScreen()),
                );
              case 'playlist':
                showAddToPlaylist(context, track);
              case 'sleep':
                _showSleepSheet(context, player, s);
              case 'speed':
                _showSpeedSheet(context, player, s);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'lyrics', child: Text(s.lyrics)),
            PopupMenuItem(value: 'moments', child: Text(s.moments)),
            PopupMenuItem(value: 'edit', child: Text(s.editSong)),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'queue', child: Text(s.queue)),
            PopupMenuItem(value: 'playlist', child: Text(s.addToPlaylist)),
            PopupMenuItem(value: 'sleep', child: Text(s.sleepTimer)),
            PopupMenuItem(value: 'speed', child: Text(s.playbackSpeed)),
          ],
        ),
      ],
    );
  }

  // MARK: - Artwork: floating, with swipe-to-change

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

  Widget _artwork(Track track, PlayerController player) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) => setState(() => _dragX += d.delta.dx),
                onHorizontalDragEnd: (_) => _onDragEnd(player, width),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // A soft tiffany halo that slowly turns while a song plays.
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
                                accent.withValues(alpha: 0.0),
                                accent.withValues(alpha: 0.35),
                                accent.withValues(alpha: 0.0),
                                accent.withValues(alpha: 0.22),
                                accent.withValues(alpha: 0.0),
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
                                color: accent.withValues(alpha: 0.28),
                                blurRadius: 48,
                                spreadRadius: -8,
                                offset: const Offset(0, 16),
                              ),
                            ],
                          ),
                          child: Artwork(track: track, radius: R.card),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
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
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bedtime, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            s.sleepsIn(formatDuration(player.sleepRemaining!)),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent),
          ),
        ],
      ),
    );
  }

  // MARK: - Title + favourite

  Widget _titleRow(Track track, Strings s, AppColors colors, LibraryStore store) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                track.artistName(s),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: colors.secondaryText),
              ),
            ],
          ),
        ),
        _HeartButton(track: track, store: store),
      ],
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
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: accent,
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
                leading: const Icon(Icons.add_circle, color: accent),
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
                      leading: const Icon(Icons.bookmark, color: accent),
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

  // MARK: - Waveform seek

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
                  if (player.speed != 1)
                    Text('${player.speed}×',
                        style: const TextStyle(fontSize: 11.5, color: accent)),
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
            icon: Icon(Icons.shuffle, color: player.shuffle ? accent : colors.secondaryText),
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
                gradient: const RadialGradient(
                  center: Alignment(-0.3, -0.4),
                  radius: 1.1,
                  colors: [Color(0xFF3FE0DA), accent],
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.5),
                    blurRadius: 24,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Icon(
                player.playing ? Icons.pause : Icons.play_arrow,
                color: onAccent,
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
              color: player.repeat == Repeat.off ? colors.secondaryText : accent,
            ),
          ),
        ],
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
                  leading: const Icon(Icons.bedtime_outlined, color: accent),
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
                      color: accent,
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
  const _HeartButton({required this.track, required this.store});

  final Track track;
  final LibraryStore store;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return IconButton(
      onPressed: () => store.toggleFavorite(track),
      iconSize: 26,
      icon: Icon(
        track.favorite ? Icons.favorite : Icons.favorite_border,
        color: track.favorite ? accent : colors.secondaryText,
      ),
    );
  }
}
