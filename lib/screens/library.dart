import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../audio/player_controller.dart';
import '../data/importer.dart';
import '../data/library_store.dart';
import '../l10n.dart';
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Text(
                  s.library,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: colors.primaryText),
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
          ),
          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
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
          ),
          const SizedBox(height: 16),

          // Each section owns a lazy scroll list, so only the visible rows — and
          // their covers — are ever built. The header and tabs above stay pinned.
          Expanded(
            child: tracks.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 170),
                    children: [
                      EmptyLibrary(onImport: () => context.read<Importer>().pickAndImport()),
                    ],
                  )
                : switch (_section) {
                    LibrarySection.songs => _Songs(tracks: sorted),
                    LibrarySection.artists => _Browse(tracks: tracks, byArtist: true),
                    LibrarySection.albums => _Browse(tracks: tracks, byArtist: false),
                    LibrarySection.playlists => const _Playlists(),
                  },
          ),
        ],
      ),
    );
  }
}

// MARK: - Songs with multi-select

class _Songs extends StatefulWidget {
  const _Songs({required this.tracks});

  final List<Track> tracks;

  @override
  State<_Songs> createState() => _SongsState();
}

class _SongsState extends State<_Songs> {
  final Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  void _toggle(Track track) {
    setState(() {
      if (!_selected.remove(track.id)) _selected.add(track.id);
    });
  }

  List<Track> get _selectedTracks =>
      widget.tracks.where((t) => _selected.contains(t.id)).toList();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final app = context.watch<AppState>();
    final store = context.read<LibraryStore>();
    final player = context.watch<PlayerController>();
    final s = app.s;

    // A lazy list: item 0 is the play-all / selection bar, the rest are rows.
    // Only on-screen rows are built, so covers decode as the user scrolls.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 170),
      itemCount: widget.tracks.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          final Widget header = _selecting
              ? _SelectionBar(
                  count: _selected.length,
                  allSelected: _selected.length == widget.tracks.length,
                  onSelectAll: () => setState(() {
                    if (_selected.length == widget.tracks.length) {
                      _selected.clear();
                    } else {
                      _selected
                        ..clear()
                        ..addAll(widget.tracks.map((t) => t.id));
                    }
                  }),
                  onQueue: () {
                    for (final t in _selectedTracks) {
                      player.addToQueue(t);
                    }
                    setState(_selected.clear);
                  },
                  onPlaylist: () async {
                    await showAddTracksToPlaylist(context, _selectedTracks);
                    if (mounted) setState(_selected.clear);
                  },
                  onDelete: () => _confirmDelete(context, store, s),
                  onClose: () => setState(_selected.clear),
                )
              : GestureDetector(
                  onTap: () =>
                      widget.tracks.isEmpty ? null : player.play(widget.tracks.first, widget.tracks),
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
                              fontSize: 14, fontWeight: FontWeight.bold, color: colors.primaryText),
                        ),
                        const Spacer(),
                        Text(
                          s.songsCount(widget.tracks.length),
                          style: TextStyle(fontSize: 12.5, color: colors.secondaryText),
                        ),
                      ],
                    ),
                  ),
                );
          return Padding(padding: const EdgeInsets.only(bottom: 10), child: header);
        }

        final track = widget.tracks[index - 1];
        final selected = _selected.contains(track.id);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Long-press starts (or extends) a selection; tap plays, or toggles
          // once selecting.
          onTap: () => _selecting ? _toggle(track) : player.play(track, widget.tracks),
          onLongPress: () => _toggle(track),
          child: _SelectableRow(
            track: track,
            selecting: _selecting,
            selected: selected,
            isCurrent: player.current?.id == track.id,
            onFavorite: () => store.toggleFavorite(track),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, LibraryStore store, Strings s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.delete),
        content: Text(s.deleteQuestion),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(s.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(s.delete, style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await store.deleteMany(_selectedTracks);
    if (mounted) setState(_selected.clear);
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.allSelected,
    required this.onSelectAll,
    required this.onQueue,
    required this.onPlaylist,
    required this.onDelete,
    required this.onClose,
  });

  final int count;
  final bool allSelected;
  final VoidCallback onSelectAll, onQueue, onPlaylist, onDelete, onClose;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final s = context.watch<AppState>().s;

    return Glass(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close, color: colors.primaryText),
            tooltip: s.close,
          ),
          Text(
            s.nSelected(count),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colors.primaryText),
          ),
          const Spacer(),
          IconButton(onPressed: onSelectAll, tooltip: s.selectAll,
              icon: Icon(allSelected ? Icons.deselect : Icons.select_all, color: colors.primaryText)),
          IconButton(onPressed: onQueue, tooltip: s.addToQueue,
              icon: Icon(Icons.queue_music, color: colors.primaryText)),
          IconButton(onPressed: onPlaylist, tooltip: s.addToPlaylist,
              icon: Icon(Icons.playlist_add, color: colors.primaryText)),
          IconButton(onPressed: onDelete, tooltip: s.delete,
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
        ],
      ),
    );
  }
}

class _SelectableRow extends StatelessWidget {
  const _SelectableRow({
    required this.track,
    required this.selecting,
    required this.selected,
    required this.isCurrent,
    required this.onFavorite,
  });

  final Track track;
  final bool selecting, selected, isCurrent;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    if (!selecting) {
      return TrackRow(track: track, isCurrent: isCurrent, onFavorite: onFavorite);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            color: selected ? accent : AppColors.of(context).secondaryText,
          ),
          const SizedBox(width: 4),
          Expanded(child: TrackRow(track: track, isCurrent: isCurrent)),
        ],
      ),
    );
  }
}

// MARK: - Browse by artist / album

class _Browse extends StatelessWidget {
  const _Browse({required this.tracks, required this.byArtist});

  final List<Track> tracks;
  final bool byArtist;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;

    final groups = <String, List<Track>>{};
    for (final track in tracks) {
      // One song credited to several artists shows up under each of them.
      final keys = byArtist
          ? (track.artist.isEmpty ? [s.unknownArtist] : splitArtists(track.artist))
          : [track.albumName(s)];
      for (final key in keys) {
        groups.putIfAbsent(key, () => []).add(track);
      }
    }
    final names = groups.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 170),
      itemCount: names.length,
      itemBuilder: (context, i) {
        final name = names[i];
        final items = groups[name]!;
        return _GroupRow(
          title: name,
          subtitle: s.songsCount(items.length),
          cover: items.firstWhere((t) => t.coverName != null, orElse: () => items.first),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => GroupDetail(title: name, tracks: items)),
          ),
          onLongPress: () => _showGroupActions(context, name, items),
        );
      },
    );
  }
}

/// The per-album / per-artist action sheet: select a group and act on all of it.
void _showGroupActions(BuildContext context, String title, List<Track> tracks) {
  final s = context.read<AppState>().s;
  final store = context.read<LibraryStore>();
  final player = context.read<PlayerController>();
  final colors = AppColors.of(context);

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.background,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold, color: colors.primaryText),
                  ),
                ),
                Text(s.songsCount(tracks.length),
                    style: TextStyle(color: colors.secondaryText, fontSize: 12.5)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.play_arrow, color: accent),
            title: Text(s.playAll),
            onTap: () {
              Navigator.pop(sheetContext);
              if (tracks.isNotEmpty) player.play(tracks.first, tracks);
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_music, color: accent),
            title: Text(s.addToQueue),
            onTap: () {
              Navigator.pop(sheetContext);
              for (final t in tracks) {
                player.addToQueue(t);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add, color: accent),
            title: Text(s.addToPlaylist),
            onTap: () {
              Navigator.pop(sheetContext);
              showAddTracksToPlaylist(context, tracks);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: Text(s.deleteFromLibrary, style: const TextStyle(color: Colors.redAccent)),
            onTap: () async {
              Navigator.pop(sheetContext);
              await store.deleteMany(tracks);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.onTap,
    this.onLongPress,
  });

  final String title;
  final String subtitle;
  final Track? cover;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
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
                        fontSize: 15.5, fontWeight: FontWeight.bold, color: colors.primaryText),
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

/// The song list for one artist or album. Public so the player screen can open
/// an artist straight from the now-playing title.
class GroupDetail extends StatelessWidget {
  const GroupDetail({super.key, required this.title, required this.tracks});

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
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 170),
        itemCount: tracks.length,
        itemBuilder: (context, i) {
          final track = tracks[i];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => player.play(track, tracks),
            onLongPress: () => showTrackSheet(context, track),
            child: TrackRow(track: track, isCurrent: player.current?.id == track.id),
          );
        },
      ),
    );
  }
}

// MARK: - Playlists

class _Playlists extends StatelessWidget {
  const _Playlists();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final app = context.watch<AppState>();
    final store = context.watch<LibraryStore>();
    final s = app.s;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 170),
      children: [
        _createRow(context, store, s, Icons.add, s.newPlaylist, mixtape: false),
        const SizedBox(height: 8),
        _createRow(context, store, s, Icons.graphic_eq, s.newMixtape, mixtape: true),
        const SizedBox(height: 12),
        if (store.playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Text(s.noPlaylistsYet, style: TextStyle(color: colors.secondaryText)),
          )
        else
          ...store.playlists.map((playlist) {
            final tracks = store.byIds(playlist.trackIds);
            final minutes = tracks.fold<int>(0, (sum, t) => sum + t.durationMs) ~/ 60000;
            final base = '${s.songsCount(tracks.length)} · ${s.totalDuration(minutes)}';
            return _GroupRow(
              title: playlist.name,
              subtitle: playlist.mixtape ? '${s.mixtapeLabel} · $base' : base,
              cover: tracks.isEmpty ? null : tracks.first,
              onLongPress: () => store.deletePlaylist(playlist),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => _PlaylistDetail(playlist: playlist)),
              ),
            );
          }),
      ],
    );
  }

  Widget _createRow(BuildContext context, LibraryStore store, Strings s, IconData icon,
      String label, {required bool mixtape}) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: () async {
        final name = await promptForName(context, s);
        if (name != null && name.isNotEmpty) {
          await store.createPlaylist(name, mixtape: mixtape);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: accent),
            ),
            if (mixtape) ...[
              const Spacer(),
              Text(
                s.mixtapeHint,
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 10.5, color: colors.secondaryText),
              ),
            ],
          ],
        ),
      ),
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
                  onPressed: () => _playFrom(player, tracks.first, tracks),
                  icon: Icon(playlist.mixtape ? Icons.graphic_eq : Icons.play_arrow),
                  label: Text(playlist.mixtape ? s.mixtapeLabel : s.playAll),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: onAccent,
                    shape: const StadiumBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ...tracks.map((track) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _playFrom(player, track, tracks),
                      onLongPress: () => showTrackSheet(context, track, fromPlaylist: playlist),
                      child: TrackRow(track: track, isCurrent: player.current?.id == track.id),
                    )),
              ],
            ),
    );
  }

  /// A mixtape plays as one continuous crossfaded set; a normal playlist cuts
  /// between tracks as usual.
  void _playFrom(PlayerController player, Track track, List<Track> tracks) {
    if (playlist.mixtape) {
      player.playMixtape(track, tracks);
    } else {
      player.play(track, tracks);
    }
  }
}
