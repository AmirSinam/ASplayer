import 'dart:io';

/// Small platform gate. The app is mobile-first; a few features (system media
/// controls, share-to-app, the home widget, system-volume control) only exist
/// on Android, and are simply skipped elsewhere.
class Plat {
  static bool get isAndroid => Platform.isAndroid;
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
