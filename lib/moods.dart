import 'package:flutter/material.dart';

/// A ready-made mood a track can be tagged with. Kept small and human — the
/// point is a quick "play by how I feel", not a taxonomy.
class Mood {
  const Mood(this.id, this.labelEn, this.labelFa, this.icon);

  final String id;
  final String labelEn;
  final String labelFa;
  final IconData icon;

  String label(bool fa) => fa ? labelFa : labelEn;
}

const moods = <Mood>[
  Mood('calm', 'Calm', 'آروم', Icons.spa_rounded),
  Mood('energetic', 'Energetic', 'پرانرژی', Icons.bolt_rounded),
  Mood('happy', 'Happy', 'شاد', Icons.wb_sunny_rounded),
  Mood('sad', 'Sad', 'دلتنگ', Icons.cloud_rounded),
  Mood('focus', 'Focus', 'تمرکز', Icons.center_focus_strong_rounded),
  Mood('romantic', 'Romantic', 'عاشقانه', Icons.favorite_rounded),
];

Mood? moodById(String id) {
  for (final m in moods) {
    if (m.id == id) return m;
  }
  return null;
}
