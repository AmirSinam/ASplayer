import 'package:flutter/services.dart';

/// One song as the phone's media database knows it.
class DeviceSong {
  const DeviceSong({
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.path,
    this.albumId = 0,
  });

  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String path;

  /// The MediaStore album this song belongs to — used to fetch the cached
  /// album-art thumbnail when the file itself carries no embedded picture.
  final int albumId;

  factory DeviceSong.fromMap(Map<dynamic, dynamic> map) => DeviceSong(
        title: (map['title'] as String?) ?? '',
        artist: (map['artist'] as String?) ?? '',
        album: (map['album'] as String?) ?? '',
        durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
        path: map['path'] as String,
        albumId: (map['albumId'] as num?)?.toInt() ?? 0,
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

  /// The cached album-art thumbnail for a MediaStore album, or null when there
  /// is none (or off-Android). Used to cover device songs whose files carry no
  /// embedded picture.
  static Future<Uint8List?> albumArt(int albumId) async {
    if (albumId <= 0) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('albumArt', albumId);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
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

  /// Current system media volume, 0..1. Falls back to 1 off-Android.
  static Future<double> getVolume() async {
    try {
      return (await _channel.invokeMethod<double>('getVolume')) ?? 1.0;
    } on PlatformException {
      return 1.0;
    } on MissingPluginException {
      return 1.0;
    }
  }

  /// Sets the system media volume — the same one the hardware buttons move.
  static Future<void> setVolume(double fraction) async {
    try {
      await _channel.invokeMethod('setVolume', fraction);
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }
}
