import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../audio/player_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'party.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final app = context.watch<AppState>();
    final player = context.watch<PlayerController>();
    final s = app.s;

    final upNext = player.upNext;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(s.queue),
        backgroundColor: Colors.transparent,
        foregroundColor: colors.primaryText,
        actions: [
          IconButton(
            tooltip: s.partyMode,
            icon: const Icon(Icons.groups_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PartyScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          if (player.current != null) ...[
            _label(s.nowPlaying, colors),
            Glass(
              radius: 18,
              elevated: false,
              padding: const EdgeInsets.all(8),
              child: TrackRow(track: player.current!, isCurrent: true),
            ),
            const SizedBox(height: 18),
          ],
          _label(s.upNext, colors),
          if (upNext.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(s.queueEmpty, style: TextStyle(color: colors.secondaryText)),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: upNext.length,
              onReorder: player.moveUpNext,
              itemBuilder: (context, index) {
                final track = upNext[index];
                return Dismissible(
                  key: ValueKey('${track.id}_$index'),
                  direction: DismissDirection.endToStart,
                  background: const ColoredBox(color: Colors.redAccent),
                  onDismissed: (_) => player.removeUpNext(index),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => player.playFromQueue(track),
                    child: TrackRow(
                      track: track,
                      isCurrent: false,
                      trailing: ReorderableDragStartListener(
                        index: index,
                        child: Icon(Icons.drag_handle, color: colors.secondaryText),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _label(String text, AppColors colors) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 8),
        child: Text(
          text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colors.secondaryText),
        ),
      );
}
