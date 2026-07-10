import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../audio/player_controller.dart';
import '../data/library_store.dart';
import '../l10n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/track_sheet.dart';
import 'queue.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
  static const _sleepMinutes = [15, 30, 45, 60];

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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.expand_more, color: colors.primaryText),
                      ),
                      const Spacer(),
                      Text(
                        s.nowPlaying,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colors.primaryText,
                        ),
                      ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_horiz, color: colors.primaryText),
                        onSelected: (value) async {
                          switch (value) {
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
                          PopupMenuItem(value: 'queue', child: Text(s.queue)),
                          PopupMenuItem(value: 'playlist', child: Text(s.addToPlaylist)),
                          PopupMenuItem(value: 'sleep', child: Text(s.sleepTimer)),
                          PopupMenuItem(value: 'speed', child: Text(s.playbackSpeed)),
                        ],
                      ),
                    ],
                  ),

                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(R.card),
                              boxShadow: [
                                BoxShadow(color: colors.shadow, blurRadius: 40, offset: const Offset(0, 18)),
                              ],
                            ),
                            child: Artwork(track: track, radius: R.card),
                          ),
                        ),
                      ),
                    ),
                  ),

                  if (player.sleepRemaining != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
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
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                    ),

                  Row(
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
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: colors.primaryText,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              track.artistName(s),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: colors.secondaryText),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => store.toggleFavorite(track),
                        icon: Icon(
                          track.favorite ? Icons.favorite : Icons.favorite_border,
                          color: track.favorite ? accent : colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  StreamBuilder<Duration>(
                    stream: player.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final total = player.duration;
                      final progress = total.inMilliseconds == 0
                          ? 0.0
                          : position.inMilliseconds / total.inMilliseconds;

                      return Column(
                        children: [
                          ScrubBar(progress: progress, onScrub: player.seekToFraction),
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
                                  Text(
                                    '${player.speed}×',
                                    style: const TextStyle(fontSize: 11.5, color: accent),
                                  ),
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
                  ),
                  const SizedBox(height: 6),

                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      children: [
                        Icon(Icons.volume_down, size: 18, color: colors.secondaryText),
                        Expanded(
                          child: ScrubBar(
                            progress: player.volume,
                            onScrub: player.setVolume,
                            thumb: true,
                          ),
                        ),
                        Icon(Icons.volume_up, size: 18, color: colors.secondaryText),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  Glass(
                    radius: 999,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: player.toggleShuffle,
                          icon: Icon(
                            Icons.shuffle,
                            color: player.shuffle ? accent : colors.secondaryText,
                          ),
                        ),
                        IconButton(
                          onPressed: player.previous,
                          iconSize: 30,
                          icon: Icon(Icons.skip_previous, color: colors.primaryText),
                        ),
                        GestureDetector(
                          onTap: player.toggle,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(color: accent, shape: BoxShape.circle),
                            child: Icon(
                              player.playing ? Icons.pause : Icons.play_arrow,
                              color: onAccent,
                              size: 30,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: player.next,
                          iconSize: 30,
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
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

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
