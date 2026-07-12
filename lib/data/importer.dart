import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../models.dart';
import 'device_music.dart';
import 'library_store.dart';

class Importer {
  Importer(this.store);

  final LibraryStore store;

  /// Opens the system picker. Returns how many files were added.
  Future<int> pickAndImport() async {
    final result = await FilePicker.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null) return 0;

    final paths = result.files.map((f) => f.path).whereType<String>();
    return importPaths(paths);
  }

  /// Copies each file into the app's own storage and reads its embedded tags.
  Future<int> importPaths(Iterable<String> sourcePaths) async {
    var added = 0;

    for (final source in sourcePaths) {
      final sourceFile = File(source);
      if (!await sourceFile.exists()) continue;

      final id = '${DateTime.now().microsecondsSinceEpoch}_$added';
      final extension = p.extension(source).isEmpty ? '.mp3' : p.extension(source);
      final fileName = '$id$extension';
      final destination = File(p.join(store.mediaDir.path, fileName));

      try {
        await sourceFile.copy(destination.path);
      } catch (_) {
        continue;
      }

      final track = await _readTags(destination, id: id, fileName: fileName, fallback: source);
      await store.add(track);
      added++;
    }

    return added;
  }

  /// Links songs the phone already holds. Nothing is copied: a linked track
  /// plays straight out of the user's own music folder.
  ///
  /// Cover art is not in the media database, so it is pulled from each file's
  /// tags — which is why this reports progress instead of blocking.
  Future<int> linkDeviceSongs(
    List<DeviceSong> songs, {
    void Function(int done, int total)? onProgress,
  }) async {
    var added = 0;

    for (var i = 0; i < songs.length; i++) {
      final song = songs[i];
      onProgress?.call(i, songs.length);

      if (store.hasTrackForPath(song.path)) continue;
      final file = File(song.path);
      if (!await file.exists()) continue;

      final id = '${DateTime.now().microsecondsSinceEpoch}_$added';
      String? coverName;
      try {
        final tags = readMetadata(file, getImage: true);
        final art = _firstCover(tags.pictures);
        if (art != null) {
          coverName = '$id.img';
          await File(p.join(store.coversDir.path, coverName)).writeAsBytes(art);
        }
      } catch (_) {
        // No readable tags: the media database entry is enough to play it.
      }

      // Most phone songs keep their art in the media database, not in the file,
      // so fall back to the album-art thumbnail when the tags carried none.
      if (coverName == null) {
        final art = await DeviceMusic.albumArt(song.albumId);
        if (art != null && art.isNotEmpty) {
          coverName = '$id.img';
          await File(p.join(store.coversDir.path, coverName)).writeAsBytes(art);
        }
      }

      await store.add(Track(
        id: id,
        title: song.title.isEmpty ? p.basenameWithoutExtension(song.path) : song.title,
        artist: song.artist,
        album: song.album,
        durationMs: song.durationMs,
        fileName: p.basename(song.path),
        externalPath: song.path,
        coverName: coverName,
        addedAt: DateTime.now(),
      ));
      added++;
    }

    onProgress?.call(songs.length, songs.length);
    return added;
  }

  /// Fills in covers for songs already in the library that have none — reading
  /// each file's own art first, then the phone's media database for linked
  /// songs. Returns how many covers were recovered.
  Future<int> backfillCovers({void Function(int done, int total)? onProgress}) async {
    final missing = store.tracks.where((t) => t.coverName == null).toList();
    if (missing.isEmpty) return 0;

    // Scan the phone once, and only if some gaps are linked (device) songs.
    final deviceByPath = <String, DeviceSong>{};
    if (missing.any((t) => t.externalPath != null)) {
      for (final song in await DeviceMusic.scan()) {
        deviceByPath[song.path] = song;
      }
    }

    var fixed = 0;
    for (var i = 0; i < missing.length; i++) {
      final track = missing[i];
      onProgress?.call(i, missing.length);

      List<int>? art;
      final file = File(store.filePathOf(track));
      if (await file.exists()) {
        try {
          art = _firstCover(readMetadata(file, getImage: true).pictures);
        } catch (_) {
          // Unreadable tags — fall through to the media database.
        }
      }
      if (art == null && track.externalPath != null) {
        final song = deviceByPath[track.externalPath];
        if (song != null) {
          final bytes = await DeviceMusic.albumArt(song.albumId);
          if (bytes != null && bytes.isNotEmpty) art = bytes;
        }
      }
      if (art != null && art.isNotEmpty) {
        await store.setCover(track, art);
        fixed++;
      }
    }
    onProgress?.call(missing.length, missing.length);
    return fixed;
  }

  /// The first embedded picture that actually carries bytes. Some files ship an
  /// empty artwork frame, which would otherwise be saved as an undecodable
  /// zero-byte cover that never loads.
  List<int>? _firstCover(List<Picture> pictures) {
    for (final picture in pictures) {
      if (picture.bytes.isNotEmpty) return picture.bytes;
    }
    return null;
  }

  Future<Track> _readTags(
    File file, {
    required String id,
    required String fileName,
    required String fallback,
  }) async {
    String title = p.basenameWithoutExtension(fallback);
    String artist = '';
    String album = '';
    String lyrics = '';
    int durationMs = 0;
    String? coverName;

    try {
      final tags = readMetadata(file, getImage: true);

      final tagTitle = tags.title?.trim();
      if (tagTitle != null && tagTitle.isNotEmpty) title = tagTitle;

      artist = tags.artist?.trim() ?? '';
      album = tags.album?.trim() ?? '';
      lyrics = tags.lyrics?.trim() ?? '';
      durationMs = tags.duration?.inMilliseconds ?? 0;

      final art = _firstCover(tags.pictures);
      if (art != null) {
        coverName = '$id.img';
        await File(p.join(store.coversDir.path, coverName)).writeAsBytes(art);
      }
    } catch (_) {
      // A file with unreadable or missing tags is still a playable file.
    }

    return Track(
      id: id,
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      fileName: fileName,
      coverName: coverName,
      lyrics: lyrics,
      addedAt: DateTime.now(),
    );
  }
}
