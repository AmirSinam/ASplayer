import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/library_store.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class EditTrackScreen extends StatefulWidget {
  const EditTrackScreen({super.key, required this.track});

  final Track track;

  @override
  State<EditTrackScreen> createState() => _EditTrackScreenState();
}

class _EditTrackScreenState extends State<EditTrackScreen> {
  late final TextEditingController _title;
  late final TextEditingController _artist;
  late final TextEditingController _album;
  late final TextEditingController _lyrics;
  int _coverBump = 0; // forces the preview to reload after a cover change

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.track.title);
    _artist = TextEditingController(text: widget.track.artist);
    _album = TextEditingController(text: widget.track.album);
    _lyrics = TextEditingController(text: widget.track.lyrics);
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _lyrics.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final store = context.read<LibraryStore>();
    final result = await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    List<int>? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      try {
        bytes = await File(file.path!).readAsBytes();
      } catch (_) {
        bytes = null;
      }
    }
    if (bytes == null) return;

    await store.setCover(widget.track, bytes);
    if (mounted) setState(() => _coverBump++);
  }

  Future<void> _save() async {
    final store = context.read<LibraryStore>();
    await store.editTrack(
      widget.track,
      title: _title.text.trim().isEmpty ? widget.track.title : _title.text.trim(),
      artist: _artist.text.trim(),
      album: _album.text.trim(),
      lyrics: _lyrics.text,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final s = context.watch<AppState>().s;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(s.editSong),
        backgroundColor: Colors.transparent,
        foregroundColor: colors.primaryText,
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(s.save, style: const TextStyle(color: accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickCover,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    // The bump key rebuilds the image when the cover file changes.
                    child: Artwork(key: ValueKey(_coverBump), track: widget.track, radius: R.tile),
                  ),
                  Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: accent, shape: BoxShape.circle),
                    child: const Icon(Icons.photo_camera, color: onAccent, size: 18),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(onPressed: _pickCover, child: Text(s.changeCover)),
          ),
          const SizedBox(height: 12),

          _field(s.fieldTitle, _title, colors),
          _field(s.fieldArtist, _artist, colors),
          _field(s.fieldAlbum, _album, colors),
          const SizedBox(height: 8),
          _field(s.lyrics, _lyrics, colors, maxLines: 8, hint: s.lyricsHint),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, AppColors colors,
      {int maxLines = 1, String? hint}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        minLines: maxLines > 1 ? 4 : 1,
        style: TextStyle(color: colors.primaryText),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: colors.secondaryText, fontSize: 12),
          filled: true,
          fillColor: colors.glass,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: colors.rim),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: colors.rim),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: accent),
          ),
        ),
      ),
    );
  }
}
