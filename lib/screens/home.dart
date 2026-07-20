import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../audio/player_controller.dart';
import '../data/importer.dart';
import '../data/library_store.dart';
import '../l10n.dart';
import '../models.dart';
import '../moods.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/track_sheet.dart';
import 'party.dart';

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
                    // The wordmark: "AS" in tiffany, "player" in the text colour,
                    // set in the display font. Forced LTR so it reads correctly
                    // even in the Persian layout.
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'AS', style: TextStyle(color: accent)),
                            TextSpan(
                              text: 'player',
                              style: TextStyle(color: colors.primaryText),
                            ),
                          ],
                        ),
                        style: const TextStyle(
                          fontFamily: wordmarkFont,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.songsInLibrary(tracks.length),
                      style: TextStyle(fontSize: 13, color: colors.secondaryText),
                    ),
                  ],
                ),
              ),
              const _PartyButton(),
              const SizedBox(width: 10),
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

            ..._moodSection(context, store, player, s, app.lang == Lang.fa),

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

  /// A row of mood chips for moods actually in use; tapping plays that mood
  /// shuffled. Empty (returns nothing) until the user tags some songs.
  List<Widget> _moodSection(BuildContext context, LibraryStore store,
      PlayerController player, Strings s, bool fa) {
    final used = moods.where((m) => store.usedMoods.contains(m.id)).toList();
    if (used.isEmpty) return const [];
    final colors = AppColors.of(context);

    return [
      SectionHeader(title: s.howYouFeel),
      const SizedBox(height: 10),
      SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: used.length,
          separatorBuilder: (_, __) => const SizedBox(width: 9),
          itemBuilder: (context, index) {
            final m = used[index];
            return GestureDetector(
              onTap: () {
                final list = store.tracksByMood(m.id);
                if (list.isEmpty) return;
                final shuffled = [...list]..shuffle();
                player.play(shuffled.first, shuffled);
              },
              child: Glass(
                radius: 999,
                elevated: false,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(m.icon, size: 16, color: accent),
                    const SizedBox(width: 6),
                    Text(
                      m.label(fa),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 22),
    ];
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

/// A one-tap entry to party mode, right on Home so it is easy to reach. Kept
/// glassy (secondary) so the filled Add button stays the primary action.
class _PartyButton extends StatelessWidget {
  const _PartyButton();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PartyScreen()),
      ),
      child: Tooltip(
        message: s.partyMode,
        child: const Glass(
          radius: 999,
          elevated: false,
          padding: EdgeInsets.all(11),
          child: Icon(Icons.groups_rounded, color: accent, size: 22),
        ),
      ),
    );
  }
}
