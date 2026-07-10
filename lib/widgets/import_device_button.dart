import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/device_music.dart';
import '../data/importer.dart';
import '../theme.dart';

/// Pulls in every song the phone already holds — the same list Samsung Music
/// shows. Files are linked, never copied.
class ImportDeviceButton extends StatefulWidget {
  const ImportDeviceButton({super.key, this.filled = true});

  /// Filled reads as the primary action (onboarding, empty library);
  /// outlined sits quietly in Settings.
  final bool filled;

  @override
  State<ImportDeviceButton> createState() => _ImportDeviceButtonState();
}

class _ImportDeviceButtonState extends State<ImportDeviceButton> {
  bool _busy = false;
  int _done = 0;
  int _total = 0;

  Future<void> _run() async {
    final app = context.read<AppState>();
    final importer = context.read<Importer>();
    final messenger = ScaffoldMessenger.of(context);
    final s = app.s;

    if (!await DeviceMusic.requestPermission()) {
      messenger.showSnackBar(SnackBar(content: Text(s.permissionNeeded)));
      return;
    }

    setState(() {
      _busy = true;
      _done = 0;
      _total = 0;
    });

    final songs = await DeviceMusic.scan();
    if (songs.isEmpty) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(s.noSongsOnPhone)));
      return;
    }

    final added = await importer.linkDeviceSongs(
      songs,
      onProgress: (done, total) {
        if (!mounted) return;
        setState(() {
          _done = done;
          _total = total;
        });
      },
    );

    // From now on, keep the library in step with the phone's music folder.
    app.deviceSyncEnabled = true;

    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(content: Text(s.imported(added))));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final s = context.watch<AppState>().s;

    if (_busy) {
      final label = _total == 0 ? s.scanningPhone : '${s.importing}  $_done / $_total';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: 13.5, color: colors.secondaryText),
              ),
            ),
          ],
        ),
      );
    }

    const icon = Icon(Icons.library_music_outlined, size: 19);
    final label = Text(s.importFromPhone);

    return SizedBox(
      width: double.infinity,
      child: widget.filled
          ? FilledButton.icon(
              onPressed: _run,
              icon: icon,
              label: label,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: onAccent,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: const StadiumBorder(),
              ),
            )
          : OutlinedButton.icon(
              onPressed: _run,
              icon: icon,
              label: label,
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: colors.rim),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: const StadiumBorder(),
              ),
            ),
    );
  }
}
