import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';

/// One server message: `{"type", "seq", "payload"}` (docs/PROTOCOL.md).
class ServerMessage {
  ServerMessage(this.type, this.payload);
  final String type;
  final Map<String, dynamic> payload;
}

enum SocketStatus { offline, connecting, online }

/// Where the game's messages come from: the online server ([GameSocket]) or a match
/// running inside the app against bots (LocalGame). Both speak docs/PROTOCOL.md.
abstract class GameTransport {
  Stream<ServerMessage> get messages;
  Stream<SocketStatus> get statusStream;
  SocketStatus get status;
  Future<void> connect();
  void send(String type, [Map<String, dynamic> payload = const {}]);
  Future<void> close();
}

/// The game socket. Reconnects by itself with backoff; the server answers a reconnect
/// with `full_state`, so the UI never has to replay anything.
class GameSocket implements GameTransport {
  GameSocket(this.api);

  final Api api;
  final _messages = StreamController<ServerMessage>.broadcast();
  final _status = StreamController<SocketStatus>.broadcast();
  WebSocketChannel? _ch;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Timer? _ping;
  int _seq = 0;
  int _attempt = 0;
  bool _wanted = false;
  @override
  SocketStatus status = SocketStatus.offline;

  @override
  Stream<ServerMessage> get messages => _messages.stream;
  @override
  Stream<SocketStatus> get statusStream => _status.stream;

  void _setStatus(SocketStatus s) {
    status = s;
    _status.add(s);
  }

  /// Connect (no-op if already connected or connecting).
  @override
  Future<void> connect() async {
    _wanted = true;
    if (status != SocketStatus.offline) return;
    _setStatus(SocketStatus.connecting);
    try {
      await api.ensureLogin();
      final ch = WebSocketChannel.connect(api.socketUri());
      await ch.ready.timeout(const Duration(seconds: 8));
      _ch = ch;
      _attempt = 0;
      _setStatus(SocketStatus.online);
      _sub = ch.stream.listen(_onData, onDone: _onClosed, onError: (_) => _onClosed());
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 20), (_) => send('ping', {}));
    } catch (_) {
      _onClosed();
    }
  }

  void _onData(dynamic raw) {
    try {
      final m = jsonDecode(raw as String) as Map<String, dynamic>;
      _messages.add(ServerMessage(m['type'] as String, (m['payload'] as Map?)?.cast<String, dynamic>() ?? {}));
    } catch (_) {
      // ignore malformed frames
    }
  }

  void _onClosed() {
    final code = _ch?.closeCode;
    _sub?.cancel();
    _sub = null;
    _ch = null;
    _ping?.cancel();
    _setStatus(SocketStatus.offline);
    if (code == 4401) {
      // token refused: log in again on the next attempt
      api.settings.clearSession();
    }
    if (code == 4001) _wanted = false; // this player opened a newer connection elsewhere
    if (!_wanted) return;
    _attempt++;
    final wait = Duration(milliseconds: min(15000, 500 * pow(2, min(_attempt, 5)).toInt()));
    _retry?.cancel();
    _retry = Timer(wait, connect);
  }

  /// Send a client message. Dropped silently while offline (the server is authoritative,
  /// and the next `full_state` brings the client back in step).
  @override
  void send(String type, [Map<String, dynamic> payload = const {}]) {
    final ch = _ch;
    if (ch == null) return;
    _seq++;
    ch.sink.add(jsonEncode({'type': type, 'seq': _seq, 'payload': payload}));
  }

  @override
  Future<void> close() async {
    _wanted = false;
    _retry?.cancel();
    _ping?.cancel();
    await _ch?.sink.close();
    _ch = null;
    _setStatus(SocketStatus.offline);
  }
}
