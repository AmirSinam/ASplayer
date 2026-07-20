import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import '../audio/player_controller.dart';
import '../data/library_store.dart';
import '../l10n.dart';
import '../party/party_server.dart';
import '../theme.dart';

/// The host side of party mode: starts the local server and shows a QR guests
/// scan to join. The server is torn down when this screen closes.
class PartyScreen extends StatefulWidget {
  const PartyScreen({super.key});

  @override
  State<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends State<PartyScreen> {
  PartyServer? _server;
  String? _url;
  bool _starting = true;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    final store = context.read<LibraryStore>();
    final player = context.read<PlayerController>();
    final server = PartyServer(store: store, onAdd: player.partyAdd);
    final url = await server.start();
    if (!mounted) {
      server.stop();
      return;
    }
    setState(() {
      _server = server;
      _url = url;
      _starting = false;
    });
    // Refresh the "added by guests" count once a second.
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _retry() async {
    await _server?.stop();
    _server = null;
    await _start();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _server?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final s = context.watch<AppState>().s;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(s.partyMode),
        backgroundColor: Colors.transparent,
        foregroundColor: colors.primaryText,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _body(s, colors),
        ),
      ),
    );
  }

  Widget _body(Strings s, AppColors colors) {
    if (_starting) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: accent),
          const SizedBox(height: 16),
          Text(s.partyStarting, style: TextStyle(color: colors.secondaryText)),
        ],
      );
    }

    if (_url == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 44, color: colors.secondaryText),
          const SizedBox(height: 16),
          Text(
            s.partyNoNetwork,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.secondaryText, height: 1.7),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _retry,
            style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: onAccent),
            child: Text(s.partyStarting),
          ),
        ],
      );
    }

    final added = _server?.addedCount ?? 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: QrImageView(
            data: _url!,
            size: 236,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          s.partyScanHint,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: colors.primaryText),
        ),
        const SizedBox(height: 8),
        SelectableText(
          _url!,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: accent, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          s.partySameWifi,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: colors.secondaryText),
        ),
        const SizedBox(height: 22),
        if (added > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.queue_music, size: 16, color: accent),
                const SizedBox(width: 6),
                Text(
                  s.partyAdded(added),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: accent),
                ),
              ],
            ),
          ),
        const SizedBox(height: 26),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
            label: Text(s.endParty),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
            ),
          ),
        ),
      ],
    );
  }
}
