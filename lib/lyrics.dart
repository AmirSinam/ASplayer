/// One line of lyrics. [time] is null for plain (untimed) lyrics.
class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration? time;
  final String text;
}

/// Parsed lyrics for a track.
class Lyrics {
  Lyrics(this.lines, this.synced);

  final List<LyricLine> lines;

  /// True when at least some lines carry timestamps (LRC), so playback can
  /// highlight the current line.
  final bool synced;

  bool get isEmpty => lines.isEmpty;

  /// Index of the line that should be active at [position], or -1.
  int activeIndex(Duration position) {
    if (!synced) return -1;
    var found = -1;
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].time;
      if (t != null && t <= position) {
        found = i;
      } else if (t != null && t > position) {
        break;
      }
    }
    return found;
  }

  // [mm:ss.xx] or [mm:ss] — LRC timestamps, possibly several per line.
  static final _tag = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');

  static Lyrics parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return Lyrics(const [], false);

    final timed = <LyricLine>[];
    var sawTag = false;

    for (final rawLine in text.split('\n')) {
      final matches = _tag.allMatches(rawLine).toList();
      if (matches.isEmpty) continue;
      sawTag = true;
      final body = rawLine.replaceAll(_tag, '').trim();
      for (final m in matches) {
        final min = int.parse(m.group(1)!);
        final sec = int.parse(m.group(2)!);
        final frac = m.group(3);
        final ms = frac == null ? 0 : int.parse(frac.padRight(3, '0').substring(0, 3));
        timed.add(LyricLine(Duration(minutes: min, seconds: sec, milliseconds: ms), body));
      }
    }

    if (sawTag) {
      timed.sort((a, b) => a.time!.compareTo(b.time!));
      return Lyrics(timed, true);
    }

    // Plain text: keep every line, blanks included for spacing.
    final plain = text.split('\n').map((l) => LyricLine(null, l.trim())).toList();
    return Lyrics(plain, false);
  }
}
