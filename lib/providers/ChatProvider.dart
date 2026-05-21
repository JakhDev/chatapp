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
  StreamSubscription? _wsSub;

  // ✅ Supabase Realtime obunasi uchun kanal
  sb.RealtimeChannel? _realtimeChannel;

  User?            _me;
  final List<Chat> _chats = [];
  String           _searchQuery = '';
  List<User>       _allUsers = [];
  String?          _activeChatId; // Hozir ekranda ochiq turgan chat ID-si

  User?      get currentUser => _me;
  List<User> get allUsers    => List.unmodifiable(_allUsers);

  // Qidiruv tizimi filtri bilan chatlar ro'yxati
  List<Chat> get chats {
    if (_searchQuery.isEmpty) return List.unmodifiable(_chats);
    return List.unmodifiable(
      _chats
          .where((c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList(),
    );
  }

  ChatProvider(this._ws) {
    // WebSocket-dan keladigan xabarlarni tinglash
    _wsSub = _ws.msgStream.listen(_onIncoming);

    // Agar foydalanuvchi tizimda login bo'lgan bo'lsa, avtomat sessiyani tiklash
    final sbUser = sb.Supabase.instance.client.auth.currentUser;
    if (sbUser != null) {
      final name = sbUser.userMetadata?['full_name'] as String? ??
          sbUser.userMetadata?['name']  as String? ??
          sbUser.email ??
          'User';
      _loginWithId(sbUser.id, name);
    }
  }

  // ── Bitta chatning barcha xabarlarini qaytarish ────────────────────────────
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

    // Serverlarga ulanish
    _ws.connect(_me!.id);
    _subscribeRealtime();

    notifyListeners();
    loadAllUsers(); // ✅ SHU QO'SHILDI

    _saveUserToDb(id, name);
    loadOldMessages(); // Barcha eski chat va xabarlarni dastlabki yuklash
  }

  // ── Supabase Realtime: Yangi xabarlarni jonli tutib olish ────────────────
  void _subscribeRealtime() {
    _realtimeChannel?.unsubscribe();

    _realtimeChannel = sb.Supabase.instance.client
        .channel('public:messages')
        .onPostgresChanges(
      event: sb.PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        if (kDebugMode) print('🔴 Realtime baza orqali xabar keldi: ${payload.newRecord}');
        _onRealtimeMessage(payload.newRecord);
      },
    );

    _realtimeChannel?.subscribe();
  }

  // ── Realtime-dan kelgan ma'lumotni modelga o'tkazish ─────────────────────
  void _onRealtimeMessage(Map<String, dynamic> row) {
    if (_me == null) return;

    final String chatId     = row['chatid']     as String? ?? '';
    final String msgId      = row['id']?.toString() ?? '';
    final String senderId   = row['senderid']   as String? ?? '';
    final String senderName = row['sendername'] as String? ?? '';
    final String content    = row['content']    as String? ?? '';
    // ✅ TO'G'RI: 'isread' (pastki chiziqsiz)
    final bool isRead       = row['isread'] == true;

    if (chatId.isEmpty || content.isEmpty) return;

    final rawTs = row['created_at'] as String? ?? row['timestamp'] as String?;
    final timestamp = rawTs != null ? DateTime.tryParse(rawTs) ?? DateTime.now() : DateTime.now();

    final isImage = content.startsWith('http') &&
        (content.contains('.jpg') || content.contains('.png') || content.contains('chat_images'));

    final msg = Message(
      id:         msgId,
      chatId:     chatId,
      senderId:   senderId,
      senderName: senderName,
      content:    content,
      type:       isImage ? MessageType.image : MessageType.text,
      timestamp:  timestamp,
    );

    final isMine = msg.senderId == _me!.id;
    final chatIdx = _chats.indexWhere((c) => c.id == msg.chatId);

    if (chatIdx != -1) {
      final chat = _chats[chatIdx];

      final localIdx = chat.messages.indexWhere((m) =>
      m.id.startsWith('local_') &&
          m.content == msg.content &&
          m.senderId == msg.senderId);

      if (localIdx != -1) {
        chat.messages[localIdx] = msg;
      } else if (!chat.messages.any((m) => m.id == msg.id)) {
        chat.messages.add(msg);

        // 🔥 FAQAT SHUNDA SONI OSHADI: Agar chat ochiq bo'lmasa va xabar begona odamdan bo'lsa
        if (!isMine && _activeChatId != msg.chatId && !isRead) {
          chat.unreadCount++;
        }
      }

      chat.lastMessage = msg.type == MessageType.image ? '📷 Rasm' : msg.content;
      chat.lastMessageTime = msg.timestamp;

      if (_activeChatId == msg.chatId && !isMine) {
        chat.unreadCount = 0;
        markAsRead(msg.chatId);
      }

    } else {
      final idList = msg.chatId.split('_');
      final otherId = idList.first == _me!.id ? idList.last : idList.first;

      final otherUser = _allUsers.firstWhere(
            (u) => u.id == otherId,
        orElse: () => User(id: otherId, name: msg.senderName.isNotEmpty ? msg.senderName : 'Foydalanuvchi'),
      );

      final newChat = Chat(
        id:              msg.chatId,
        name:            otherUser.name,
        type:            ChatType.personal,
        memberIds:       [_me!.id, otherId],
        messages:        [msg],
        lastMessage:     msg.type == MessageType.image ? '📷 Rasm' : msg.content,
        lastMessageTime: msg.timestamp,
        unreadCount:     (!isMine && _activeChatId != msg.chatId && !isRead) ? 1 : 0,
      );
      _chats.insert(0, newChat);
    }

    _sortChats();
    notifyListeners();
  }

  // ── 🔥 CHAT OCHILGANDA BAZADA O'QILDI QILISH ─────────────────────────────
  Future<void> markAsRead(String chatId) async {
    if (_me == null) return;
    try {
      // ✅ TO'G'RI: 'isread' (pastki chiziqsiz)
      await sb.Supabase.instance.client
          .from('messages')
          .update({'isread': true})
          .eq('chatid', chatId)
          .neq('senderid', _me!.id);

      final chatIdx = _chats.indexWhere((c) => c.id == chatId);
      if (chatIdx != -1) {
        _chats[chatIdx].unreadCount = 0;
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) print('🚨 markAsRead xatolik: $e');
    }
  }

  // ── Foydalanuvchini ro'yxatdan o'tkazish yoki yangilash ──────────────────
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
    } catch (e) {
      if (kDebugMode) print('🚨 _saveUserToDb xatolik: $e');
    }
  }

  // ── Kontaktdagi barcha foydalanuvchilarni yuklash (o'zidan tashqari) ──────
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

  // ── AQLLI FUNKSIYA: Chatga kirganda eski xabarlarni bazadan tortish ───────
  Future<Chat> fetchOrCreateChat(User other) async {
    final ids = [_me!.id, other.id]..sort();
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
        for (final row in data) {
          final content = row['content'] as String? ?? '';
          final isImage = content.startsWith('http') &&
              (content.contains('.jpg') || content.contains('.png') || content.contains('chat_images'));

          final rawTs = row['created_at'] as String?;
          final timestamp = rawTs != null ? DateTime.tryParse(rawTs) ?? DateTime.now() : DateTime.now();
          // ✅ TO'G'RI: 'isread' (pastki chiziqsiz)
          final bool isRead = row['isread'] == true;

          final msg = Message(
            id:         row['id']?.toString() ?? '',
            chatId:     chatId,
            senderId:   row['senderid'] as String? ?? '',
            senderName: row['sendername'] as String? ?? '',
            content:    content,
            type:       isImage ? MessageType.image : MessageType.text,
            timestamp:  timestamp,
          );

          try { (msg as dynamic).isRead = isRead; } catch (_) {}
          currentChat.messages.add(msg);
        }
        final lastMsg = currentChat.messages.last;
        currentChat.lastMessage = lastMsg.type == MessageType.image ? '📷 Rasm' : lastMsg.content;
        currentChat.lastMessageTime = lastMsg.timestamp;
      }
    } catch (e) {
      if (kDebugMode) print('🚨 fetchOrCreateChat xatolik: $e');
    }

    _sortChats();
    notifyListeners();
    return currentChat;
  }

  // ── Ilova ilk marta yonganida barcha eski xabarlarni yuklash ─────────────
  Future<void> loadOldMessages() async {
    if (_me == null) return;
    try {
      final List<dynamic> usersData = await sb.Supabase.instance.client
          .from('users')
          .select('id, name');

      final Map<String, String> userNames = {
        for (var u in usersData) u['id'] as String : u['name'] as String? ?? 'Foydalanuvchi'
      };

      final List<dynamic> data = await sb.Supabase.instance.client
          .from('messages')
          .select()
          .order('created_at', ascending: true);

      _chats.clear();

      for (final row in data) {
        final String chatId     = row['chatid']     as String? ?? '';
        final String senderId   = row['senderid']   as String? ?? '';
        final String senderName = row['sendername'] as String? ?? '';
        final String content    = row['content']    as String? ?? '';
        if (chatId.isEmpty) continue;

        final rawTs = row['created_at'] as String? ?? row['timestamp'] as String?;
        final timestamp = rawTs != null ? DateTime.tryParse(rawTs) ?? DateTime.now() : DateTime.now();

        final isImage = content.startsWith('http') &&
            (content.contains('.jpg') || content.contains('.png') || content.contains('chat_images'));

        final msg = Message(
          id:         row['id']?.toString() ?? '',
          chatId:     chatId,
          senderId:   senderId,
          senderName: senderName,
          content:    content,
          type:       isImage ? MessageType.image : MessageType.text,
          timestamp:  timestamp,
        );

        final idList = chatId.split('_');
        String normalizedChatId = chatId;
        String otherId = _me!.id;

        if (idList.length >= 2) {
          idList.sort();
          normalizedChatId = idList.join('_');
          otherId = idList.first == _me!.id ? idList.last : idList.first;
        } else {
          otherId = msg.senderId == _me!.id ? _me!.id : msg.senderId;
        }

        // 🔥 STRATEGIK FILTR: O'zi bilan bo'lgan chatni o'tkazib yuborish
        if (otherId == _me!.id) continue;

        int chatIdx = _chats.indexWhere((c) => c.id == normalizedChatId);

        if (chatIdx == -1) {
          final chatName = userNames[otherId] ??
              (msg.senderId == _me!.id ? 'Foydalanuvchi' : msg.senderName);

          _chats.add(Chat(
            id:        normalizedChatId,
            name:      chatName.isNotEmpty ? chatName : 'Foydalanuvchi',
            type:      ChatType.personal,
            memberIds: [_me!.id, otherId],
            messages:  [],
            unreadCount: 0,
          ));
          chatIdx = _chats.length - 1;
        }

        final currentChat = _chats[chatIdx];
        if (!currentChat.messages.any((m) => m.id == msg.id)) {
          currentChat.messages.add(msg);
        }

        currentChat.lastMessage = msg.type == MessageType.image ? '📷 Rasm' : msg.content;
        currentChat.lastMessageTime = msg.timestamp;
      }

      // O'qilmagan xabarlarni hisoblash
      for (var chat in _chats) {
        chat.messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        int count = 0;
        for (var m in chat.messages) {
          final isMine = m.senderId == _me!.id;
          final dbRow = data.firstWhere(
                (row) => row['id']?.toString() == m.id,
            orElse: () => null,
          );
          if (dbRow != null) {
            // ✅ TO'G'RI: 'isread' (pastki chiziqsiz)
            final bool isMsgRead = dbRow['isread'] == true;
            if (!isMine && !isMsgRead) count++;
          }
        }
        chat.unreadCount = count;
      }

      _sortChats();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 loadOldMessages xatoligi: $e');
    }
  }

  void openChat(String chatId) {
    _activeChatId = chatId; // Aktiv oyna belgilandi
    _ws.joinChat(chatId);

    // 🔥 LOKALDA DARHOL NOLGA TUSHIRAMIZ (UI tez o'zgarishi uchun)
    final i = _chats.indexWhere((c) => c.id == chatId);
    if (i != -1) {
      _chats[i].unreadCount = 0;
      notifyListeners();
    }

    // Orqa fonda bazani yangilash
    markAsRead(chatId);
  }

  // Chat ekrandan yopilganda chaqiriladi
  void closeChat() {
    _activeChatId = null;
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  // ── Matn yuborish ─────────────────────────────────────────────────────────
  Future<void> sendText(String chatId, String text, String chatName, BuildContext context) async {
    if (_me == null || text.trim().isEmpty) return;

    final cleanText = text.trim();
    final timeNow = DateTime.now();

    // 1. UI uchun vaqtinchalik xabar (darhol chiqishi uchun)
    final localMsg = Message(
      id: 'local_${timeNow.millisecondsSinceEpoch}',
      chatId: chatId,
      senderId: _me!.id,
      senderName: _me!.name,
      content: cleanText,
      type: MessageType.text,
      timestamp: timeNow,
    );

    int i = _chats.indexWhere((c) => c.id == chatId);
    if (i == -1) {
      _chats.insert(0, Chat(
        id: chatId,
        name: chatName,
        type: ChatType.personal,
        memberIds: [_me!.id],
        messages: [],
      ));
      i = 0;
    }
    _addMsgAndFormat(_chats[i], localMsg);

    // 2. WebSocket orqali jonli yuborish
    _ws.sendMessage(
      chatId: chatId,
      senderId: _me!.id,
      senderName: _me!.name,
      content: cleanText,
    );

    // 3. Supabase'ga yozish
    try {
      // ✅ TO'G'RI: 'isread' (pastki chiziqsiz)
      await sb.Supabase.instance.client.from('messages').insert({
        'chatid':     chatId,
        'senderid':   _me!.id,
        'sendername': _me!.name,
        'content':    cleanText,
        'type':       'text',
        'isread':     false,
      });
      if (kDebugMode) print('✅ Xabar bazaga yozildi');
    } catch (e) {
      if (kDebugMode) print('🚨 BAZAGA YOZISH XATOLIGI: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Xabar yuborilmadi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Rasm yuborish ─────────────────────────────────────────────────────────
  Future<void> sendImage(String chatId, String filePath, String chatName, BuildContext context) async {
    if (_me == null || filePath.isEmpty) return;

    final file = File(filePath);
    final timeNow = DateTime.now();
    final fileName = '${_me!.id}_${timeNow.millisecondsSinceEpoch}.jpg';

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
      _chats.insert(0, Chat(
        id: chatId,
        name: chatName,
        type: ChatType.personal,
        memberIds: [_me!.id],
      ));
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
        chatId: chatId,
        senderId: _me!.id,
        senderName: _me!.name,
        content: publicUrl,
        type: MessageType.image,
      );

      // ✅ TO'G'RI: 'isread' (pastki chiziqsiz)
      await sb.Supabase.instance.client.from('messages').insert({
        'chatid':     chatId,
        'senderid':   _me!.id,
        'sendername': _me!.name,
        'content':    publicUrl,
        'type':       'image',
        'isread':     false,
      });
      if (kDebugMode) print('✅ Rasm bazaga yozildi');
    } catch (e) {
      if (kDebugMode) print('🚨 sendImage xatolik: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rasm yuborilmadi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Tizimdan chiqish (Logout) ─────────────────────────────────────────────
  Future<void> logout() async {
    try {
      if (_me != null) {
        await sb.Supabase.instance.client
            .from('users')
            .update({'isonline': false})
            .eq('id', _me!.id);
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
      _searchQuery = '';
      _activeChatId = null;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 logout xatolik: $e');
    }
  }

  // ── WebSocket oqimidan (Stream) kelgan yangi xabar ───────────────────────
  void _onIncoming(Message msg) {
    if (msg.chatId.isEmpty) return;

    final chatIdx = _chats.indexWhere((c) => c.id == msg.chatId);
    if (chatIdx != -1) {
      final chat = _chats[chatIdx];
      final isDuplicate = chat.messages.any((m) =>
      m.id == msg.id ||
          (m.content == msg.content &&
              m.senderId == msg.senderId &&
              m.id.startsWith('local_')));

      if (!isDuplicate) {
        _addMsgAndFormat(chat, msg);

        if (_activeChatId == msg.chatId) {
          try { (msg as dynamic).isRead = true; } catch (_) {}
          if (msg.senderId != _me?.id) markAsRead(msg.chatId);
        } else if (msg.senderId != _me?.id) {
          chat.unreadCount++;
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
        unreadCount:     _activeChatId != msg.chatId ? 1 : 0,
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

  @override
  void dispose() {
    _wsSub?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }
}