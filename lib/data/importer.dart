import 'dart:io';

import 'package:audiotags/audiotags.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../models.dart';
import 'library_store.dart';

class Importer {
  Importer(this.store);

  final LibraryStore store;

  /// Opens the system picker. Returns how many files were added.
  Future<int> pickAndImport() async {
    final result = await FilePicker.platform.pickFiles(
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

  Future<Track> _readTags(
    File file, {
    required String id,
    required String fileName,
    required String fallback,
  }) async {
    String title = p.basenameWithoutExtension(fallback);
    String artist = '';
    String album = '';
    int durationMs = 0;
    String? coverName;

    try {
      final tag = await AudioTags.read(file.path);
      if (tag != null) {
        if (tag.title != null && tag.title!.trim().isNotEmpty) title = tag.title!.trim();
        artist = tag.trackArtist?.trim() ?? '';
        album = tag.album?.trim() ?? '';
        durationMs = (tag.duration ?? 0) * 1000;

        if (tag.pictures.isNotEmpty) {
          coverName = '$id.img';
          await File(p.join(store.coversDir.path, coverName)).writeAsBytes(tag.pictures.first.bytes);
        }
      }
    } catch (_) {
      // A file with unreadable tags is still a playable file.
    }

    return Track(
      id: id,
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      fileName: fileName,
      coverName: coverName,
      addedAt: DateTime.now(),
    );
  }
}
