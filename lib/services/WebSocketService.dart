import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:chatapp/models/Chat.dart';

enum WsStatus { disconnected, connecting, connected, error }

class WebSocketService extends ChangeNotifier {
  // 👇 O'zingizning serveringiz URL ini shu yerga yozing
  static const String _wsUrl = 'wss://echo.websocket.events';

  WebSocketChannel? _channel;
  WsStatus _status = WsStatus.disconnected;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  final _msgCtrl = StreamController<Message>.broadcast();

  WsStatus get status      => _status;
  Stream<Message> get msgStream => _msgCtrl.stream;
  bool get isConnected     => _status == WsStatus.connected;

  String? _userId;

  // ── Connect ──────────────────────────────────────────────
  Future<void> connect(String userId) async {
    if (_status == WsStatus.connected || _status == WsStatus.connecting) return;
    _userId = userId;
    _setStatus(WsStatus.connecting);

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      await _channel!.ready;           // throws if connection fails
      _setStatus(WsStatus.connected);

      _sub = _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone:  _onDone,
      );

      _send({'type': 'join', 'userId': userId});
      _startPing();
    } catch (e) {
      debugPrint('WS connect error: $e');
      _setStatus(WsStatus.error);
      _scheduleReconnect();
    }
  }

  // ── Join room ─────────────────────────────────────────────
  void joinChat(String chatId) {
    if (!isConnected) return;
    _send({'type': 'join_chat', 'chatId': chatId, 'userId': _userId});
  }

  // ── Send text ─────────────────────────────────────────────
  void sendMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String content,
    MessageType type = MessageType.text,
  }) {
    final msg = Message(
      id:         '${DateTime.now().millisecondsSinceEpoch}',
      senderId:   senderId,
      senderName: senderName,
      content:    content,
      type:       type,
      timestamp:  DateTime.now(),
    );

    _send({'type': 'message', 'chatId': chatId, 'message': msg.toJson()});

    // Echo locally so sender sees their own message immediately
    _msgCtrl.add(msg);
  }

  // ── Send image ────────────────────────────────────────────
  void sendImage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String imageUrl,
  }) => sendMessage(
    chatId:     chatId,
    senderId:   senderId,
    senderName: senderName,
    content:    imageUrl,
    type:       MessageType.image,
  );

  // ── Internal ──────────────────────────────────────────────
  void _onData(dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      if (json['type'] == 'message') {
        _msgCtrl.add(Message.fromJson(json['message'] as Map<String, dynamic>));
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
    _setStatus(WsStatus.disconnected);
    _scheduleReconnect();
  }

  void _send(Map<String, dynamic> data) {
    if (!isConnected) return;
    _channel?.sink.add(jsonEncode(data));
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _send({'type': 'ping'});
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), () {
      if (_userId != null) connect(_userId!);
    });
  }

  void _setStatus(WsStatus s) {
    _status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _msgCtrl.close();
    super.dispose();
  }
}