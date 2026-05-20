import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/services/WebSocketService.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

class ChatProvider extends ChangeNotifier {
  final WebSocketService _ws;
  StreamSubscription? _sub;

  User?            _me;
  final List<Chat> _chats = [];
  String _searchQuery = '';

  User?      get currentUser => _me;

  // Qidiruv uchun chatlarni filtrlovchi getter
  List<Chat> get chats {
    if (_searchQuery.isEmpty) {
      return List.unmodifiable(_chats);
    }
    return List.unmodifiable(
      _chats.where((chat) => chat.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList(),
    );
  }

  ChatProvider(this._ws) {
    _sub = _ws.msgStream.listen(_onIncoming);

    final sbUser = sb.Supabase.instance.client.auth.currentUser;
    if (sbUser != null) {
      final name = sbUser.userMetadata?['full_name'] as String? ??
          sbUser.userMetadata?['name'] as String? ??
          sbUser.email ?? 'User';
      _loginWithId(sbUser.id, name);
    }
  }

  List<Message> messages(String chatId) {
    final chat = _chats.firstWhere(
            (c) => c.id == chatId,
        orElse: () => Chat(id: '', name: '', type: ChatType.personal, memberIds: [])
    );
    return List.unmodifiable(chat.messages);
  }

  void login(String name) {
    final sbUser = sb.Supabase.instance.client.auth.currentUser;
    if (sbUser != null) {
      _loginWithId(sbUser.id, name);
    }
  }

  void _loginWithId(String id, String name) {
    _me = User(
      id:       id,
      name:     name,
      isOnline: true,
    );
    _ws.connect(_me!.id);
    notifyListeners();
  }

  void openChat(String chatId) {
    _ws.joinChat(chatId);
    final i = _chats.indexWhere((c) => c.id == chatId);
    if (i != -1) {
      _chats[i].unreadCount = 0;
      notifyListeners();
    }
  }

  // Qidiruv matnini o'zgartirish
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void addChatIfNotExist(Chat newChat) {
    final exists = _chats.any((c) => c.id == newChat.id);
    if (!exists) {
      _chats.insert(0, newChat);
      notifyListeners();
    }
  }

  // 🚨 SUPABASE + WEBSOCKET BILAN INTEGRATSIYA QILINGAN METOD
// Ushbu metodni ChatProvider klassingiz ichiga joylang:
  void sendText(String chatId, String text, BuildContext context) async { // <- context qo'shildi!
    if (_me == null || text.trim().isEmpty) return;

    final cleanText = text.trim();
    final timeNow = DateTime.now();

    // 1. Darhol ekranga mahalliy xabarni chiqarish (UI qotib qolmasligi uchun)
    final localMsg = Message(
      id:         'local_${timeNow.millisecondsSinceEpoch}',
      senderId:   _me!.id,
      senderName: _me!.name,
      content:    cleanText,
      type:       MessageType.text,
      timestamp:  timeNow,
    );

    final i = _chats.indexWhere((c) => c.id == chatId);
    if (i != -1) {
      _addMsgAndFormat(_chats[i], localMsg);
    }

    // 2. WebSocket orqali real-time sherigimizga yuboramiz
    _ws.sendMessage(
      chatId:     chatId,
      senderId:   _me!.id,
      senderName: _me!.name,
      content:    cleanText,
    );

    // 3. Supabase 'messages' jadvaliga saqlash mantiqi va aniq diagnostikasi
    try {
      // Diqqat: jadvalingizdagi ustun nomlari kichik harflarda bo'lishi shart!
      await sb.Supabase.instance.client.from('messages').insert({
        'chatid': chatId,
        'senderid': _me!.id,
        'sendername': _me!.name,
        'content': cleanText,
      });

      if (kDebugMode) print("🎯 AJOYIB! Xabar Supabase 'messages' jadvaliga muvaffaqiyatli saqlandi.");

    } on sb.PostgrestException catch (postgrestError) {
      // Agar Supabase bazasida ustunlar xato bo'lsa yoki RLS baribir bloklasa shu yerga tushadi:
      if (kDebugMode) print("🚨 Supabase Postgrest xatosi: ${postgrestError.message}");

      // Ekranga xatoni chiqarish
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text("Baza xatosi: ${postgrestError.message}"),
        ),
      );
    } catch (globalError) {
      // Boshqa har qanday kutilmagan xatoliklar uchun:
      if (kDebugMode) print("🚨 Kutilmagan global xatolik: $globalError");

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange,
          content: Text("Tizim xatosi: $globalError"),
        ),
      );
    }
  }
  void sendImage(String chatId, String path) {
    if (_me == null) return;
    _ws.sendMessage(
      chatId:     chatId,
      senderId:   _me!.id,
      senderName: _me!.name,
      content:    path,
    );
  }

  Chat newPersonal(User other) {
    final id  = other.id;
    final hit = _chats.where((c) => c.id == id);
    if (hit.isNotEmpty) return hit.first;

    final chat = Chat(
      id:        id,
      name:      other.name,
      type:      ChatType.personal,
      memberIds: [_me!.id, other.id],
      messages:  [],
    );
    _chats.insert(0, chat);
    notifyListeners();
    return chat;
  }

  Chat newGroup(String name, List<User> members) {
    final chat = Chat(
      id:        'grp_${DateTime.now().millisecondsSinceEpoch}',
      name:      name,
      type:      ChatType.group,
      memberIds: [_me!.id, ...members.map((m) => m.id)],
      messages:  [],
    );
    _chats.insert(0, chat);
    notifyListeners();
    return chat;
  }

  void _onIncoming(Message msg) {
    final isMine = msg.senderId == _me?.id;
    String targetChatId = isMine ? (_chats.isNotEmpty ? _chats.first.id : '') : msg.senderId;

    if (targetChatId.isEmpty) return;

    final chatIndex = _chats.indexWhere((c) => c.id == targetChatId);

    if (chatIndex != -1) {
      final currentChat = _chats[chatIndex];
      final isDuplicate = currentChat.messages.any((m) =>
      m.content == msg.content &&
          m.senderId == msg.senderId &&
          (m.id == msg.id || m.id.startsWith('local_'))
      );

      if (!isDuplicate || !isMine) {
        _addMsgAndFormat(currentChat, msg);
      }
    } else {
      final newChat = Chat(
        id: targetChatId,
        name: msg.senderName.isNotEmpty ? msg.senderName : 'Foydalanuvchi',
        type: ChatType.personal,
        memberIds: [_me?.id ?? '', msg.senderId],
        messages: [],
      );
      _chats.insert(0, newChat);
      _addMsgAndFormat(newChat, msg);
    }
  }

  void _addMsgAndFormat(Chat chat, Message msg) {
    final hasMessage = chat.messages.any((m) => m.id == msg.id);
    if (!hasMessage) {
      chat.messages.add(msg);
    }

    chat.lastMessage = msg.type == MessageType.image ? '📷 Rasm' : msg.content;
    chat.lastMessageTime = msg.timestamp;

    _chats.sort((a, b) => (b.lastMessageTime ?? DateTime(0)).compareTo(a.lastMessageTime ?? DateTime(0)));

    notifyListeners();
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }
}