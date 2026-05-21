import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/services/WebSocketService.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class ChatProvider extends ChangeNotifier {
  final WebSocketService _ws;
  StreamSubscription? _wsSub;

  sb.RealtimeChannel? _realtimeChannel;

  User?            _me;
  final List<Chat> _chats = [];
  String           _searchQuery = '';
  List<User>       _allUsers = [];
  String?          _activeChatId;

  User?      get currentUser => _me;
  List<User> get allUsers    => List.unmodifiable(_allUsers);

  List<Chat> get chats {
    if (_searchQuery.isEmpty) return List.unmodifiable(_chats);
    return List.unmodifiable(
      _chats.where((c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList(),
    );
  }

  ChatProvider(this._ws) {
    _wsSub = _ws.msgStream.listen(_onIncoming);

    final sbUser = sb.Supabase.instance.client.auth.currentUser;
    if (sbUser != null) {
      final name = sbUser.userMetadata?['full_name'] as String? ??
          sbUser.userMetadata?['name']  as String? ??
          sbUser.email ?? 'User';
      _loginWithId(sbUser.id, name);
    }
  }

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
    _subscribeRealtime();
    notifyListeners();
    loadAllUsers();
    _saveUserToDb(id, name);
    loadOldMessages();
  }

  // ── Supabase Realtime ─────────────────────────────────────────────────────
  void _subscribeRealtime() {
    _realtimeChannel?.unsubscribe();

    _realtimeChannel = sb.Supabase.instance.client
        .channel('public:messages')
        .onPostgresChanges(
      event: sb.PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        if (kDebugMode) print('🔴 Realtime xabar: ${payload.newRecord}');
        _onRealtimeMessage(payload.newRecord);
      },
    );

    _realtimeChannel?.subscribe();
  }

  // ── Realtime xabarni qabul qilish ────────────────────────────────────────
  void _onRealtimeMessage(Map<String, dynamic> row) {
    if (_me == null) return;

    final String chatId     = row['chatid']     as String? ?? '';
    final String msgId      = row['id']?.toString() ?? '';
    final String senderId   = row['senderid']   as String? ?? '';
    final String senderName = row['sendername'] as String? ?? '';
    final String content    = row['content']    as String? ?? '';
    // ✅ FIX: isRead to'g'ri o'qiladi
    final bool   isRead     = row['isread'] == true;

    if (chatId.isEmpty || content.isEmpty) return;

    final rawTs = row['created_at'] as String? ?? row['timestamp'] as String?;
    final timestamp = rawTs != null ? DateTime.tryParse(rawTs) ?? DateTime.now() : DateTime.now();

    final isImage = _isImageContent(content);

    final msg = Message(
      id:         msgId,
      chatId:     chatId,
      senderId:   senderId,
      senderName: senderName,
      content:    content,
      type:       isImage ? MessageType.image : MessageType.text,
      timestamp:  timestamp,
      isRead:     isRead, // ✅ FIX: Message modeliga isRead uzatildi
    );

    final isMine  = senderId == _me!.id;
    final chatIdx = _chats.indexWhere((c) => c.id == chatId);

    if (chatIdx != -1) {
      final chat = _chats[chatIdx];

      // Mahalliy vaqtinchalik xabarni almashtirish
      final localIdx = chat.messages.indexWhere((m) =>
      m.id.startsWith('local_') &&
          m.content == content &&
          m.senderId == senderId);

      if (localIdx != -1) {
        chat.messages[localIdx] = msg;
      } else if (!chat.messages.any((m) => m.id == msgId)) {
        chat.messages.add(msg);

        // ✅ FIX: Faqat o'qilmagan va begona xabarlar uchun soni oshiriladi
        if (!isMine && _activeChatId != chatId && !isRead) {
          chat.unreadCount++;
        }
      }

      chat.lastMessage     = isImage ? '📷 Rasm' : content;
      chat.lastMessageTime = timestamp;

      // Agar chat hozir ochiq bo'lsa — darhol o'qildi
      if (_activeChatId == chatId && !isMine) {
        chat.unreadCount = 0;
        markAsRead(chatId);
      }
    } else {
      // Yangi chat (ilk xabar)
      final idList  = chatId.split('_');
      final otherId = idList.first == _me!.id ? idList.last : idList.first;

      final otherUser = _allUsers.firstWhere(
            (u) => u.id == otherId,
        orElse: () => User(id: otherId, name: senderName.isNotEmpty ? senderName : 'Foydalanuvchi'),
      );

      final newChat = Chat(
        id:              chatId,
        name:            otherUser.name,
        type:            ChatType.personal,
        memberIds:       [_me!.id, otherId],
        messages:        [msg],
        lastMessage:     isImage ? '📷 Rasm' : content,
        lastMessageTime: timestamp,
        // ✅ FIX: Ochiq chat bo'lmasa va o'qilmagan bo'lsa — 1
        unreadCount:     (!isMine && _activeChatId != chatId && !isRead) ? 1 : 0,
      );
      _chats.insert(0, newChat);
    }

    _sortChats();
    notifyListeners();
  }

  // ── O'qildi deb belgilash ─────────────────────────────────────────────────
  Future<void> markAsRead(String chatId) async {
    if (_me == null) return;
    try {
      await sb.Supabase.instance.client
          .from('messages')
          .update({'isread': true})
          .eq('chatid', chatId)
          .neq('senderid', _me!.id)
          .eq('isread', false); // ✅ FIX: Faqat o'qilmaganlarni yangilaydi

      final chatIdx = _chats.indexWhere((c) => c.id == chatId);
      if (chatIdx != -1) {
        final chat = _chats[chatIdx];
        // ✅ FIX: Lokal xabarlarning isRead holatini ham yangilash
        for (var i = 0; i < chat.messages.length; i++) {
          final m = chat.messages[i];
          if (m.senderId != _me!.id && !m.isRead) {
            chat.messages[i] = m.copyWith(isRead: true);
          }
        }
        chat.unreadCount = 0;
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) print('🚨 markAsRead xatolik: $e');
    }
  }

  // ── Chat ochilganda ───────────────────────────────────────────────────────
  void openChat(String chatId) {
    _activeChatId = chatId;
    _ws.joinChat(chatId);

    // UI darhol yangilansin
    final i = _chats.indexWhere((c) => c.id == chatId);
    if (i != -1) {
      final chat = _chats[i];
      // ✅ FIX: Lokal xabarlarni ham o'qildi qilamiz
      for (var j = 0; j < chat.messages.length; j++) {
        final m = chat.messages[j];
        if (m.senderId != _me?.id && !m.isRead) {
          chat.messages[j] = m.copyWith(isRead: true);
        }
      }
      chat.unreadCount = 0;
      notifyListeners();
    }

    // DB da o'qildi qilish (orqa fonda)
    markAsRead(chatId);
  }

  void closeChat() {
    _activeChatId = null;
  }

  // ── Eski xabarlarni yuklash (ilk ishga tushish) ───────────────────────────
  Future<void> loadOldMessages() async {
    if (_me == null) return;
    try {
      final List<dynamic> usersData = await sb.Supabase.instance.client
          .from('users')
          .select('id, name');

      final Map<String, String> userNames = {
        for (var u in usersData) u['id'] as String: u['name'] as String? ?? 'Foydalanuvchi',
      };

      final List<dynamic> data = await sb.Supabase.instance.client
          .from('messages')
          .select()
          .order('created_at', ascending: true);

      _chats.clear();

      // ✅ FIX: Bir passda xabar quriladi VA unreadCount sanaladi
      for (final row in data) {
        final String chatId     = row['chatid']     as String? ?? '';
        final String senderId   = row['senderid']   as String? ?? '';
        final String senderName = row['sendername'] as String? ?? '';
        final String content    = row['content']    as String? ?? '';
        if (chatId.isEmpty) continue;

        final rawTs     = row['created_at'] as String? ?? row['timestamp'] as String?;
        final timestamp = rawTs != null ? DateTime.tryParse(rawTs) ?? DateTime.now() : DateTime.now();

        // ✅ FIX: isRead TO'G'RIDAN-TO'G'RI row dan o'qiladi
        final bool isRead  = row['isread'] == true;
        final bool isMine  = senderId == _me!.id;
        final bool isImage = _isImageContent(content);

        final msg = Message(
          id:         row['id']?.toString() ?? '',
          chatId:     chatId,
          senderId:   senderId,
          senderName: senderName,
          content:    content,
          type:       isImage ? MessageType.image : MessageType.text,
          timestamp:  timestamp,
          isRead:     isRead, // ✅ FIX: to'g'ridan-to'g'ri saqlanadi
        );

        // Chat ID normalizatsiyasi
        final idList = chatId.split('_');
        String normalizedChatId = chatId;
        String otherId = _me!.id;

        if (idList.length >= 2) {
          idList.sort();
          normalizedChatId = idList.join('_');
          otherId = idList.first == _me!.id ? idList.last : idList.first;
        }

        // O'z-o'zi bilan chatni o'tkazib yuborish
        if (otherId == _me!.id) continue;

        int chatIdx = _chats.indexWhere((c) => c.id == normalizedChatId);

        if (chatIdx == -1) {
          final chatName = userNames[otherId] ??
              (senderId == _me!.id ? 'Foydalanuvchi' : senderName);

          _chats.add(Chat(
            id:          normalizedChatId,
            name:        chatName.isNotEmpty ? chatName : 'Foydalanuvchi',
            type:        ChatType.personal,
            memberIds:   [_me!.id, otherId],
            messages:    [],
            unreadCount: 0,
          ));
          chatIdx = _chats.length - 1;
        }

        final chat = _chats[chatIdx];
        if (!chat.messages.any((m) => m.id == msg.id)) {
          chat.messages.add(msg);

          // ✅ FIX: Ikkinchi pass kerak emas — shu yerda hisoblaymiz
          if (!isMine && !isRead) {
            chat.unreadCount++;
          }
        }

        chat.lastMessage     = isImage ? '📷 Rasm' : content;
        chat.lastMessageTime = timestamp;
      }

      for (var chat in _chats) {
        chat.messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }

      _sortChats();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 loadOldMessages xatoligi: $e');
    }
  }

  // ── fetchOrCreateChat ─────────────────────────────────────────────────────
  Future<Chat> fetchOrCreateChat(User other) async {
    final ids   = [_me!.id, other.id]..sort();
    final chatId = '${ids[0]}_${ids[1]}';

    final existingIdx = _chats.indexWhere((c) => c.id == chatId);
    if (existingIdx != -1 && _chats[existingIdx].messages.isNotEmpty) {
      return _chats[existingIdx];
    }

    Chat currentChat;
    if (existingIdx != -1) {
      currentChat = _chats[existingIdx];
    } else {
      currentChat = Chat(
        id:        chatId,
        name:      other.name,
        type:      ChatType.personal,
        memberIds: [_me!.id, other.id],
        messages:  [],
      );
      _chats.insert(0, currentChat);
    }

    try {
      final List<dynamic> data = await sb.Supabase.instance.client
          .from('messages')
          .select()
          .eq('chatid', chatId)
          .order('created_at', ascending: true);

      if (data.isNotEmpty) {
        currentChat.messages.clear();
        currentChat.unreadCount = 0;

        for (final row in data) {
          final content  = row['content'] as String? ?? '';
          final isImage  = _isImageContent(content);
          final rawTs    = row['created_at'] as String?;
          final timestamp = rawTs != null ? DateTime.tryParse(rawTs) ?? DateTime.now() : DateTime.now();
          final bool isRead = row['isread'] == true;  // ✅ FIX
          final senderId = row['senderid'] as String? ?? '';
          final isMine   = senderId == _me!.id;

          final msg = Message(
            id:         row['id']?.toString() ?? '',
            chatId:     chatId,
            senderId:   senderId,
            senderName: row['sendername'] as String? ?? '',
            content:    content,
            type:       isImage ? MessageType.image : MessageType.text,
            timestamp:  timestamp,
            isRead:     isRead, // ✅ FIX
          );

          currentChat.messages.add(msg);

          // ✅ FIX: unreadCount shu yerda hisoblanadi
          if (!isMine && !isRead) {
            currentChat.unreadCount++;
          }
        }

        final lastMsg = currentChat.messages.last;
        currentChat.lastMessage     = lastMsg.type == MessageType.image ? '📷 Rasm' : lastMsg.content;
        currentChat.lastMessageTime = lastMsg.timestamp;
      }
    } catch (e) {
      if (kDebugMode) print('🚨 fetchOrCreateChat xatolik: $e');
    }

    _sortChats();
    notifyListeners();
    return currentChat;
  }

  // ── Matn yuborish ─────────────────────────────────────────────────────────
  Future<void> sendText(String chatId, String text, String chatName, BuildContext context) async {
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
      isRead:     false,
    );

    int i = _chats.indexWhere((c) => c.id == chatId);
    if (i == -1) {
      _chats.insert(0, Chat(
        id: chatId, name: chatName, type: ChatType.personal, memberIds: [_me!.id], messages: [],
      ));
      i = 0;
    }
    _addMsgAndFormat(_chats[i], localMsg);

    _ws.sendMessage(
      chatId: chatId, senderId: _me!.id, senderName: _me!.name, content: cleanText,
    );

    try {
      await sb.Supabase.instance.client.from('messages').insert({
        'chatid':     chatId,
        'senderid':   _me!.id,
        'sendername': _me!.name,
        'content':    cleanText,
        'type':       'text',
        'isread':     false,
      });
    } catch (e) {
      if (kDebugMode) print('🚨 BAZAGA YOZISH XATOLIGI: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xabar yuborilmadi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Rasm yuborish ─────────────────────────────────────────────────────────
  Future<void> sendImage(String chatId, XFile xFile, String senderName, BuildContext context) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path     = 'chat_images/$fileName';
      final Uint8List fileBytes = await xFile.readAsBytes();

      await sb.Supabase.instance.client.storage
          .from('chat_bucket')
          .uploadBinary(path, fileBytes);

      final String imageUrl = sb.Supabase.instance.client.storage
          .from('chat_bucket')
          .getPublicUrl(path);

      await sb.Supabase.instance.client.from('messages').insert({
        'chatid':     chatId,
        'senderid':   sb.Supabase.instance.client.auth.currentUser!.id,
        'sendername': senderName,
        'content':    imageUrl,
        'type':       'image',
        'isread':     false,
      });
    } catch (e) {
      debugPrint('Rasm xatoligi: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rasm yuklanmadi: $e')),
        );
      }
    }
  }

  // ── WebSocket stream ───────────────────────────────────────────────────────
  void _onIncoming(Message msg) {
    if (msg.chatId.isEmpty) return;

    final chatIdx = _chats.indexWhere((c) => c.id == msg.chatId);
    if (chatIdx != -1) {
      final chat      = _chats[chatIdx];
      final isDuplicate = chat.messages.any((m) =>
      m.id == msg.id ||
          (m.content == msg.content && m.senderId == msg.senderId && m.id.startsWith('local_')));

      if (!isDuplicate) {
        _addMsgAndFormat(chat, msg);

        if (_activeChatId == msg.chatId) {
          if (msg.senderId != _me?.id) markAsRead(msg.chatId);
        } else if (msg.senderId != _me?.id) {
          // ✅ FIX: isRead false bo'lsagina oshiriladi
          if (!msg.isRead) chat.unreadCount++;
          notifyListeners();
        }
      }
    } else if (msg.senderId != _me?.id) {
      final newChat = Chat(
        id:              msg.chatId,
        name:            msg.senderName.isNotEmpty ? msg.senderName : 'Foydalanuvchi',
        type:            ChatType.personal,
        memberIds:       [_me?.id ?? '', msg.senderId],
        messages:        [msg],
        lastMessage:     msg.type == MessageType.image ? '📷 Rasm' : msg.content,
        lastMessageTime: msg.timestamp,
        unreadCount:     (!msg.isRead && _activeChatId != msg.chatId) ? 1 : 0,
      );
      _chats.insert(0, newChat);
      _sortChats();
      notifyListeners();
    }
  }

  void _addMsgAndFormat(Chat chat, Message msg) {
    if (!chat.messages.any((m) => m.id == msg.id)) {
      chat.messages.add(msg);
    }
    chat.lastMessage     = msg.type == MessageType.image ? '📷 Rasm' : msg.content;
    chat.lastMessageTime = msg.timestamp;
    _sortChats();
    notifyListeners();
  }

  void _sortChats() {
    _chats.sort((a, b) =>
        (b.lastMessageTime ?? DateTime(0)).compareTo(a.lastMessageTime ?? DateTime(0)));
  }

  // ── Yordamchi: rasm URL ekanligini tekshirish ────────────────────────────
  bool _isImageContent(String content) {
    return content.startsWith('http') &&
        (content.contains('.jpg') || content.contains('.png') || content.contains('chat_images'));
  }

  // ── Qolgan funksiyalar ────────────────────────────────────────────────────
  Future<void> loadAllUsers() async {
    if (_me == null) return;
    try {
      final List<dynamic> data = await sb.Supabase.instance.client
          .from('users')
          .select('id, name, avatarurl, isonline')
          .neq('id', _me!.id);
      _allUsers = data.map((row) => User.fromJson(row)).toList();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 loadAllUsers xatolik: $e');
    }
  }

  Future<void> _saveUserToDb(String id, String name) async {
    try {
      final sbUser    = sb.Supabase.instance.client.auth.currentUser;
      final avatarUrl = sbUser?.userMetadata?['avatar_url'] as String? ?? '';
      await sb.Supabase.instance.client.from('users').upsert({
        'id': id, 'name': name, 'avatarurl': avatarUrl, 'isonline': true,
      }, onConflict: 'id');
    } catch (e) {
      if (kDebugMode) print('🚨 _saveUserToDb xatolik: $e');
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      if (_me != null) {
        await sb.Supabase.instance.client
            .from('users').update({'isonline': false}).eq('id', _me!.id);
      }
      _realtimeChannel?.unsubscribe();
      _realtimeChannel = null;
      await sb.Supabase.instance.client.auth.signOut();
      try {
        await GoogleSignIn().signOut();
        await GoogleSignIn().disconnect();
      } catch (_) {}
      await _wsSub?.cancel();
      _wsSub = null;
      try { (_ws as dynamic).disconnect(); } catch (_) {}
      _me = null;
      _chats.clear();
      _allUsers.clear();
      _searchQuery   = '';
      _activeChatId  = null;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 logout xatolik: $e');
    }
  }

  // ── Chatni o'chirish ──────────────────────────────────────────────────────
  Future<void> deleteChat(String chatId) async {
    try {
      // Avval chatdagi barcha xabarlarni o'chiramiz
      await sb.Supabase.instance.client
          .from('messages')
          .delete()
          .eq('chatid', chatId);

      // Lokal listdan olib tashlaymiz
      _chats.removeWhere((c) => c.id == chatId);

      // Agar hozir ochiq bo'lsa — yopamiz
      if (_activeChatId == chatId) _activeChatId = null;

      notifyListeners();
      if (kDebugMode) print('✅ Chat o\'chirildi: $chatId');
    } catch (e) {
      if (kDebugMode) print('🚨 deleteChat xatolik: $e');
    }
  }

  // ── Foydalanuvchini o'chirish ─────────────────────────────────────────────
  Future<void> deleteUser(String userId) async {
    try {
      await sb.Supabase.instance.client
          .from('users')
          .delete()
          .eq('id', userId);

      _allUsers.removeWhere((u) => u.id == userId);
      notifyListeners();

      if (kDebugMode) print('✅ Foydalanuvchi o\'chirildi: $userId');
    } catch (e) {
      if (kDebugMode) print('🚨 deleteUser xatolik: $e');
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }
}