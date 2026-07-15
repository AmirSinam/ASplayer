import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../audio/eq_presets.dart';
import '../audio/player_controller.dart';
import '../l10n.dart';
import '../theme.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  // Fetched once; the effect's band layout doesn't change under us.
  Future<AndroidEqualizerParameters>? _params;

  @override
  void initState() {
    super.initState();
    final player = context.read<PlayerController>();
    if (player.eqAvailable) _params = player.eqParameters;
  }

  String _freqLabel(double f) {
    if (f >= 1000) {
      final k = f / 1000;
      return '${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}k';
    }
    return f.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final app = context.watch<AppState>();
    final player = context.watch<PlayerController>();
    final s = app.s;
    final fa = app.lang == Lang.fa;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(s.equalizer),
        backgroundColor: Colors.transparent,
        foregroundColor: colors.primaryText,
        actions: [
          if (player.eqAvailable)
            TextButton(
              onPressed: () => player.applyEqPreset('flat'),
              child: Text(s.eqReset, style: const TextStyle(color: accent)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Glass(
            elevated: false,
            padding: const EdgeInsets.fromLTRB(18, 6, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.equalizer,
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold, color: colors.primaryText),
                  ),
                ),
                Switch(
                  value: player.eqEnabled,
                  activeThumbColor: accent,
                  onChanged: player.eqAvailable ? player.setEqEnabled : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            player.eqAvailable ? s.equalizerBody : s.eqAndroidOnly,
            style: TextStyle(fontSize: 13, height: 1.7, color: colors.secondaryText),
          ),
          const SizedBox(height: 18),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: eqPresets.map((p) {
              final selected = player.eqPreset == p.id;
              return GestureDetector(
                onTap: player.eqAvailable ? () => player.applyEqPreset(p.id) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? accent : colors.glass,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: selected ? accent : colors.rim),
                  ),
                  child: Text(
                    p.label(fa),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? onAccent : colors.secondaryText,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 22),

          if (player.eqAvailable)
            FutureBuilder<AndroidEqualizerParameters>(
              future: _params,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(s.eqPlayToTune,
                          style: TextStyle(color: colors.secondaryText)),
                    ),
                  );
                }
                return _Bands(
                  params: snap.data!,
                  player: player,
                  enabled: player.eqEnabled,
                  freqLabel: _freqLabel,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _Bands extends StatelessWidget {
  const _Bands({
    required this.params,
    required this.player,
    required this.enabled,
    required this.freqLabel,
  });

  final AndroidEqualizerParameters params;
  final PlayerController player;
  final bool enabled;
  final String Function(double) freqLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final gains = player.eqGains;

    // Force left‑to‑right so low frequencies always sit on the left.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: 250,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(params.bands.length, (i) {
              final band = params.bands[i];
              final raw = gains.length == params.bands.length ? gains[i] : band.gain;
              final value =
                  raw.clamp(params.minDecibels, params.maxDecibels).toDouble();
              return SizedBox(
                width: 62,
                child: Column(
                  children: [
                    Text(
                      '${value >= 0 ? '+' : ''}${value.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: enabled ? accent : colors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: accent,
                            thumbColor: accent,
                            inactiveTrackColor: colors.rim,
                            trackHeight: 3,
                          ),
                          child: Slider(
                            value: value,
                            min: params.minDecibels,
                            max: params.maxDecibels,
                            onChanged: enabled ? (v) => player.setEqBand(i, v) : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      freqLabel(band.centerFrequency),
                      style: TextStyle(fontSize: 11, color: colors.secondaryText),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
