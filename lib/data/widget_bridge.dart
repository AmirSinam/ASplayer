import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pushes now-playing state to the home-screen widget. State goes through
/// SharedPreferences (which the native widget reads); a channel ping tells the
/// widget to repaint. Android only; a no-op everywhere else.
class WidgetBridge {
  static const _channel = MethodChannel('ir.aspoormehr.asplayer/widget');

  static Future<void> update({
    required String title,
    required String artist,
    String? coverPath,
    required bool playing,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('widget_title', title);
      await prefs.setString('widget_artist', artist);
      if (coverPath != null) {
        await prefs.setString('widget_cover', coverPath);
      } else {
        await prefs.remove('widget_cover');
      }
      await prefs.setBool('widget_playing', playing);
      await _channel.invokeMethod('refresh');
    } on PlatformException {
      // Widget not present or platform without support; ignore.
    } on MissingPluginException {
      // Non-Android platform.
    }
  }
}
