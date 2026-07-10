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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Collection _collection = Collection.all;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final app = context.watch<AppState>();
    final store = context.watch<LibraryStore>();
    final player = context.watch<PlayerController>();
    final s = app.s;

    final tracks = store.tracks;
    final selected = _collection.apply(tracks);

    final searchResults = tracks
        .where((t) =>
            t.title.toLowerCase().contains(_search.toLowerCase()) ||
            t.artist.toLowerCase().contains(_search.toLowerCase()))
        .toList();

    final recent = tracks.where((t) => t.lastPlayedAt != null).toList()
      ..sort((a, b) => b.lastPlayedAt!.compareTo(a.lastPlayedAt!));

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 170),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.hello,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      s.songsInLibrary(tracks.length),
                      style: TextStyle(fontSize: 13, color: colors.secondaryText),
                    ),
                  ],
                ),
              ),
              const _AddButton(),
            ],
          ),
          const SizedBox(height: 20),

          Glass(
            radius: 999,
            elevated: false,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (value) => setState(() => _search = value),
                    style: TextStyle(color: colors.primaryText, fontSize: 14.5),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: s.searchSong,
                      hintStyle: TextStyle(color: colors.secondaryText, fontSize: 14.5),
                    ),
                  ),
                ),
                const Icon(Icons.search, color: accent, size: 20),
              ],
            ),
          ),
          const SizedBox(height: 22),

          if (_search.isNotEmpty)
            ...[
              if (searchResults.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: Text(s.noSongFound, style: TextStyle(color: colors.secondaryText)),
                  ),
                )
              else
                ...searchResults.map((track) => _row(context, track, searchResults)),
            ]
          else if (tracks.isEmpty)
            EmptyLibrary(onImport: () => context.read<Importer>().pickAndImport())
          else ...[
            SectionHeader(title: s.categories),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: Collection.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 9),
                itemBuilder: (context, index) {
                  final item = Collection.values[index];
                  return GlassChip(
                    label: item.title(s),
                    selected: _collection == item,
                    onTap: () => setState(() => _collection = item),
                  );
                },
              ),
            ),
            const SizedBox(height: 22),

            if (selected.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    _collection.emptyMessage(s),
                    style: TextStyle(color: colors.secondaryText),
                  ),
                ),
              )
            else ...[
              SectionHeader(
                title: _collection == Collection.all ? s.yourSongs : _collection.title(s),
                onMore: () => app.tab = 2,
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 190,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: selected.length > 8 ? 8 : selected.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final track = selected[index];
                    return GestureDetector(
                      onTap: () => player.play(track, selected),
                      onLongPress: () => showTrackSheet(context, track),
                      child: SongCard(track: track),
                    );
                  },
                ),
              ),
              const SizedBox(height: 22),
            ],

            if (recent.isNotEmpty) ...[
              SectionHeader(title: s.recentlyPlayed),
              const SizedBox(height: 6),
              ...recent.take(5).map((track) => _row(context, track, recent.take(5).toList())),
            ],
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, Track track, List<Track> queue) {
    final player = context.read<PlayerController>();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => player.play(track, queue),
      onLongPress: () => showTrackSheet(context, track),
      child: TrackRow(track: track, isCurrent: player.current?.id == track.id),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.read<Importer>().pickAndImport(),
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(color: accent, shape: BoxShape.circle),
        child: const Icon(Icons.add, color: onAccent, size: 22),
      ),
    );
  }
}
