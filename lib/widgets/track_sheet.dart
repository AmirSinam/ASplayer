import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../audio/player_controller.dart';
import '../data/library_store.dart';
import '../l10n.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// The long-press menu shared by every list of songs.
Future<void> showTrackSheet(
  BuildContext context,
  Track track, {
  Playlist? fromPlaylist,
}) {
  final app = context.read<AppState>();
  final store = context.read<LibraryStore>();
  final player = context.read<PlayerController>();
  final s = app.s;
  final colors = AppColors.of(context);

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.background,
    showDragHandle: true,
    builder: (sheetContext) {
      Widget item(IconData icon, String label, VoidCallback onTap, {bool danger = false}) {
        final color = danger ? Colors.redAccent : colors.primaryText;
        return ListTile(
          leading: Icon(icon, color: danger ? Colors.redAccent : accent, size: 21),
          title: Text(label, style: TextStyle(color: color, fontSize: 15)),
          onTap: () {
            Navigator.pop(sheetContext);
            onTap();
          },
        );
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  SizedBox(width: 44, height: 44, child: Artwork(track: track)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            item(Icons.playlist_play, s.playNext, () => player.playNext(track)),
            item(Icons.queue_music, s.addToQueue, () => player.addToQueue(track)),
            item(Icons.playlist_add, s.addToPlaylist, () => showAddToPlaylist(context, track)),
            item(
              track.favorite ? Icons.favorite : Icons.favorite_border,
              track.favorite ? s.unmarkFavorite : s.markFavorite,
              () => store.toggleFavorite(track),
            ),
            if (fromPlaylist != null)
              item(
                Icons.remove_circle_outline,
                s.removeFromPlaylist,
                () => store.removeFromPlaylist(fromPlaylist, track),
                danger: true,
              ),
            item(Icons.delete_outline, s.deleteFromLibrary, () => store.delete(track), danger: true),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<void> showAddToPlaylist(BuildContext context, Track track) {
  final app = context.read<AppState>();
  final store = context.read<LibraryStore>();
  final s = app.s;
  final colors = AppColors.of(context);

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.background,
    showDragHandle: true,
    builder: (sheetContext) => AnimatedBuilder(
      animation: store,
      builder: (context, _) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add, color: accent),
              title: Text(s.newPlaylist, style: const TextStyle(color: accent, fontSize: 15)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final name = await promptForName(context, s);
                if (name != null && name.isNotEmpty) {
                  await store.createPlaylist(name, withTrack: track);
                }
              },
            ),
            if (store.playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(s.noPlaylistsYet, style: TextStyle(color: colors.secondaryText)),
              ),
            ...store.playlists.map((playlist) {
              final already = playlist.trackIds.contains(track.id);
              return ListTile(
                leading: Icon(
                  already ? Icons.check_circle : Icons.queue_music,
                  color: accent,
                ),
                title: Text(playlist.name, style: TextStyle(color: colors.primaryText)),
                subtitle: Text(
                  s.songsCount(playlist.trackIds.length),
                  style: TextStyle(color: colors.secondaryText, fontSize: 12),
                ),
                enabled: !already,
                onTap: () async {
                  await store.addToPlaylist(playlist, track);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

Future<String?> promptForName(BuildContext context, Strings s) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(s.newPlaylist),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: s.playlistNamePlaceholder),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s.cancel)),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: Text(s.create),
        ),
      ],
    ),
  );
}
