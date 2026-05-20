import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:chatapp/models/Chat.dart';

enum WsStatus { disconnected, connecting, connected, error }

class WebSocketService extends ChangeNotifier {
  // 👇 O'zingizning serveringiz URL ini shu yerga yozing
  final String wsUrl = "ws://localhost:8080";
  WebSocketChannel? _channel;
  WsStatus _status = WsStatus.disconnected;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  final _msgCtrl = StreamController<Message>.broadcast();

  WsStatus        get status    => _status;
  Stream<Message> get msgStream => _msgCtrl.stream;
  bool            get isConnected => _status == WsStatus.connected;

  String? _userId;

  // ── Connect ───────────────────────────────────────────────────────────────
  Future<void> connect(String userId) async {
    if (_status == WsStatus.connected || _status == WsStatus.connecting) return;
    _userId = userId;
    _setStatus(WsStatus.connecting);

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      await _channel!.ready;
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

  // ── Join room ─────────────────────────────────────────────────────────────
  void joinChat(String chatId) {
    if (!isConnected) return;
    _send({'type': 'join_chat', 'chatId': chatId, 'userId': _userId});
  }

  // ── Xabar yuborish ────────────────────────────────────────────────────────
  void sendMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String content,
    MessageType type = MessageType.text,
  }) {
    final msg = Message(
      id:         '${DateTime.now().millisecondsSinceEpoch}',
      chatId:     chatId,       // ← YANGI: chatId qo'shildi
      senderId:   senderId,
      senderName: senderName,
      content:    content,
      type:       type,
      timestamp:  DateTime.now(),
    );

    // Serverga yuboramiz — chatId ham message ichida bo'ladi (toJson orqali)
    _send({
      'type':    'message',
      'chatId':  chatId,
      'message': msg.toJson(),
    });

    // ❌ Local echo o'chirildi — ChatProvider allaqachon localMsg qo'shadi
    // _msgCtrl.add(msg);  // Bu dublikatlarga olib kelardi!
  }

  // ── Rasm yuborish ─────────────────────────────────────────────────────────
  void sendImage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String imageUrl,
  }) =>
      sendMessage(
        chatId:     chatId,
        senderId:   senderId,
        senderName: senderName,
        content:    imageUrl,
        type:       MessageType.image,
      );

  // ── Serverdan kelgan xabarni qayta ishlash ────────────────────────────────
  void _onData(dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;

      if (json['type'] == 'message') {
        final msgJson = json['message'] as Map<String, dynamic>;

        // Agar message ichida chatId yo'q bo'lsa, tashqi chatId ni olamiz
        if (!msgJson.containsKey('chatId') || (msgJson['chatId'] as String? ?? '').isEmpty) {
          msgJson['chatId'] = json['chatId'] as String? ?? '';
        }

        final msg = Message.fromJson(msgJson);

        // Faqat boshqa foydalanuvchilardan kelgan xabarlarni stream ga qo'shamiz
        // (o'zimizni xabarlarimiz ChatProvider da localMsg sifatida allaqachon bor)
        if (msg.senderId != _userId) {
          _msgCtrl.add(msg);
        }
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

  void disconnect() {
    _sub?.cancel();
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _setStatus(WsStatus.disconnected);
  }

  @override
  void dispose() {
    disconnect();
    _msgCtrl.close();
    super.dispose();
  }
}