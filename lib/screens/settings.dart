import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../data/importer.dart';
import '../data/library_store.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/import_device_button.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final app = context.watch<AppState>();
    final store = context.watch<LibraryStore>();
    final s = app.s;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 170),
        children: [
          Text(
            s.settings,
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: colors.primaryText),
          ),
          const SizedBox(height: 18),

          _Card(
            children: [
              _title(s.language, colors),
              const SizedBox(height: 10),
              SegmentedButton<Lang>(
                segments: Lang.values
                    .map((l) => ButtonSegment(value: l, label: Text(l.displayName)))
                    .toList(),
                selected: {app.lang},
                onSelectionChanged: (set) => app.lang = set.first,
              ),
            ],
          ),
          const SizedBox(height: 14),

          _Card(
            children: [
              _title(s.appearance, colors),
              const SizedBox(height: 10),
              SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(value: ThemeMode.system, label: Text(s.appearanceSystem)),
                  ButtonSegment(value: ThemeMode.light, label: Text(s.appearanceLight)),
                  ButtonSegment(value: ThemeMode.dark, label: Text(s.appearanceDark)),
                ],
                selected: {app.themeMode},
                onSelectionChanged: (set) => app.themeMode = set.first,
              ),
            ],
          ),
          const SizedBox(height: 14),

          _Card(
            children: [
              _row(s.trackCount, '${store.tracks.length}', colors),
              Divider(color: colors.rim, height: 24),
              FutureBuilder<int>(
                future: store.storageUsedBytes(),
                builder: (context, snapshot) {
                  final bytes = snapshot.data ?? 0;
                  final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
                  return _row(s.storageUsed, '$mb MB', colors);
                },
              ),
            ],
          ),
          const SizedBox(height: 14),

          _Card(
            children: [
              _title(s.importFromPhone, colors),
              const SizedBox(height: 8),
              Text(
                s.importFromPhoneBody,
                style: TextStyle(fontSize: 13, height: 1.8, color: colors.secondaryText),
              ),
              const SizedBox(height: 14),
              const ImportDeviceButton(filled: false),
            ],
          ),
          const SizedBox(height: 14),

          _Card(
            children: [
              _title(s.restoreCovers, colors),
              const SizedBox(height: 8),
              Text(
                s.restoreCoversBody,
                style: TextStyle(fontSize: 13, height: 1.8, color: colors.secondaryText),
              ),
              const SizedBox(height: 14),
              const _RestoreCoversButton(),
            ],
          ),
          const SizedBox(height: 14),

          _Card(
            children: [
              _title(s.howToAdd, colors),
              const SizedBox(height: 8),
              Text(
                s.howToAddBody,
                style: TextStyle(fontSize: 13, height: 1.8, color: colors.secondaryText),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _Card(
            children: [
              _title(s.backgroundPlay, colors),
              const SizedBox(height: 8),
              Text(
                s.backgroundPlayBody,
                style: TextStyle(fontSize: 13, height: 1.8, color: colors.secondaryText),
              ),
            ],
          ),
          const SizedBox(height: 14),

          const _AboutCard(),
        ],
      ),
    );
  }

  Widget _title(String text, AppColors colors) => Text(
        text,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.primaryText),
      );

  Widget _row(String label, String value, AppColors colors) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 15, color: colors.primaryText)),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: accent),
          ),
        ],
      );
}

class _RestoreCoversButton extends StatefulWidget {
  const _RestoreCoversButton();

  @override
  State<_RestoreCoversButton> createState() => _RestoreCoversButtonState();
}

class _RestoreCoversButtonState extends State<_RestoreCoversButton> {
  bool _running = false;

  Future<void> _run() async {
    final s = context.read<AppState>().s;
    final importer = context.read<Importer>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _running = true);
    final count = await importer.backfillCovers();
    if (!mounted) return;
    setState(() => _running = false);
    messenger.showSnackBar(SnackBar(content: Text(s.coversRestored(count))));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _running ? null : _run,
        icon: _running
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: onAccent),
              )
            : const Icon(Icons.image_outlined, size: 18),
        label: Text(_running ? s.scanningPhone : s.restoreCovers),
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final s = context.watch<AppState>().s;

    return _Card(
      children: [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.graphic_eq, color: onAccent, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${s.versionLabel} $appVersion',
                    style: TextStyle(fontSize: 12.5, color: colors.secondaryText),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        Text(
          s.aboutTagline,
          style: TextStyle(fontSize: 13, height: 1.8, color: colors.secondaryText),
        ),
        const SizedBox(height: 14),

        Divider(color: colors.rim, height: 1),
        const SizedBox(height: 14),

        Text(
          s.developedBy,
          style: TextStyle(fontSize: 12.5, color: colors.secondaryText),
        ),
        const SizedBox(height: 2),
        Text(
          developerName,
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.bold,
            color: colors.primaryText,
          ),
        ),
        const SizedBox(height: 14),

        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _openSite(context),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(s.visitWebsite),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: onAccent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            developerSite.replaceFirst('https://', ''),
            style: TextStyle(fontSize: 12, color: colors.secondaryText),
          ),
        ),
      ],
    );
  }

  Future<void> _openSite(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(
      Uri.parse(developerSite),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      messenger.showSnackBar(const SnackBar(content: Text(developerSite)));
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Glass(
      elevated: false,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}
