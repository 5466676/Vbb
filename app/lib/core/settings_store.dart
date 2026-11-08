import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// The free online server (Render, render.yaml). Settings or a `harb://server?url=...` link can
/// point the app at another one (e.g. the home server behind Tailscale Funnel).
const kDefaultServerUrl = 'https://harb-al-oqool.onrender.com';

/// Everything kept on the device between launches (shared_preferences).
class SettingsStore {
  SettingsStore(this._p);

  final SharedPreferences _p;

  static Future<SettingsStore> open() async => SettingsStore(await SharedPreferences.getInstance());

  /// Permanent player id for this device: a UUID v4 made on first launch.
  String get deviceId {
    var id = _p.getString('device_id');
    if (id == null) {
      id = const Uuid().v4();
      _p.setString('device_id', id);
    }
    return id;
  }

  /// In a browser the game talks to the site it was opened from (the server serves it at /play).
  String get serverUrl => _p.getString('server_url') ?? (kIsWeb ? Uri.base.origin : kDefaultServerUrl);
  Future<void> setServerUrl(String url) => _p.setString('server_url', normalizeServerUrl(url));

  String get name => _p.getString('name') ?? '';
  Future<void> setName(String v) => _p.setString('name', v.trim());

  String? get token => _p.getString('token');
  String? get playerId => _p.getString('player_id');
  Future<void> setSession(String token, String playerId, String name) async {
    await _p.setString('token', token);
    await _p.setString('player_id', playerId);
    if (this.name.isEmpty) await setName(name);
  }

  Future<void> clearSession() async {
    await _p.remove('token');
    await _p.remove('player_id');
  }

  /// Total experience on this device (offline matches, and online ones as the server counts them).
  int get xp => _p.getInt('xp') ?? 0;
  Future<void> setXp(int v) => _p.setInt('xp', v);

  String get army => _p.getString('army') ?? 'islamic';
  Future<void> setArmy(String v) => _p.setString('army', v);

  int get questionsVersion => _p.getInt('questions_version') ?? 0;
  Future<void> setQuestionsVersion(int v) => _p.setInt('questions_version', v);

  double get musicVolume => _p.getDouble('music_volume') ?? 0.6;
  double get sfxVolume => _p.getDouble('sfx_volume') ?? 0.9;
  double get voiceVolume => _p.getDouble('voice_volume') ?? 1.0;
  Future<void> setVolumes({double? music, double? sfx, double? voice}) async {
    if (music != null) await _p.setDouble('music_volume', music);
    if (sfx != null) await _p.setDouble('sfx_volume', sfx);
    if (voice != null) await _p.setDouble('voice_volume', voice);
  }
}

/// `https://pc.tail.ts.net/` -> `https://pc.tail.ts.net`; adds https:// when no scheme was typed.
String normalizeServerUrl(String raw) {
  var url = raw.trim();
  if (url.isEmpty) return '';
  if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'https://$url';
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// Overridden in main() with the opened store.
final settingsProvider = Provider<SettingsStore>((ref) => throw UnimplementedError('opened in main'));
