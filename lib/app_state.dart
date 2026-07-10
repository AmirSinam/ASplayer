import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';

class AppState extends ChangeNotifier {
  AppState._(this._prefs, this._lang, this._themeMode, this._onboarded);

  final SharedPreferences _prefs;

  Lang _lang;
  ThemeMode _themeMode;
  bool _onboarded;
  int _tab = 0;

  /// English by default; Persian only if the user picks it.
  static Future<AppState> load() async {
    final prefs = await SharedPreferences.getInstance();

    final lang = Lang.values.firstWhere(
      (l) => l.name == prefs.getString('language'),
      orElse: () => Lang.en,
    );
    final themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == prefs.getString('appearance'),
      orElse: () => ThemeMode.system,
    );

    return AppState._(prefs, lang, themeMode, prefs.getBool('onboarded') ?? false);
  }

  Lang get lang => _lang;
  ThemeMode get themeMode => _themeMode;
  bool get onboarded => _onboarded;
  int get tab => _tab;

  Strings get s => _lang == Lang.fa ? Strings.fa : Strings.en;

  set lang(Lang value) {
    _lang = value;
    _prefs.setString('language', value.name);
    notifyListeners();
  }

  set themeMode(ThemeMode value) {
    _themeMode = value;
    _prefs.setString('appearance', value.name);
    notifyListeners();
  }

  set tab(int value) {
    _tab = value;
    notifyListeners();
  }

  void finishOnboarding() {
    _onboarded = true;
    _prefs.setBool('onboarded', true);
    notifyListeners();
  }
}
