import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../app_state.dart';
import '../audio/player_controller.dart';
import '../data/device_music.dart';
import '../data/importer.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets/app_snack.dart';
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

class _RootScreenState extends State<RootScreen> with WidgetsBindingObserver {
  StreamSubscription<List<SharedMediaFile>>? _shareSub;
  final _pager = PageController();
  DateTime? _lastBack;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenForSharedFiles();
    _syncDeviceSongs();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from Telegram after saving a song into Music is the main case:
    // pick up anything new without the user asking.
    if (state == AppLifecycleState.resumed) _syncDeviceSongs();
  }

  /// Links songs added to the phone since last time. Runs on launch and every
  /// time the app comes forward, so a track saved from anywhere — a browser,
  /// Telegram, Rubika, the share sheet — turns up on its own. Only active once
  /// the user has opted in.
  Future<void> _syncDeviceSongs() async {
    final app = context.read<AppState>();
    if (!app.deviceSyncEnabled) return;
    if (!await DeviceMusic.hasPermission()) return;

    final songs = await DeviceMusic.scan();
    if (songs.isEmpty || !mounted) return;
    final added = await context.read<Importer>().linkDeviceSongs(songs);
    _notifyAdded(added);
  }

  /// A small banner telling the user how many songs just landed. Shown when the
  /// app is in front (which is when device sync runs), so it reads like a
  /// notification without needing a background service.
  void _notifyAdded(int count) {
    if (count <= 0 || !mounted) return;
    final s = context.read<AppState>().s;
    showAppSnack(context, s.imported(count),
        kind: SnackKind.success, icon: Icons.library_add_check_rounded);
  }

  /// Files arriving from Telegram's share sheet, both while running and on a
  /// cold start. Mobile-only — the plugin has no desktop implementation.
  void _listenForSharedFiles() {
    if (!Plat.isMobile) return;
    final importer = context.read<Importer>();

    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) async {
      final added = await importer.importPaths(files.map((f) => f.path));
      _notifyAdded(added);
    });

    ReceiveSharingIntent.instance.getInitialMedia().then((files) async {
      if (files.isEmpty) return;
      final added = await importer.importPaths(files.map((f) => f.path));
      _notifyAdded(added);
      ReceiveSharingIntent.instance.reset();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareSub?.cancel();
    _pager.dispose();
    super.dispose();
  }

  void _goToTab(int index) {
    // Animate the pager; its callback writes app.tab back.
    _pager.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// Back button: step back to Home first, and only leave the app on a second
  /// press from Home — so a stray back never dumps the user out.
  Future<void> _handleBack(AppState app) async {
    if (app.tab != 0) {
      _goToTab(0);
      return;
    }
    final now = DateTime.now();
    if (_lastBack != null && now.difference(_lastBack!) < const Duration(seconds: 2)) {
      await SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    showAppSnack(context, app.s.pressBackAgain, duration: const Duration(seconds: 2));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.onboarded) return const OnboardingScreen();

    final player = context.watch<PlayerController>();

    // Keep the pager in step when the tab is changed from the bar.
    if (_pager.hasClients && _pager.page?.round() != app.tab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pager.hasClients && _pager.page?.round() != app.tab) _goToTab(app.tab);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack(app);
      },
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            Positioned.fill(child: Backdrop(track: player.current)),
            // Swipe left/right to move between Home, Favorites, Library, Settings.
            PageView(
              controller: _pager,
              onPageChanged: (index) => app.tab = index,
              children: const [
                _KeepAlive(child: HomeScreen()),
                _KeepAlive(child: FavoritesScreen()),
                _KeepAlive(child: LibraryScreen()),
                _KeepAlive(child: SettingsScreen()),
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
                    _FloatingTabBar(onTap: _goToTab),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps a page's state (scroll position, selections) alive while swiping.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
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
  const _FloatingTabBar({required this.onTap});

  final ValueChanged<int> onTap;

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
            onTap: () => onTap(index),
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
