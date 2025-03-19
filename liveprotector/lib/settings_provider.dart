import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  late String _baseUrl = "";
  String get baseUrl => _baseUrl;
  
  late SharedPreferences _preferences;

  set baseUrl(String newValue) {
    _baseUrl = newValue;
    _preferences.setString("base_url", newValue);
    notifyListeners();
  }

  SettingsProvider() {
    loadSettings();
  }

  Future<void> loadSettings() async {
    _preferences = await SharedPreferences.getInstance();

    _baseUrl = _preferences.getString("base_url") ?? _baseUrl;

    notifyListeners();
  }

}