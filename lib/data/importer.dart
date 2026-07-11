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
        if (tags.pictures.isNotEmpty) {
          coverName = '$id.img';
          await File(p.join(store.coversDir.path, coverName))
              .writeAsBytes(tags.pictures.first.bytes);
        }
      } catch (_) {
        // No readable tags: the media database entry is enough to play it.
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

      if (tags.pictures.isNotEmpty) {
        coverName = '$id.img';
        await File(p.join(store.coversDir.path, coverName))
            .writeAsBytes(tags.pictures.first.bytes);
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
