import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'audio/player_controller.dart';
import 'data/importer.dart';
import 'data/library_store.dart';
import 'platform.dart';
import 'screens/root.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = await LibraryStore.open();
  final appState = await AppState.load();
  final controller = PlayerController(store);

  // audio_service (the notification / lock-screen bridge) is mobile-only. On
  // desktop the player runs fine without it — just no OS media controls.
  if (Plat.isMobile) {
    final handler = await AudioService.init(
      builder: () => ASAudioHandler(controller),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'ir.aspoormehr.asplayer.audio',
        androidNotificationChannelName: 'ASplayer',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    controller.attach(handler);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider.value(value: controller),
        Provider.value(value: Importer(store)),
      ],
      child: const ASplayerApp(),
    ),
  );
}

class ASplayerApp extends StatelessWidget {
  const ASplayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return MaterialApp(
      title: 'ASplayer',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: app.themeMode,
      builder: (context, child) => Directionality(
        textDirection: app.lang.direction,
        child: child!,
      ),
      home: const RootScreen(),
    );
  }
}
