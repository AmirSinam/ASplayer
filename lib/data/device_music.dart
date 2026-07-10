import 'package:flutter/services.dart';

/// One song as the phone's media database knows it.
class DeviceSong {
  const DeviceSong({
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.path,
  });

  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String path;

  factory DeviceSong.fromMap(Map<dynamic, dynamic> map) => DeviceSong(
        title: (map['title'] as String?) ?? '',
        artist: (map['artist'] as String?) ?? '',
        album: (map['album'] as String?) ?? '',
        durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
        path: map['path'] as String,
      );
}

/// Reads the songs already sitting on the phone — the same list Samsung Music
/// and every other player shows. Android only; elsewhere it finds nothing.
class DeviceMusic {
  static const _channel = MethodChannel('ir.aspoormehr.asplayer/device_music');

  static Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Shows the system permission dialog. Returns false if the user says no.
  static Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<List<DeviceSong>> scan() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('scan') ?? [];
      return raw
          .cast<Map<dynamic, dynamic>>()
          .map(DeviceSong.fromMap)
          .where((song) => song.path.isNotEmpty)
          .toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}
