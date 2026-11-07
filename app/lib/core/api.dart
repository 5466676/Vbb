import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'settings_store.dart';

class ApiError implements Exception {
  ApiError(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => 'ApiError($status): $message';
}

/// REST calls to the game server (docs/PROTOCOL.md "Offline-first REST").
class Api {
  Api(this.settings, {http.Client? client}) : _http = client ?? http.Client();

  final SettingsStore settings;
  final http.Client _http;

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('${settings.serverUrl}$path').replace(queryParameters: query);

  Map<String, String> get _auth => {if (settings.token != null) 'Authorization': 'Bearer ${settings.token}'};

  Future<Map<String, dynamic>> _json(Future<http.Response> req, {Duration timeout = const Duration(seconds: 8)}) async {
    final res = await req.timeout(timeout);
    final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      final detail = body is Map ? body['detail'] : null;
      final msg = detail is Map
          ? (detail['message'] ?? detail['code']).toString()
          : (detail ?? res.reasonPhrase).toString();
      throw ApiError(res.statusCode, msg);
    }
    return body is Map<String, dynamic> ? body : {'data': body};
  }

  /// Quick check before online screens. Never throws: false when the server is off.
  Future<bool> health() async {
    if (settings.serverUrl.isEmpty) return false;
    try {
      final r = await _json(_http.get(_u('/health')), timeout: const Duration(seconds: 4));
      return r['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// Guest login with this device's UUID; stores the token.
  Future<void> login() async {
    final r = await _json(
      _http.post(
        _u('/auth/guest'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'device_id': settings.deviceId, 'name': settings.name}),
      ),
    );
    await settings.setSession(r['token'] as String, r['player_id'] as String, r['name'] as String);
  }

  Future<void> ensureLogin() async {
    if (settings.token == null) await login();
  }

  Future<Map<String, dynamic>> sync(List<Map<String, dynamic>> actions, int questionsSince) async {
    await ensureLogin();
    Future<Map<String, dynamic>> call() => _json(
      _http.post(
        _u('/sync'),
        headers: {'Content-Type': 'application/json', ..._auth},
        body: jsonEncode({'actions': actions, 'questions_since': questionsSince}),
      ),
    );
    try {
      return await call();
    } on ApiError catch (e) {
      if (e.status != 401) rethrow;
      await login(); // token expired or server secret changed
      return call();
    }
  }

  Future<Map<String, dynamic>> questions(int since) =>
      _json(_http.get(_u('/questions', {'since': '$since', 'limit': '1000'})));

  Future<Map<String, dynamic>> leaderboard({String period = 'all'}) =>
      _json(_http.get(_u('/leaderboard', {'period': period}), headers: _auth));

  Future<Map<String, dynamic>> myStats() async {
    await ensureLogin();
    return _json(_http.get(_u('/me/stats'), headers: _auth));
  }

  Future<String> setAccount(String username, String pin) async {
    await ensureLogin();
    final r = await _json(
      _http.post(
        _u('/auth/account'),
        headers: {'Content-Type': 'application/json', ..._auth},
        body: jsonEncode({'username': username, 'pin': pin}),
      ),
    );
    return r['username'] as String;
  }

  /// Move an account to this device (username + PIN).
  Future<void> restore(String username, String pin) async {
    final r = await _json(
      _http.post(
        _u('/auth/restore'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'pin': pin, 'device_id': settings.deviceId}),
      ),
    );
    await settings.setSession(r['token'] as String, r['player_id'] as String, r['name'] as String);
  }

  /// ws(s)://host/ws?token=... (the server also accepts the Authorization header; web sockets
  /// in browsers cannot send headers, and the home server runs without access logs).
  Uri socketUri() {
    final base = Uri.parse(settings.serverUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws',
      queryParameters: {'token': settings.token ?? ''},
    );
  }
}

final apiProvider = Provider<Api>((ref) => Api(ref.watch(settingsProvider)));
