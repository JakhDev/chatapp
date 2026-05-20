import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/services/WebSocketService.dart';

class ChatProvider extends ChangeNotifier {
  final WebSocketService _ws;
  StreamSubscription? _sub;

  User?             _me;
  final List<Chat>  _chats    = [];
  final Map<String, List<Message>> _msgs = {};

  User?        get currentUser => _me;
  List<Chat>   get chats       => List.unmodifiable(_chats);

  ChatProvider(this._ws) {
    _sub = _ws.msgStream.listen(_onIncoming);
    _loadDemo();
  }

  List<Message> messages(String chatId) =>
      List.unmodifiable(_msgs[chatId] ?? []);

  void login(String name) {
    _me = User(
      id:       '${DateTime.now().millisecondsSinceEpoch}',
      name:     name,
      isOnline: true,
    );
    _ws.connect(_me!.id);
    notifyListeners();
  }

  void openChat(String chatId) {
    _ws.joinChat(chatId);
    final i = _chats.indexWhere((c) => c.id == chatId);
    if (i != -1) { _chats[i].unreadCount = 0; notifyListeners(); }
  }

  void sendText(String chatId, String text) {
    if (_me == null || text.trim().isEmpty) return;
    _ws.sendMessage(
      chatId:     chatId,
      senderId:   _me!.id,
      senderName: _me!.name,
      content:    text.trim(),
    );
  }

  void sendImage(String chatId, String path) {
    if (_me == null) return;
    _ws.sendImage(
      chatId:     chatId,
      senderId:   _me!.id,
      senderName: _me!.name,
      imageUrl:   path,
    );
  }

  Chat newPersonal(User other) {
    final id  = '${_me!.id}_${other.id}';
    final hit = _chats.where((c) => c.id == id);
    if (hit.isNotEmpty) return hit.first;
    final chat = Chat(
      id:        id,
      name:      other.name,
      type:      ChatType.personal,
      memberIds: [_me!.id, other.id],
    );
    _chats.insert(0, chat);
    _msgs[id] = [];
    notifyListeners();
    return chat;
  }

  Chat newGroup(String name, List<User> members) {
    final chat = Chat(
      id:        'grp_${DateTime.now().millisecondsSinceEpoch}',
      name:      name,
      type:      ChatType.group,
      memberIds: [_me!.id, ...members.map((m) => m.id)],
    );
    _chats.insert(0, chat);
    _msgs[chat.id] = [];
    notifyListeners();
    return chat;
  }

  void _onIncoming(Message msg) {
    for (final chat in _chats) {
      if (_msgs.containsKey(chat.id)) {
        _addMsg(chat.id, msg);
        break;
      }
    }
  }

  void _addMsg(String chatId, Message msg) {
    _msgs[chatId]!.add(msg);
    final i = _chats.indexWhere((c) => c.id == chatId);
    if (i != -1) {
      _chats[i].lastMessage     = msg.type == MessageType.image ? '📷 Rasm' : msg.content;
      _chats[i].lastMessageTime = msg.timestamp;
      _chats.sort((a, b) =>
          (b.lastMessageTime ?? DateTime(0))
              .compareTo(a.lastMessageTime ?? DateTime(0)));
    }
    notifyListeners();
  }

  void _loadDemo() {
    final chat1 = Chat(
      id: 'demo_jasur', name: 'Jasur',
      type: ChatType.personal, memberIds: ['me', 'u1'],
      lastMessage: 'Qalaysan? 👋',
      lastMessageTime: DateTime.now().subtract(const Duration(minutes: 5)),
      unreadCount: 2,
    );
    final chat2 = Chat(
      id: 'demo_malika', name: 'Malika',
      type: ChatType.personal, memberIds: ['me', 'u2'],
      lastMessage: 'Loyiha haqida gaplashamizmi?',
      lastMessageTime: DateTime.now().subtract(const Duration(hours: 1)),
    );
    final group = Chat(
      id: 'demo_group', name: 'Flutter Devs 🚀',
      type: ChatType.group, memberIds: ['me', 'u1', 'u2', 'u3'],
      lastMessage: 'Bobur: yangi update chiqdi!',
      lastMessageTime: DateTime.now().subtract(const Duration(minutes: 30)),
      unreadCount: 5,
    );
    _chats.addAll([chat1, chat2, group]);
    _msgs['demo_jasur'] = [
      Message(id:'1', senderId:'u1', senderName:'Jasur',
          content:'Salom! 👋', timestamp: DateTime.now().subtract(const Duration(minutes:10))),
      Message(id:'2', senderId:'me', senderName:'Men',
          content:'Yaxshi, rahmat!', timestamp: DateTime.now().subtract(const Duration(minutes:8))),
      Message(id:'3', senderId:'u1', senderName:'Jasur',
          content:'Qalaysan? 👋', timestamp: DateTime.now().subtract(const Duration(minutes:5))),
    ];
    _msgs['demo_malika'] = [
      Message(id:'m1', senderId:'u2', senderName:'Malika',
          content:'Loyiha haqida gaplashamizmi?',
          timestamp: DateTime.now().subtract(const Duration(hours:1))),
    ];
    _msgs['demo_group'] = [
      Message(id:'g1', senderId:'u1', senderName:'Jasur',
          content:'Hammaga salom! 🎉', timestamp: DateTime.now().subtract(const Duration(hours:2))),
      Message(id:'g2', senderId:'u2', senderName:'Malika',
          content:'Flutter 3.x juda zo\'r!', timestamp: DateTime.now().subtract(const Duration(hours:1))),
      Message(id:'g3', senderId:'u3', senderName:'Bobur',
          content:'Yangi update chiqdi!', timestamp: DateTime.now().subtract(const Duration(minutes:30))),
    ];
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }
}