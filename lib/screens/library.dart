import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../audio/player_controller.dart';
import '../data/importer.dart';
import '../data/library_store.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/track_sheet.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  LibrarySection _section = LibrarySection.songs;
  SortOption _sort = SortOption.dateAdded;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final app = context.watch<AppState>();
    final store = context.watch<LibraryStore>();
    final s = app.s;

    final tracks = store.tracks;
    final sorted = _sort.apply(tracks);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 170),
        children: [
          Row(
            children: [
              Text(
                s.library,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
              const Spacer(),
              if (_section == LibrarySection.songs && tracks.isNotEmpty)
                PopupMenuButton<SortOption>(
                  tooltip: s.sortBy,
                  icon: Icon(Icons.swap_vert, color: colors.primaryText),
                  onSelected: (value) => setState(() => _sort = value),
                  itemBuilder: (context) => SortOption.values
                      .map((o) => PopupMenuItem(value: o, child: Text(o.label(s))))
                      .toList(),
                ),
              GestureDetector(
                onTap: () => context.read<Importer>().pickAndImport(),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: const Icon(Icons.add, color: onAccent, size: 21),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: LibrarySection.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final item = LibrarySection.values[index];
                return GlassChip(
                  label: item.title(s),
                  selected: _section == item,
                  onTap: () => setState(() => _section = item),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          if (tracks.isEmpty)
            EmptyLibrary(onImport: () => context.read<Importer>().pickAndImport())
          else
            switch (_section) {
              LibrarySection.songs => _Songs(tracks: sorted),
              LibrarySection.artists => _Browse(tracks: tracks, byArtist: true),
              LibrarySection.albums => _Browse(tracks: tracks, byArtist: false),
              LibrarySection.playlists => const _Playlists(),
            },
        ],
      ),
    );
  }
}

class _Songs extends StatelessWidget {
  const _Songs({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final app = context.watch<AppState>();
    final store = context.read<LibraryStore>();
    final player = context.watch<PlayerController>();
    final s = app.s;

    return Column(
      children: [
        GestureDetector(
          onTap: () => tracks.isEmpty ? null : player.play(tracks.first, tracks),
          child: Glass(
            radius: 18,
            elevated: false,
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                const Icon(Icons.play_arrow, size: 20, color: accent),
                const SizedBox(width: 8),
                Text(
                  s.playAll,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colors.primaryText,
                  ),
                ),
                const Spacer(),
                Text(
                  s.songsCount(tracks.length),
                  style: TextStyle(fontSize: 12.5, color: colors.secondaryText),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        ...tracks.map(
          (track) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => player.play(track, tracks),
            onLongPress: () => showTrackSheet(context, track),
            child: TrackRow(
              track: track,
              isCurrent: player.current?.id == track.id,
              onFavorite: () => store.toggleFavorite(track),
            ),
          ),
        ),
      ],
    );
  }
}

class _Browse extends StatelessWidget {
  const _Browse({required this.tracks, required this.byArtist});

  final List<Track> tracks;
  final bool byArtist;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;

    final groups = <String, List<Track>>{};
    for (final track in tracks) {
      final key = byArtist ? track.artistName(s) : track.albumName(s);
      groups.putIfAbsent(key, () => []).add(track);
    }
    final names = groups.keys.toList()..sort();

    return Column(
      children: names.map((name) {
        final items = groups[name]!;
        return _GroupRow(
          title: name,
          subtitle: s.songsCount(items.length),
          cover: items.firstWhere((t) => t.coverName != null, orElse: () => items.first),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => _GroupDetail(title: name, tracks: items)),
          ),
        );
      }).toList(),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Track? cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Artwork(track: cover, size: 52),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(fontSize: 12.5, color: colors.secondaryText)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: colors.secondaryText),
          ],
        ),
      ),
    );
  }
}

class _GroupDetail extends StatelessWidget {
  const _GroupDetail({required this.title, required this.tracks});

  final String title;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final player = context.watch<PlayerController>();

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        foregroundColor: colors.primaryText,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 170),
        children: tracks
            .map((track) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => player.play(track, tracks),
                  onLongPress: () => showTrackSheet(context, track),
                  child: TrackRow(track: track, isCurrent: player.current?.id == track.id),
                ))
            .toList(),
      ),
    );
  }
}

class _Playlists extends StatelessWidget {
  const _Playlists();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final app = context.watch<AppState>();
    final store = context.watch<LibraryStore>();
    final s = app.s;

    return Column(
      children: [
        GestureDetector(
          onTap: () async {
            final name = await promptForName(context, s);
            if (name != null && name.isNotEmpty) await store.createPlaylist(name);
          },
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.add, color: accent, size: 20),
                const SizedBox(width: 10),
                Text(
                  s.newPlaylist,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (store.playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Text(s.noPlaylistsYet, style: TextStyle(color: colors.secondaryText)),
          )
        else
          ...store.playlists.map((playlist) {
            final tracks = store.byIds(playlist.trackIds);
            final minutes = tracks.fold<int>(0, (sum, t) => sum + t.durationMs) ~/ 60000;
            return GestureDetector(
              onLongPress: () => store.deletePlaylist(playlist),
              child: _GroupRow(
                title: playlist.name,
                subtitle: '${s.songsCount(tracks.length)} · ${s.totalDuration(minutes)}',
                cover: tracks.isEmpty ? null : tracks.first,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => _PlaylistDetail(playlist: playlist)),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _PlaylistDetail extends StatelessWidget {
  const _PlaylistDetail({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final app = context.watch<AppState>();
    final store = context.watch<LibraryStore>();
    final player = context.watch<PlayerController>();
    final s = app.s;

    final tracks = store.byIds(playlist.trackIds);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(playlist.name),
        backgroundColor: Colors.transparent,
        foregroundColor: colors.primaryText,
      ),
      body: tracks.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  s.playlistEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.secondaryText, height: 1.7),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 170),
              children: [
                FilledButton.icon(
                  onPressed: () => player.play(tracks.first, tracks),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(s.playAll),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: onAccent,
                    shape: const StadiumBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ...tracks.map((track) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => player.play(track, tracks),
                      onLongPress: () => showTrackSheet(context, track, fromPlaylist: playlist),
                      child: TrackRow(track: track, isCurrent: player.current?.id == track.id),
                    )),
              ],
            ),
    );
  }
}
