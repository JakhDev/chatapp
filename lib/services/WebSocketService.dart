import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:chatapp/models/Chat.dart';

// ── Conditional import: Web da stub, mobile da haqiqiy paket ─────────────────
import 'package:web_socket_channel/web_socket_channel.dart'
if (dart.library.html) 'package:chatapp/services/ws_stub.dart'
if (dart.library.io)   'package:web_socket_channel/io.dart';

enum WsStatus { disconnected, connecting, connected, error }

class WebSocketService extends ChangeNotifier {
  WebSocketChannel?   _channel;
  WsStatus            _status = WsStatus.disconnected;
  StreamSubscription? _sub;
  Timer?              _reconnectTimer;
  Timer?              _pingTimer;

  final _msgCtrl = StreamController<Message>.broadcast();

  WsStatus        get status      => _status;
  Stream<Message> get msgStream   => _msgCtrl.stream;
  bool            get isConnected => _status == WsStatus.connected;

  String? _userId;

  // ── Connect ─────────────────────────────────────────────────────────────────
  Future<void> connect(String userId) async {
    // Web platformda WebSocket ishlatmaymiz — Supabase Realtime yetarli
    if (kIsWeb) {
      _userId = userId;
      _setStatus(WsStatus.connected);
      return;
    }

    if (_status == WsStatus.connected ||
        _status == WsStatus.connecting) return;

    _userId = userId;
    _setStatus(WsStatus.connecting);

    try {
      _channel = WebSocketChannel.connect(
          Uri.parse('ws://localhost:8080'));
      await _channel!.ready;
      _setStatus(WsStatus.connected);

      _sub = _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone:  _onDone,
        cancelOnError: false,
      );

      _send({'type': 'join', 'userId': userId});
      _startPing();
    } catch (e) {
      debugPrint('WS connect error: $e');
      _setStatus(WsStatus.error);
      _scheduleReconnect();
    }
  }

  // ── Join chat ────────────────────────────────────────────────────────────────
  void joinChat(String chatId) {
    if (kIsWeb || !isConnected) return;
    _send({'type': 'join_chat', 'chatId': chatId, 'userId': _userId});
  }

  // ── Send message ─────────────────────────────────────────────────────────────
  void sendMessage({
    required String     chatId,
    required String     senderId,
    required String     senderName,
    required String     content,
    MessageType         type = MessageType.text,
  }) {
    if (kIsWeb || !isConnected) return;

    _send({
      'type':   'message',
      'chatId': chatId,
      'message': {
        'id':         '${DateTime.now().millisecondsSinceEpoch}',
        'chatid':     chatId,
        'senderid':   senderId,
        'sendername': senderName,
        'content':    content,
        'type':       type == MessageType.image ? 'image'
            : type == MessageType.audio ? 'audio'
            : 'text',
        'timestamp':  DateTime.now().toIso8601String(),
        'isread':     false,
      },
    });
  }

  // ── Internal handlers ────────────────────────────────────────────────────────
  void _onData(dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      if (json['type'] == 'message') {
        final msgJson = Map<String, dynamic>.from(
            json['message'] as Map<String, dynamic>);
        // chatId ni to'ldirish
        if ((msgJson['chatId'] as String? ?? '').isEmpty) {
          msgJson['chatId'] = json['chatId'] as String? ?? '';
        }
        final msg = Message.fromJson(msgJson);
        // O'z xabarimizni qayta qo'shmaymiz
        if (msg.senderId != _userId) _msgCtrl.add(msg);
      }
    } catch (e) {
      debugPrint('WS parse error: $e');
    }
  }

  void _onError(dynamic e) {
    debugPrint('WS error: $e');
    _setStatus(WsStatus.error);
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('WS connection closed');
    _setStatus(WsStatus.disconnected);
    _scheduleReconnect();
  }

  void _send(Map<String, dynamic> data) {
    if (kIsWeb || !isConnected || _channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (e) {
      debugPrint('WS send error: $e');
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      const Duration(seconds: 25),
          (_) => _send({'type': 'ping'}),
    );
  }

  void _scheduleReconnect() {
    if (kIsWeb) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      const Duration(seconds: 4),
          () { if (_userId != null) connect(_userId!); },
    );
  }

  void _setStatus(WsStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  // ── Disconnect ───────────────────────────────────────────────────────────────
  void disconnect() {
    _sub?.cancel();
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setStatus(WsStatus.disconnected);
  }

  @override
  void dispose() {
    disconnect();
    _msgCtrl.close();
    super.dispose();
  }
}