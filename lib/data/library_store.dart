import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models.dart';

/// Everything the app owns lives under the app's documents directory:
///   media/    the audio files themselves
///   covers/   extracted artwork
///   library.json
class LibraryStore extends ChangeNotifier {
  LibraryStore._(this._root);

  final Directory _root;

  List<Track> _tracks = [];
  List<Playlist> _playlists = [];

  List<Track> get tracks => List.unmodifiable(_tracks);
  List<Playlist> get playlists => List.unmodifiable(_playlists);

  Directory get mediaDir => Directory(p.join(_root.path, 'media'));
  Directory get coversDir => Directory(p.join(_root.path, 'covers'));
  File get _indexFile => File(p.join(_root.path, 'library.json'));

  static Future<LibraryStore> open() async {
    final root = await getApplicationDocumentsDirectory();
    final store = LibraryStore._(root);
    await store.mediaDir.create(recursive: true);
    await store.coversDir.create(recursive: true);
    await store._load();
    return store;
  }

  /// Linked tracks play straight out of the phone's music folder; imported ones
  /// live in our own directory.
  String filePathOf(Track track) =>
      track.externalPath ?? p.join(mediaDir.path, track.fileName);

  bool hasTrackForPath(String externalPath) =>
      _tracks.any((t) => t.externalPath == externalPath);

  String? coverPathOf(Track track) =>
      track.coverName == null ? null : p.join(coversDir.path, track.coverName!);

  Track? byId(String id) {
    for (final track in _tracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  List<Track> byIds(Iterable<String> ids) =>
      ids.map(byId).whereType<Track>().toList();

  // MARK: - Mutations

  Future<void> add(Track track) async {
    _tracks.insert(0, track);
    await save();
  }

  /// Removes the track from the library. A linked file belongs to the user and
  /// is left exactly where it is — only copies we made are deleted.
  Future<void> delete(Track track) async {
    if (!track.isLinked) {
      final file = File(filePathOf(track));
      if (await file.exists()) await file.delete();
    }

    final cover = coverPathOf(track);
    if (cover != null) {
      final coverFile = File(cover);
      if (await coverFile.exists()) await coverFile.delete();
    }

    _tracks.removeWhere((t) => t.id == track.id);
    for (final playlist in _playlists) {
      playlist.trackIds.remove(track.id);
    }
    await save();
  }

  Future<void> toggleFavorite(Track track) async {
    track.favorite = !track.favorite;
    await save();
  }

  Future<void> markPlayed(Track track) async {
    track.playCount += 1;
    track.lastPlayedAt = DateTime.now();
    await save();
  }

  Future<void> createPlaylist(String name, {Track? withTrack}) async {
    _playlists.insert(
      0,
      Playlist(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        trackIds: withTrack == null ? [] : [withTrack.id],
        createdAt: DateTime.now(),
      ),
    );
    await save();
  }

  Future<void> deletePlaylist(Playlist playlist) async {
    _playlists.removeWhere((p) => p.id == playlist.id);
    await save();
  }

  Future<void> addToPlaylist(Playlist playlist, Track track) async {
    if (playlist.trackIds.contains(track.id)) return;
    playlist.trackIds.add(track.id);
    await save();
  }

  Future<void> removeFromPlaylist(Playlist playlist, Track track) async {
    playlist.trackIds.remove(track.id);
    await save();
  }

  Future<int> storageUsedBytes() async {
    if (!await mediaDir.exists()) return 0;
    var total = 0;
    await for (final entity in mediaDir.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  // MARK: - Persistence

  Future<void> save() async {
    final payload = jsonEncode({
      'version': 1,
      'tracks': _tracks.map((t) => t.toJson()).toList(),
      'playlists': _playlists.map((p) => p.toJson()).toList(),
    });
    await _indexFile.writeAsString(payload);
    notifyListeners();
  }

  Future<void> _load() async {
    if (!await _indexFile.exists()) return;
    try {
      final json = jsonDecode(await _indexFile.readAsString()) as Map<String, dynamic>;
      _tracks = (json['tracks'] as List)
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList();
      _playlists = (json['playlists'] as List)
          .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // A corrupt index must not brick the app; the audio files are still there
      // and can be re-imported.
      _tracks = [];
      _playlists = [];
    }
  }
}
