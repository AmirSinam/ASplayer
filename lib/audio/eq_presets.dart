import 'dart:math';

/// A named equalizer curve. The curve is stored as anchor points (frequency in
/// Hz → gain in dB) and interpolated in log‑frequency space, so it maps cleanly
/// onto whatever band layout a given phone's equalizer happens to expose.
class EqPreset {
  const EqPreset(this.id, this.labelEn, this.labelFa, this.anchors);

  final String id;
  final String labelEn;
  final String labelFa;
  final Map<int, double> anchors;

  String label(bool fa) => fa ? labelFa : labelEn;

  /// Gain (dB) this preset wants at [freqHz], interpolated between anchors.
  double gainAt(double freqHz) {
    final freqs = anchors.keys.toList()..sort();
    if (freqHz <= freqs.first) return anchors[freqs.first]!;
    if (freqHz >= freqs.last) return anchors[freqs.last]!;
    for (var i = 0; i < freqs.length - 1; i++) {
      final a = freqs[i];
      final b = freqs[i + 1];
      if (freqHz >= a && freqHz <= b) {
        final t = (log(freqHz) - log(a)) / (log(b) - log(a));
        return anchors[a]! + (anchors[b]! - anchors[a]!) * t;
      }
    }
    return 0;
  }
}

/// The built‑in modes. Curves are tuned to sound balanced rather than extreme —
/// boosts stay within a range most phone equalizers can honour without clipping.
const eqPresets = <EqPreset>[
  EqPreset('flat', 'Flat', 'تخت', {60: 0, 14000: 0}),
  EqPreset('bass', 'Bass boost', 'تقویت بم', {60: 7, 250: 4, 1000: 0, 14000: 0}),
  EqPreset('treble', 'Treble boost', 'تقویت زیر', {60: 0, 1000: 0, 4000: 3, 14000: 7}),
  EqPreset('vocal', 'Vocal', 'صدای خواننده', {60: -2, 250: 1, 1000: 4, 3000: 4, 14000: 0}),
  EqPreset('pop', 'Pop', 'پاپ', {60: -1, 250: 2, 1000: 4, 3500: 2, 14000: -1}),
  EqPreset('rock', 'Rock', 'راک', {60: 5, 250: 2, 1000: -1, 3500: 2, 14000: 5}),
  EqPreset('jazz', 'Jazz', 'جز', {60: 3, 250: 1, 1000: -1, 4000: 1, 14000: 3}),
  EqPreset('classical', 'Classical', 'کلاسیک', {60: 4, 250: 2, 1000: -1, 4000: 2, 14000: 3}),
  EqPreset('dance', 'Dance', 'دنس', {60: 6, 250: 2, 1000: 0, 4000: 3, 14000: 5}),
  EqPreset('night', 'Late night', 'شبانه', {60: 3, 250: 1, 1000: 2, 4000: -1, 14000: -4}),
];
