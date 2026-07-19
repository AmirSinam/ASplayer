import 'l10n.dart';

/// Splits a combined artist tag into the people in it. Handles the common
/// joiners — "feat", "ft", "&", "x", "×", and commas — so "Yas & Sohrab" or
/// "A x B" each become two artists. Word-boundary "x" avoids cutting names
/// like "Max". Slashes are left alone on purpose (AC/DC, R/B).
final _artistSplit = RegExp(
  r'\s*(?:feat\.?|ft\.?|featuring|&|،|,|\bx\b|×)\s*',
  caseSensitive: false,
);

List<String> splitArtists(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [];
  final seen = <String>{};
  final parts = <String>[];
  for (final piece in trimmed.split(_artistSplit)) {
    final name = piece.trim();
    if (name.isEmpty) continue;
    if (seen.add(name.toLowerCase())) parts.add(name);
  }
  return parts.isEmpty ? [trimmed] : parts;
}

class Track {
  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.fileName,
    this.externalPath,
    this.coverName,
    required this.addedAt,
    this.lastPlayedAt,
    this.playCount = 0,
    this.favorite = false,
    this.lyrics = '',
    List<int>? bookmarksMs,
    List<String>? moods,
  })  : bookmarksMs = bookmarksMs ?? [],
        moods = moods ?? [];

  final String id;
  String title;

  /// Empty when the file carried no artist tag — the label is chosen at display
  /// time so it follows the app language.
  String artist;
  String album;
  int durationMs;

  /// Relative to the app's media directory. Never store an absolute path:
  /// on Android the app directory changes between installs.
  final String fileName;

  /// Set when the song lives in the phone's own music folder and was linked
  /// rather than copied. The file belongs to the user, not to this app: we read
  /// it, and removing the track from the library must never delete it.
  final String? externalPath;

  String? coverName;

  final DateTime addedAt;
  DateTime? lastPlayedAt;
  int playCount;
  bool favorite;

  /// Raw lyrics — either LRC (timestamped, synced) or plain text.
  String lyrics;

  /// Saved moments in the song, in milliseconds, so the user can jump straight
  /// to a favourite part later. Kept sorted.
  final List<int> bookmarksMs;

  /// Free-form mood tags the user attaches (calm, energetic, focus…), used to
  /// play "by how I feel" rather than by name.
  final List<String> moods;

  Duration get duration => Duration(milliseconds: durationMs);

  bool get hasLyrics => lyrics.trim().isNotEmpty;

  bool get isLinked => externalPath != null;

  String artistName(Strings s) => artist.isEmpty ? s.unknownArtist : artist;
  String albumName(Strings s) => album.isEmpty ? s.noAlbum : album;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': durationMs,
        'fileName': fileName,
        'externalPath': externalPath,
        'coverName': coverName,
        'addedAt': addedAt.toIso8601String(),
        'lastPlayedAt': lastPlayedAt?.toIso8601String(),
        'playCount': playCount,
        'favorite': favorite,
        'lyrics': lyrics,
        'bookmarksMs': bookmarksMs,
        'moods': moods,
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String? ?? '',
        album: json['album'] as String? ?? '',
        durationMs: json['durationMs'] as int? ?? 0,
        fileName: json['fileName'] as String,
        externalPath: json['externalPath'] as String?,
        coverName: json['coverName'] as String?,
        addedAt: DateTime.parse(json['addedAt'] as String),
        lastPlayedAt: json['lastPlayedAt'] == null
            ? null
            : DateTime.parse(json['lastPlayedAt'] as String),
        playCount: json['playCount'] as int? ?? 0,
        favorite: json['favorite'] as bool? ?? false,
        lyrics: json['lyrics'] as String? ?? '',
        bookmarksMs: (json['bookmarksMs'] as List?)?.cast<int>() ?? [],
        moods: (json['moods'] as List?)?.cast<String>() ?? [],
      );
}

class Playlist {
  Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
    required this.createdAt,
    this.mixtape = false,
  });

  final String id;
  String name;
  final List<String> trackIds;
  final DateTime createdAt;

  /// A mixtape plays with crossfade forced on, as one continuous set.
  final bool mixtape;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'createdAt': createdAt.toIso8601String(),
        'mixtape': mixtape,
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String,
        trackIds: (json['trackIds'] as List).cast<String>(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        mixtape: json['mixtape'] as bool? ?? false,
      );
}

/// The chips across the top of the home screen. Everything here is derived from
/// the user's own library — there is no server, so "popular" would be meaningless.
enum Collection {
  all,
  favorites,
  mostPlayed,
  recentlyAdded;

  String title(Strings s) => switch (this) {
        Collection.all => s.all,
        Collection.favorites => s.favorites,
        Collection.mostPlayed => s.mostPlayed,
        Collection.recentlyAdded => s.recentlyAdded,
      };

  String emptyMessage(Strings s) => switch (this) {
        Collection.favorites => s.noFavoritesYet,
        Collection.mostPlayed => s.nothingPlayedYet,
        _ => s.nothingHere,
      };

  List<Track> apply(List<Track> tracks) {
    switch (this) {
      case Collection.all:
        return tracks;
      case Collection.favorites:
        return tracks.where((t) => t.favorite).toList();
      case Collection.mostPlayed:
        final played = tracks.where((t) => t.playCount > 0).toList()
          ..sort((a, b) => b.playCount.compareTo(a.playCount));
        return played;
      case Collection.recentlyAdded:
        return [...tracks]..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    }
  }
}

enum SortOption {
  dateAdded,
  title,
  artist,
  duration;

  String label(Strings s) => switch (this) {
        SortOption.dateAdded => s.sortNewest,
        SortOption.title => s.sortTitle,
        SortOption.artist => s.sortArtist,
        SortOption.duration => s.sortDuration,
      };

  List<Track> apply(List<Track> tracks) {
    final list = [...tracks];
    switch (this) {
      case SortOption.dateAdded:
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case SortOption.title:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case SortOption.artist:
        list.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
      case SortOption.duration:
        list.sort((a, b) => a.durationMs.compareTo(b.durationMs));
    }
    return list;
  }
}

enum LibrarySection {
  songs,
  artists,
  albums,
  playlists;

  String title(Strings s) => switch (this) {
        LibrarySection.songs => s.songs,
        LibrarySection.artists => s.artists,
        LibrarySection.albums => s.albums,
        LibrarySection.playlists => s.playlists,
      };
}

/// Not named RepeatMode: Flutter's material library exports its own.
enum Repeat { off, all, one }
