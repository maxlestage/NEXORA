import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Où NEXORA garde ses données : les secrets (clés d'API, jeton GitHub) dans le
/// trousseau de l'appareil (Keychain sur iOS, Keystore sur Android), le reste
/// (conversations, agents, réglages) dans les préférences.
class Storage {
  Storage._(this._prefs);

  final SharedPreferences _prefs;
  static const _secure = FlutterSecureStorage();

  /// Les secrets lus au démarrage, pour ne pas attendre le trousseau à chaque appel.
  final Map<String, String> _secrets = {};

  static Future<Storage> open() async {
    final prefs = await SharedPreferences.getInstance();
    final s = Storage._(prefs);
    try {
      s._secrets.addAll(
        await _secure.readAll().timeout(const Duration(seconds: 5)),
      );
    } catch (_) {
      // Trousseau indisponible (tests, certains navigateurs) : rien de grave.
    }
    return s;
  }

  String? secret(String key) => _secrets[key];

  Future<void> setSecret(String key, String? value) async {
    if (value == null || value.isEmpty) {
      _secrets.remove(key);
      try {
        await _secure.delete(key: key);
      } catch (_) {}
    } else {
      _secrets[key] = value;
      try {
        await _secure.write(key: key, value: value);
      } catch (_) {}
    }
  }

  Future<void> wipeSecrets() async {
    _secrets.clear();
    try {
      await _secure.deleteAll();
    } catch (_) {}
  }

  dynamic readJson(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String key, Object? value) =>
      _prefs.setString(key, jsonEncode(value));

  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String? value) async {
    if (value == null) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, value);
    }
  }

  bool getBool(String key, {bool fallback = false}) =>
      _prefs.getBool(key) ?? fallback;
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  double getDouble(String key, {double fallback = 0}) =>
      _prefs.getDouble(key) ?? fallback;
  Future<void> setDouble(String key, double value) =>
      _prefs.setDouble(key, value);

  Future<void> clearAll() async {
    await _prefs.clear();
    await wipeSecrets();
  }
}
