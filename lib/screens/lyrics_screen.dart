import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../audio/player_controller.dart';
import '../l10n.dart';
import '../lyrics.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'edit_track.dart';

class LyricsScreen extends StatefulWidget {
  const LyricsScreen({super.key, required this.track});

  final Track track;

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  final _scroll = ScrollController();
  int _active = -1;

  // Row height estimate for centring the active line.
  static const _rowExtent = 46.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _centre(int index, int count) {
    if (!_scroll.hasClients) return;
    final target = (index * _rowExtent) - (_scroll.position.viewportDimension / 2) + _rowExtent / 2;
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final app = context.watch<AppState>();
    final player = context.watch<PlayerController>();
    final s = app.s;

    final lyrics = Lyrics.parse(widget.track.lyrics);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(s.lyrics),
        backgroundColor: Colors.transparent,
        foregroundColor: colors.primaryText,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => EditTrackScreen(track: widget.track)),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Backdrop(track: widget.track)),
          SafeArea(
            child: lyrics.isEmpty
                ? _empty(s, colors)
                : lyrics.synced
                    ? _synced(lyrics, player, colors)
                    : _plain(lyrics, colors),
          ),
        ],
      ),
    );
  }

  Widget _empty(Strings s, AppColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lyrics_outlined, size: 40, color: colors.secondaryText),
          const SizedBox(height: 12),
          Text(s.noLyrics, style: TextStyle(color: colors.primaryText, fontSize: 16)),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => EditTrackScreen(track: widget.track)),
            ),
            style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: onAccent),
            child: Text(s.editLyrics),
          ),
        ],
      ),
    );
  }

  Widget _synced(Lyrics lyrics, PlayerController player, AppColors colors) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? Duration.zero;
        final active = lyrics.activeIndex(pos);
        if (active != _active && active >= 0) {
          _active = active;
          WidgetsBinding.instance.addPostFrameCallback((_) => _centre(active, lyrics.lines.length));
        }

        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 60),
          itemCount: lyrics.lines.length,
          itemExtent: _rowExtent,
          itemBuilder: (context, i) {
            final line = lyrics.lines[i];
            final isActive = i == active;
            return GestureDetector(
              onTap: line.time == null ? null : () => player.seek(line.time!),
              child: Center(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: TextStyle(
                    fontSize: isActive ? 19 : 15.5,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                    color: isActive ? accent : colors.secondaryText,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                  child: Text(line.text, textAlign: TextAlign.center, maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _plain(Lyrics lyrics, AppColors colors) {
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 60),
      children: lyrics.lines
          .map((l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text(
                  l.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, height: 1.5, color: colors.primaryText),
                ),
              ))
          .toList(),
    );
  }
}
