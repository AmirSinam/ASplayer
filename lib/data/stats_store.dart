import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models.dart';

/// On-device, private monthly listening stats — the data behind a future
/// "Your Month" capsule. No accounts, no network: everything is aggregated into
/// `stats.json` next to the library. Planted early on purpose, so the numbers
/// accrue from now even though the screen that shows them does not exist yet.
///
/// Writes are throttled and fire-and-forget so playback never waits on the disk.
class StatsStore {
  StatsStore._(this._file, this._months);

  final File _file;
  final Map<String, MonthStats> _months;

  bool _dirty = false;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<StatsStore> open() async {
    final root = await getApplicationDocumentsDirectory();
    final file = File(p.join(root.path, 'stats.json'));
    final months = <String, MonthStats>{};
    try {
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        (json['months'] as Map<String, dynamic>?)?.forEach((key, value) {
          months[key] = MonthStats.fromJson(value as Map<String, dynamic>);
        });
      }
    } catch (_) {
      // Corrupt stats must never brick playback; start fresh.
    }
    return StatsStore._(file, months);
  }

  /// The "YYYY-MM" key for a moment, in the device's local time.
  static String monthKey([DateTime? at]) {
    final d = at ?? DateTime.now();
    final m = d.month.toString().padLeft(2, '0');
    return '${d.year}-$m';
  }

  MonthStats? statsFor(String yearMonth) => _months[yearMonth];
  List<String> get months => _months.keys.toList()..sort();

  MonthStats _thisMonth() => _months.putIfAbsent(monthKey(), MonthStats.empty);

  /// Banks actual listening time against the current month and the track's
  /// artist(s). Called from a light heartbeat while playback is active.
  void addListening(Duration delta, Track track) {
    final secs = delta.inSeconds;
    if (secs <= 0) return;
    final month = _thisMonth();
    month.totalSeconds += secs;
    for (final artist in splitArtists(track.artist)) {
      month.secondsByArtist[artist] = (month.secondsByArtist[artist] ?? 0) + secs;
    }
    _dirty = true;
    _maybeFlush();
  }

  /// Records that a track started playing this month.
  void addPlay(Track track) {
    final month = _thisMonth();
    month.playsByTrack[track.id] = (month.playsByTrack[track.id] ?? 0) + 1;
    _dirty = true;
    _maybeFlush();
  }

  void _maybeFlush() {
    if (DateTime.now().difference(_lastSave) >= const Duration(seconds: 60)) flush();
  }

  Future<void> flush() async {
    if (!_dirty) return;
    _dirty = false;
    _lastSave = DateTime.now();
    try {
      await _file.writeAsString(jsonEncode({
        'version': 1,
        'months': {for (final e in _months.entries) e.key: e.value.toJson()},
      }));
    } catch (_) {
      // A failed stats write is not worth surfacing; try again next tick.
      _dirty = true;
    }
  }
}

/// One month's aggregate. Kept compact so `stats.json` stays small over years.
class MonthStats {
  MonthStats(this.totalSeconds, this.secondsByArtist, this.playsByTrack);
  MonthStats.empty() : this(0, {}, {});

  int totalSeconds;
  final Map<String, int> secondsByArtist;
  final Map<String, int> playsByTrack;

  /// The artist with the most listening seconds this month, or null if empty.
  String? get topArtist {
    String? best;
    var bestSecs = -1;
    secondsByArtist.forEach((artist, secs) {
      if (secs > bestSecs) {
        bestSecs = secs;
        best = artist;
      }
    });
    return best;
  }

  /// The track id played most this month, or null if empty.
  String? get topTrackId {
    String? best;
    var bestPlays = -1;
    playsByTrack.forEach((id, plays) {
      if (plays > bestPlays) {
        bestPlays = plays;
        best = id;
      }
    });
    return best;
  }

  int get uniqueTracks => playsByTrack.length;

  Map<String, dynamic> toJson() => {
        'totalSeconds': totalSeconds,
        'secondsByArtist': secondsByArtist,
        'playsByTrack': playsByTrack,
      };

  factory MonthStats.fromJson(Map<String, dynamic> json) => MonthStats(
        json['totalSeconds'] as int? ?? 0,
        (json['secondsByArtist'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
            {},
        (json['playsByTrack'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
            {},
      );
}
