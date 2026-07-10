import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../audio/player_controller.dart';
import '../data/library_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/track_sheet.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final app = context.watch<AppState>();
    final store = context.watch<LibraryStore>();
    final player = context.watch<PlayerController>();
    final s = app.s;

    final favorites = store.tracks.where((t) => t.favorite).toList();

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            sliver: SliverToBoxAdapter(
              child: Text(
                s.favorites,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
            ),
          ),
          if (favorites.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 120),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.favorite_border, size: 38, color: accent),
                    const SizedBox(height: 12),
                    Text(
                      s.noFavoritesYet,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.favEmptyBody,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: colors.secondaryText),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 170),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.78,
                ),
                itemCount: favorites.length,
                itemBuilder: (context, index) {
                  final track = favorites[index];
                  return GestureDetector(
                    onTap: () => player.play(track, favorites),
                    onLongPress: () => showTrackSheet(context, track),
                    child: SongCard(track: track, width: null),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
