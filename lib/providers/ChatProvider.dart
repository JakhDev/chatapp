import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/services/WebSocketService.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:google_sign_in/google_sign_in.dart';

class ChatProvider extends ChangeNotifier {
  final WebSocketService _ws;
  StreamSubscription? _sub;

  User?            _me;
  final List<Chat> _chats = [];
  String _searchQuery = '';

  List<User> _allUsers = [];
  List<User> get allUsers => List.unmodifiable(_allUsers);

  User? get currentUser => _me;

  List<Chat> get chats {
    if (_searchQuery.isEmpty) return List.unmodifiable(_chats);
    return List.unmodifiable(
      _chats
          .where((c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList(),
    );
  }

  ChatProvider(this._ws) {
    _sub = _ws.msgStream.listen(_onIncoming);

    final sbUser = sb.Supabase.instance.client.auth.currentUser;
    if (sbUser != null) {
      final name = sbUser.userMetadata?['full_name'] as String? ??
          sbUser.userMetadata?['name']  as String? ??
          sbUser.email ??
          'User';
      _loginWithId(sbUser.id, name);
    }
  }

  // ── Bitta chatning xabarlarini qaytaradi ──────────────────────────────────
  List<Message> messages(String chatId) {
    final chat = _chats.firstWhere(
          (c) => c.id == chatId,
      orElse: () => Chat(id: '', name: '', type: ChatType.personal, memberIds: []),
    );
    return List.unmodifiable(chat.messages);
  }

  void login(String name) {
    final sbUser = sb.Supabase.instance.client.auth.currentUser;
    if (sbUser != null) _loginWithId(sbUser.id, name);
  }

  void _loginWithId(String id, String name) {
    _me = User(id: id, name: name, isOnline: true);
    _ws.connect(_me!.id);
    notifyListeners();
    _saveUserToDb(id, name);   // ← Foydalanuvchini DB ga saqlash
    loadOldMessages();
  }

  // ── Foydalanuvchini users jadvaliga saqlash (yangi bo'lsa qo'shadi) ───────
  Future<void> _saveUserToDb(String id, String name) async {
    try {
      final sbUser = sb.Supabase.instance.client.auth.currentUser;
      final avatarUrl = sbUser?.userMetadata?['avatar_url'] as String? ?? '';

      await sb.Supabase.instance.client.from('users').upsert({
        'id':        id,
        'name':      name,
        'avatarurl': avatarUrl,
        'isonline':  true,
      }, onConflict: 'id');

      if (kDebugMode) print('✅ Foydalanuvchi users jadvaliga saqlandi');
    } catch (e) {
      if (kDebugMode) print('🚨 _saveUserToDb xatolik: $e');
    }
  }

  // ── Barcha foydalanuvchilarni bazadan yuklash ─────────────────────────────
  Future<void> loadAllUsers() async {
    if (_me == null) return;
    try {
      final List<dynamic> data = await sb.Supabase.instance.client
          .from('users')
          .select('id, name, avatarurl, isonline');

      _allUsers = data.map((row) {
        return User(
          id:        row['id']        as String? ?? '',
          name:      row['name']      as String? ?? 'Foydalanuvchi',
          avatarUrl: row['avatarurl'] as String? ?? '',
          isOnline:  row['isonline']  as bool?   ?? false,
        );
      }).where((u) => u.id != _me!.id).toList();

      if (kDebugMode) print('🚀 Yuklangan userlar: ${_allUsers.length}');
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 loadAllUsers xatolik: $e');
    }
  }

  // ── Yangi shaxsiy chat ochish yoki mavjudini topish ───────────────────────
  Chat newPersonal(User other) {
    final ids    = [_me!.id, other.id]..sort();
    final chatId = '${ids[0]}_${ids[1]}';

    final existing = _chats.where((c) => c.id == chatId);
    if (existing.isNotEmpty) return existing.first;

    final chat = Chat(
      id:        chatId,
      name:      other.name,
      type:      ChatType.personal,
      memberIds: [_me!.id, other.id],
      messages:  [],
    );
    _chats.insert(0, chat);
    notifyListeners();
    return chat;
  }

  // ── Eski xabarlarni Supabase dan yuklash ─────────────────────────────────
  Future<void> loadOldMessages() async {
    if (_me == null) return;
    try {
      final List<dynamic> data = await sb.Supabase.instance.client
          .from('messages')
          .select()
          .order('id', ascending: true);   // ✅ created_at yo'q, id bo'yicha

      _chats.clear();

      for (final row in data) {
        final String chatId      = row['chatid']     as String? ?? '';
        final String senderId    = row['senderid']   as String? ?? '';
        final String senderName  = row['sendername'] as String? ?? 'Foydalanuvchi';
        final String content     = row['content']    as String? ?? '';

        if (chatId.isEmpty) continue;

        // ✅ created_at bo'lmasa DateTime.now() ishlatiladi
        final rawTs    = row['created_at'] as String?;
        final timestamp = (rawTs != null && rawTs.isNotEmpty)
            ? DateTime.tryParse(rawTs) ?? DateTime.now()
            : DateTime.now();

        final isImage = content.startsWith('http') &&
            (content.contains('.jpg') ||
                content.contains('.png') ||
                content.contains('chat_images'));

        final msg = Message(
          id:         row['id']?.toString() ?? 'msg_${timestamp.millisecondsSinceEpoch}',
          chatId:     chatId,
          senderId:   senderId,
          senderName: senderName,
          content:    content,
          type:       isImage ? MessageType.image : MessageType.text,
          timestamp:  timestamp,
        );

        int chatIdx = _chats.indexWhere((c) => c.id == chatId);
        if (chatIdx == -1) {
          final chatName = senderId == _me!.id ? 'Yozishma' : senderName;
          final newChat  = Chat(
            id:        chatId,
            name:      chatName,
            type:      ChatType.personal,
            memberIds: [_me!.id, senderId],
            messages:  [],
          );
          _chats.add(newChat);
          chatIdx = _chats.length - 1;
        } else {
          final chat = _chats[chatIdx];
          if (chat.name == 'Yozishma' && senderId != _me!.id) {
            _chats[chatIdx] = Chat(
              id:              chat.id,
              name:            senderName,
              type:            chat.type,
              memberIds:       chat.memberIds,
              messages:        chat.messages,
              lastMessage:     chat.lastMessage,
              lastMessageTime: chat.lastMessageTime,
              unreadCount:     chat.unreadCount,
            );
          }
        }

        final currentChat = _chats[chatIdx];
        if (!currentChat.messages.any((m) => m.id == msg.id)) {
          currentChat.messages.add(msg);
        }
        currentChat.lastMessage     = msg.type == MessageType.image ? '📷 Rasm' : msg.content;
        currentChat.lastMessageTime = msg.timestamp;
      }

      _chats.sort((a, b) =>
          (b.lastMessageTime ?? DateTime(0)).compareTo(a.lastMessageTime ?? DateTime(0)));
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 loadOldMessages xatolik: $e');
    }
  }

  // ── Chat ochilganda o'qilmagan xabarlarni nolga tushirish ─────────────────
  void openChat(String chatId) {
    _ws.joinChat(chatId);
    final i = _chats.indexWhere((c) => c.id == chatId);
    if (i != -1) {
      _chats[i].unreadCount = 0;
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  // ── Matn xabar yuborish ───────────────────────────────────────────────────
  Future<void> sendText(String chatId, String text, BuildContext context) async {
    if (_me == null || text.trim().isEmpty) return;

    final cleanText = text.trim();
    final timeNow   = DateTime.now();

    final localMsg = Message(
      id:         'local_${timeNow.millisecondsSinceEpoch}',
      chatId:     chatId,
      senderId:   _me!.id,
      senderName: _me!.name,
      content:    cleanText,
      type:       MessageType.text,
      timestamp:  timeNow,
    );

    int i = _chats.indexWhere((c) => c.id == chatId);
    if (i == -1) {
      final newChat = Chat(
        id:        chatId,
        name:      'Yozishma',
        type:      ChatType.personal,
        memberIds: [_me!.id],
        messages:  [],
      );
      _chats.insert(0, newChat);
      i = 0;
    }
    _addMsgAndFormat(_chats[i], localMsg);

    _ws.sendMessage(
      chatId:     chatId,
      senderId:   _me!.id,
      senderName: _me!.name,
      content:    cleanText,
    );

    try {
      await sb.Supabase.instance.client.from('messages').insert({
        'chatid':     chatId,
        'senderid':   _me!.id,
        'sendername': _me!.name,
        'content':    cleanText,
      });
    } catch (e) {
      if (kDebugMode) print('🚨 sendText xatolik: $e');
    }
  }

  // ── Rasm yuborish ─────────────────────────────────────────────────────────
  Future<void> sendImage(String chatId, String filePath, BuildContext context) async {
    if (_me == null || filePath.isEmpty) return;

    final file     = File(filePath);
    final timeNow  = DateTime.now();
    final fileName = '${timeNow.millisecondsSinceEpoch}.jpg';

    final localMsg = Message(
      id:         'local_img_${timeNow.millisecondsSinceEpoch}',
      chatId:     chatId,
      senderId:   _me!.id,
      senderName: _me!.name,
      content:    filePath,
      type:       MessageType.image,
      timestamp:  timeNow,
    );

    int i = _chats.indexWhere((c) => c.id == chatId);
    if (i == -1) {
      final newChat = Chat(
        id:        chatId,
        name:      'Yozishma',
        type:      ChatType.personal,
        memberIds: [_me!.id],
        messages:  [],
      );
      _chats.insert(0, newChat);
      i = 0;
    }
    _addMsgAndFormat(_chats[i], localMsg);

    try {
      await sb.Supabase.instance.client.storage
          .from('chat_images')
          .upload(fileName, file);

      final publicUrl = sb.Supabase.instance.client.storage
          .from('chat_images')
          .getPublicUrl(fileName);

      _ws.sendMessage(
        chatId:     chatId,
        senderId:   _me!.id,
        senderName: _me!.name,
        content:    publicUrl,
      );

      await sb.Supabase.instance.client.from('messages').insert({
        'chatid':     chatId,
        'senderid':   _me!.id,
        'sendername': _me!.name,
        'content':    publicUrl,
      });
    } catch (e) {
      if (kDebugMode) print('🚨 sendImage xatolik: $e');
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    try {
      // Bazada isonline = false qilamiz
      if (_me != null) {
        await sb.Supabase.instance.client
            .from('users')
            .update({'isonline': false})
            .eq('id', _me!.id);
      }

      await sb.Supabase.instance.client.auth.signOut();
      try {
        final g = GoogleSignIn();
        await g.signOut();
        await g.disconnect();
      } catch (_) {}

      await _sub?.cancel();
      _sub = null;
      try { (_ws as dynamic).disconnect(); } catch (_) {}

      _me = null;
      _chats.clear();
      _allUsers.clear();
      _searchQuery = '';
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 logout xatolik: $e');
    }
  }

  // ── WebSocket orqali kelgan xabarni qabul qilish ──────────────────────────
  void _onIncoming(Message msg) {
    final targetChatId = msg.chatId;
    if (targetChatId.isEmpty) return;

    final isMine    = msg.senderId == _me?.id;
    final chatIndex = _chats.indexWhere((c) => c.id == targetChatId);

    if (chatIndex != -1) {
      final currentChat = _chats[chatIndex];
      final isDuplicate = currentChat.messages.any((m) =>
      m.content  == msg.content &&
          m.senderId == msg.senderId &&
          (m.id == msg.id || m.id.startsWith('local_')));

      if (!isDuplicate) {
        _addMsgAndFormat(currentChat, msg);
      }
    } else if (!isMine) {
      final newChat = Chat(
        id:        targetChatId,
        name:      msg.senderName.isNotEmpty ? msg.senderName : 'Foydalanuvchi',
        type:      ChatType.personal,
        memberIds: [_me?.id ?? '', msg.senderId],
        messages:  [],
      );
      _chats.insert(0, newChat);
      _addMsgAndFormat(newChat, msg);
    }
  }

  // ── Yordamchi: xabar qo'shish va chatni yangilash ─────────────────────────
  void _addMsgAndFormat(Chat chat, Message msg) {
    if (!chat.messages.any((m) => m.id == msg.id)) {
      chat.messages.add(msg);
    }
    chat.lastMessage     = msg.type == MessageType.image ? '📷 Rasm' : msg.content;
    chat.lastMessageTime = msg.timestamp;
    _chats.sort((a, b) =>
        (b.lastMessageTime ?? DateTime(0)).compareTo(a.lastMessageTime ?? DateTime(0)));
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}