import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../app_state.dart';
import '../audio/player_controller.dart';
import '../data/importer.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'favorites.dart';
import 'home.dart';
import 'library.dart';
import 'onboarding.dart';
import 'player.dart';
import 'settings.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  @override
  void initState() {
    super.initState();
    _listenForSharedFiles();
  }

  /// Files arriving from Telegram's share sheet, both while running and on a
  /// cold start.
  void _listenForSharedFiles() {
    final importer = context.read<Importer>();

    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      importer.importPaths(files.map((f) => f.path));
    });

    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isEmpty) return;
      importer.importPaths(files.map((f) => f.path));
      ReceiveSharingIntent.instance.reset();
    });
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.onboarded) return const OnboardingScreen();

    final player = context.watch<PlayerController>();

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(child: Backdrop(track: player.current)),
          IndexedStack(
            index: app.tab,
            children: const [
              HomeScreen(),
              FavoritesScreen(),
              LibraryScreen(),
              SettingsScreen(),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (player.current != null)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: _MiniPlayer(),
                    ),
                  const SizedBox(height: 10),
                  const _FloatingTabBar(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final player = context.watch<PlayerController>();
    final app = context.watch<AppState>();
    final track = player.current!;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PlayerScreen()),
      ),
      child: Glass(
        radius: 22,
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Artwork(track: track, size: 40, radius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colors.primaryText,
                    ),
                  ),
                  Text(
                    track.artistName(app.s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.secondaryText),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: player.toggle,
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(color: accent, shape: BoxShape.circle),
                child: Icon(
                  player.playing ? Icons.pause : Icons.play_arrow,
                  color: onAccent,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingTabBar extends StatelessWidget {
  const _FloatingTabBar();

  static const _icons = [
    Icons.home_rounded,
    Icons.favorite_rounded,
    Icons.library_music_rounded,
    Icons.settings_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final app = context.watch<AppState>();

    return Glass(
      radius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(_icons.length, (index) {
          final selected = app.tab == index;
          return GestureDetector(
            onTap: () => app.tab = index,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 46,
              height: 46,
              margin: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: selected ? accent : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _icons[index],
                size: 20,
                color: selected ? onAccent : colors.secondaryText,
              ),
            ),
          );
        }),
      ),
    );
  }
}
