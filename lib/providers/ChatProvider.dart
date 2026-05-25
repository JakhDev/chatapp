import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/services/WebSocketService.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:google_sign_in/google_sign_in.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  UUID yordamchi funksiyalar
// ─────────────────────────────────────────────────────────────────────────────

({String part1, String part2})? _splitChatId(String chatId) {
  if (chatId.length == 73 && chatId[36] == '_') {
    return (part1: chatId.substring(0, 36), part2: chatId.substring(37));
  }
  if (chatId.length > 37) {
    final p1 = chatId.substring(0, 36);
    if (chatId[36] == '_') {
      final p2 = chatId.substring(37);
      if (p1.isNotEmpty && p2.isNotEmpty) {
        return (part1: p1, part2: p2);
      }
    }
  }
  return null;
}

String normalizeChatId(String id1, String id2) {
  final ids = [id1.trim().toLowerCase(), id2.trim().toLowerCase()]..sort();
  return '${ids[0]}_${ids[1]}';
}

String? otherIdFromChatId(String chatId, String myId) {
  final parts = _splitChatId(chatId);
  if (parts == null) return null;
  final myIdLower = myId.trim().toLowerCase();
  final p1Lower = parts.part1.trim().toLowerCase();
  final p2Lower = parts.part2.trim().toLowerCase();
  if (p1Lower == myIdLower) return parts.part2;
  if (p2Lower == myIdLower) return parts.part1;
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
//  ChatProvider
// ─────────────────────────────────────────────────────────────────────────────
class ChatProvider extends ChangeNotifier {
  final WebSocketService _ws;
  StreamSubscription? _wsSub;
  sb.RealtimeChannel? _realtimeChannel;
  sb.RealtimeChannel? _presenceChannel;
  sb.RealtimeChannel? _clearHistoryChannel;

  Timer? _heartbeatTimer;

  User? _me;
  final List<Chat> _chats = [];
  String _searchQuery = '';
  List<User> _allUsers = [];
  String? _activeChatId;

  bool _isLoggingOut = false;

  final Map<String, bool> _onlineStatuses = {};
  final Map<String, DateTime> _lastSeenMap = {};

  // ─── Public getters ───────────────────────────────────────────────────────
  User? get currentUser => _me;
  Map<String, bool> get onlineStatuses => Map.unmodifiable(_onlineStatuses);
  Map<String, DateTime> get lastSeenMap => Map.unmodifiable(_lastSeenMap);

  bool isUserOnline(String userId) =>
      _onlineStatuses[userId.toLowerCase()] ?? false;
  DateTime? getLastSeen(String userId) =>
      _lastSeenMap[userId.toLowerCase()];

  List<Chat> get chats {
    final q = _searchQuery.toLowerCase().trim();
    if (q.isEmpty) return List.unmodifiable(_chats);
    return List.unmodifiable(
      _chats.where(
            (c) =>
        c.name.toLowerCase().contains(q) ||
            (c.lastMessage ?? '').toLowerCase().contains(q),
      ),
    );
  }

  List<User> get allUsers {
    final q = _searchQuery.toLowerCase().trim();
    if (q.isEmpty) return List.unmodifiable(_allUsers);
    return List.unmodifiable(
      _allUsers.where((u) => u.name.toLowerCase().contains(q)),
    );
  }

  List<Chat> get personalChats =>
      List.unmodifiable(_chats.where((c) => c.type == ChatType.personal));
  List<Chat> get groupChats =>
      List.unmodifiable(_chats.where((c) => c.type == ChatType.group));

  // ─── Constructor ──────────────────────────────────────────────────────────
  ChatProvider(this._ws) {
    _wsSub = _ws.msgStream.listen(_onIncoming);
    final sbUser = sb.Supabase.instance.client.auth.currentUser;
    if (sbUser != null) {
      final name = sbUser.userMetadata?['full_name'] as String? ??
          sbUser.userMetadata?['name'] as String? ??
          sbUser.email ??
          'User';
      _loginWithId(sbUser.id, name);
    }
  }

  List<Message> messages(String chatId) {
    final chat = _chats.firstWhere(
          (c) => c.id == chatId,
      orElse: () =>
          Chat(id: '', name: '', type: ChatType.personal, memberIds: []),
    );
    return List.unmodifiable(chat.messages);
  }

  void login(String name) {
    final sbUser = sb.Supabase.instance.client.auth.currentUser;
    if (sbUser != null) _loginWithId(sbUser.id, name);
  }

  void _loginWithId(String id, String name) {
    _isLoggingOut = false;
    _me = User(id: id, name: name, isOnline: true);
    _ws.connect(_me!.id);
    _subscribeRealtime();
    _subscribePresence();
    _subscribeClearHistory();
    _startHeartbeat();
    notifyListeners();
    loadAllUsers();
    _saveUserToDb(id, name);
    loadOldMessages();
  }

  // ─── Heartbeat ────────────────────────────────────────────────────────────
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _updateOwnLastSeen();
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => _updateOwnLastSeen());
  }

  Future<void> _updateOwnLastSeen() async {
    final uid = _me?.id;
    if (uid == null) return;
    try {
      await sb.Supabase.instance.client
          .from('users')
          .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
          .eq('id', uid);
    } catch (e) {
      if (kDebugMode) print('🚨 _updateOwnLastSeen: $e');
    }
  }

  // ─── Presence ─────────────────────────────────────────────────────────────
  void _subscribePresence() {
    _presenceChannel?.unsubscribe();
    if (_me == null) return;

    _presenceChannel = sb.Supabase.instance.client
        .channel('online_users')
        .onPresenceSync((payload) {
      final state = _presenceChannel?.presenceState() ?? {};
      final onlineIds = <String>{};
      (state as Map).forEach((key, value) {
        for (final p in (value as List)) {
          final uid = (p.payload as Map<String, dynamic>)['user_id']
              ?.toString()
              .toLowerCase();
          if (uid != null) onlineIds.add(uid);
        }
      });
      for (final u in _allUsers) {
        _onlineStatuses[u.id.toLowerCase()] =
            onlineIds.contains(u.id.toLowerCase());
      }
      if (_me != null) {
        _onlineStatuses[_me!.id.toLowerCase()] = true;
      }
      notifyListeners();
    }).onPresenceJoin((payload) {
      final userId = payload.newPresences.isNotEmpty
          ? payload.newPresences.first.payload['user_id']
          ?.toString()
          .toLowerCase()
          : null;
      if (userId != null) {
        _onlineStatuses[userId] = true;
        notifyListeners();
      }
    }).onPresenceLeave((payload) {
      final userId = payload.leftPresences.isNotEmpty
          ? payload.leftPresences.first.payload['user_id']
          ?.toString()
          .toLowerCase()
          : null;
      if (userId == null || userId == _me?.id.toLowerCase()) return;
      _onlineStatuses[userId] = false;
      _lastSeenMap[userId] = DateTime.now().toUtc();
      _updateLastSeen(userId);
      notifyListeners();
    });

    _presenceChannel?.subscribe((status, error) async {
      if (status == sb.RealtimeSubscribeStatus.subscribed) {
        await _presenceChannel?.track({'user_id': _me!.id});
      }
    });
  }

  Future<void> _updateLastSeen(String userId) async {
    try {
      await sb.Supabase.instance.client
          .from('users')
          .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
          .eq('id', userId);
    } catch (e) {
      if (kDebugMode) print('🚨 _updateLastSeen: $e');
    }
  }

  // ─── Clear history broadcast ──────────────────────────────────────────────
  void _subscribeClearHistory() {
    _clearHistoryChannel?.unsubscribe();
    _clearHistoryChannel = sb.Supabase.instance.client
        .channel('clear_history_events')
        .onBroadcast(
      event: 'clear_history',
      callback: (payload) {
        final chatId = payload['chat_id'] as String?;
        if (chatId != null) _applyClearHistory(chatId);
      },
    )
        .subscribe();
  }

  void _applyClearHistory(String chatId) {
    final i = _chats.indexWhere((c) => c.id == chatId);
    if (i != -1) {
      _chats[i].messages.clear();
      _chats[i].lastMessage = null;
      _chats[i].lastMessageTime = null;
      _chats[i].unreadCount = 0;
      notifyListeners();
    }
  }

  // ─── Realtime ─────────────────────────────────────────────────────────────
  void _subscribeRealtime() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = sb.Supabase.instance.client
        .channel('public:messages:${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
      event: sb.PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (p) => _onRealtimeMessage(p.newRecord),
    )
        .onPostgresChanges(
      event: sb.PostgresChangeEvent.update,
      schema: 'public',
      table: 'messages',
      callback: (p) => _onRealtimeUpdate(p.newRecord),
    )
        .onPostgresChanges(
      event: sb.PostgresChangeEvent.delete,
      schema: 'public',
      table: 'messages',
      callback: (p) => _onRealtimeDelete(p.oldRecord),
    );
    _realtimeChannel?.subscribe();
  }

  void _onRealtimeDelete(Map<String, dynamic> row) {
    final msgId = row['id']?.toString() ?? '';
    if (msgId.isEmpty) return;
    for (int ci = 0; ci < _chats.length; ci++) {
      final mi = _chats[ci].messages.indexWhere((m) => m.id == msgId);
      if (mi != -1) {
        _chats[ci].messages.removeAt(mi);
        _refreshLastMsg(ci);
        notifyListeners();
        break;
      }
    }
  }

  void _onRealtimeUpdate(Map<String, dynamic> row) {
    final msgId = row['id']?.toString() ?? '';
    final chatId = row['chatid'] as String? ?? '';
    final isDeleted = row['is_deleted'] == true;
    final isEdited = row['is_edited'] == true;
    final newContent = row['content'] as String? ?? '';
    final isRead = row['isread'] == true;

    final myId = _me?.id ?? '';
    final otherId = otherIdFromChatId(chatId, myId) ?? '';
    final normalId =
    otherId.isNotEmpty ? normalizeChatId(myId, otherId) : chatId;

    final ci = _chats.indexWhere((c) => c.id == normalId);
    if (ci == -1) return;
    final mi = _chats[ci].messages.indexWhere((m) => m.id == msgId);
    if (mi == -1) return;
    final old = _chats[ci].messages[mi];

    _chats[ci].messages[mi] = old.copyWith(
      content: isDeleted ? '' : newContent,
      isEdited: isEdited,
      isDeleted: isDeleted,
      isRead: isRead,
    );
    if (isDeleted) _refreshLastMsg(ci);
    notifyListeners();
  }

  void _onRealtimeMessage(Map<String, dynamic> row) {
    if (_me == null) return;

    final chatId = row['chatid'] as String? ?? '';
    final msgId = row['id']?.toString() ?? '';
    final senderId = row['senderid'] as String? ?? '';
    final senderName = row['sendername'] as String? ?? '';
    final content = row['content'] as String? ?? '';
    final isRead = row['isread'] == true;
    if (chatId.isEmpty || content.isEmpty) return;

    final myId = _me!.id;
    final otherId = otherIdFromChatId(chatId, myId) ?? senderId;
    final normalId = normalizeChatId(myId, otherId);

    final rawTs =
        row['created_at'] as String? ?? row['timestamp'] as String?;
    final ts = _parseTs(rawTs);
    final isImage = _isImageContent(content);
    final isAudio = row['type'] == 'audio';
    final audioDuration = row['audio_duration'] as int? ?? 0;

    final msg = Message(
      id: msgId,
      chatId: normalId,
      senderId: senderId,
      senderName: senderName,
      content: content,
      type: isImage
          ? MessageType.image
          : isAudio
          ? MessageType.audio
          : MessageType.text,
      timestamp: ts,
      isRead: isRead,
      isEdited: false,
      isDeleted: false,
      replyToId: row['reply_to_id'] as String?,
      replyToContent: row['reply_to_content'] as String?,
      replyToSender: row['reply_to_sender'] as String?,
      audioDuration: isAudio ? audioDuration : null,
    );

    final isMine = senderId == myId;
    final ci = _chats.indexWhere((c) => c.id == normalId);

    if (ci != -1) {
      _onNewMessage(normalId, msg);
      final chat = _chats[ci];
      final pendingIdx = chat.messages.indexWhere(
            (m) =>
        m.id == msgId ||
            (m.id.startsWith('local_') &&
                m.content == content &&
                m.senderId == senderId),
      );

      if (pendingIdx != -1) {
        chat.messages[pendingIdx] = msg;
      } else if (!chat.messages.any((m) => m.id == msgId)) {
        chat.messages.add(msg);
        if (!isMine && _activeChatId != normalId && !isRead) {
          chat.unreadCount++;
        }
      }

      chat.lastMessage = _lastMsgText(isImage, isAudio, content);
      chat.lastMessageTime = ts;

      if (_activeChatId == normalId && !isMine) {
        chat.unreadCount = 0;
        markAsRead(normalId);
      }
    } else {
      final other = _allUsers.firstWhere(
            (u) => u.id.toLowerCase() == otherId.toLowerCase(),
        orElse: () => User(
          id: otherId,
          name: senderName.isNotEmpty ? senderName : 'Foydalanuvchi',
        ),
      );

      _chats.insert(
        0,
        Chat(
          id: normalId,
          name: other.name,
          type: ChatType.personal,
          memberIds: [myId, otherId],
          messages: [msg],
          lastMessage: _lastMsgText(isImage, isAudio, content),
          lastMessageTime: ts,
          unreadCount:
          (!isMine && _activeChatId != normalId && !isRead) ? 1 : 0,
          avatarUrl: other.avatarUrl,
        ),
      );
    }
    _sortChats();
    notifyListeners();
  }

  // ─── markAsRead ───────────────────────────────────────────────────────────
  Future<void> markAsRead(String chatId) async {
    if (_me == null) return;
    try {
      await sb.Supabase.instance.client
          .from('messages')
          .update({'isread': true})
          .eq('chatid', chatId)
          .neq('senderid', _me!.id)
          .eq('isread', false);

      final i = _chats.indexWhere((c) => c.id == chatId);
      if (i != -1) {
        for (var j = 0; j < _chats[i].messages.length; j++) {
          final m = _chats[i].messages[j];
          if (m.senderId != _me!.id && !m.isRead) {
            _chats[i].messages[j] = m.copyWith(isRead: true);
          }
        }
        _chats[i].unreadCount = 0;
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) print('🚨 markAsRead: $e');
    }
  }

  void openChat(String chatId) {
    _activeChatId = chatId;
    _ws.joinChat(chatId);
    final i = _chats.indexWhere((c) => c.id == chatId);
    if (i != -1) {
      for (var j = 0; j < _chats[i].messages.length; j++) {
        final m = _chats[i].messages[j];
        if (m.senderId != _me?.id && !m.isRead) {
          _chats[i].messages[j] = m.copyWith(isRead: true);
        }
      }
      _chats[i].unreadCount = 0;
      notifyListeners();
    }
    markAsRead(chatId);
  }

  void closeChat() => _activeChatId = null;

  // ─── sendText ─────────────────────────────────────────────────────────────
  Future<void> sendText(
      String chatId,
      String text,
      String chatName,
      BuildContext context, {
        Message? replyTo,
      }) async {
    if (_me == null || text.trim().isEmpty) return;
    final cleanText = text.trim();
    final timeNow = DateTime.now().toUtc();
    final localId = 'local_${timeNow.millisecondsSinceEpoch}';

    final localMsg = Message(
      id: localId,
      chatId: chatId,
      senderId: _me!.id,
      senderName: _me!.name,
      content: cleanText,
      type: MessageType.text,
      timestamp: _toLocal(timeNow),
      isRead: false,
      isEdited: false,
      isDeleted: false,
      replyToId: replyTo?.id,
      replyToContent: replyTo?.content,
      replyToSender: replyTo?.senderName,
    );

    int i = _chats.indexWhere((c) => c.id == chatId);
    if (i == -1) {
      _chats.insert(
        0,
        Chat(
          id: chatId,
          name: chatName,
          type: ChatType.personal,
          memberIds: [_me!.id],
          messages: [],
        ),
      );
      i = 0;
    }
    _addMsgAndFormat(_chats[i], localMsg);
    _ws.sendMessage(
      chatId: chatId,
      senderId: _me!.id,
      senderName: _me!.name,
      content: cleanText,
    );

    try {
      final rows = await sb.Supabase.instance.client
          .from('messages')
          .insert({
        'chatid': chatId,
        'senderid': _me!.id,
        'sendername': _me!.name,
        'content': cleanText,
        'type': 'text',
        'isread': false,
        'is_edited': false,
        'is_deleted': false,
        if (replyTo != null) 'reply_to_id': replyTo.id,
        if (replyTo != null) 'reply_to_content': replyTo.content,
        if (replyTo != null) 'reply_to_sender': replyTo.senderName,
      })
          .select('id')
          .maybeSingle();

      _replaceLocalId(chatId, localId, rows?['id']?.toString() ?? '');
    } catch (e) {
      if (kDebugMode) print('⚠️ sendText error: $e');
      _removeLocal(chatId, localId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Xabar yuborilmadi: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ─── editMessage ──────────────────────────────────────────────────────────
  Future<void> editMessage(
      String chatId,
      String messageId,
      String newContent,
      BuildContext context,
      ) async {
    if (_me == null || newContent.trim().isEmpty) return;
    if (messageId.startsWith('local_')) return;

    final ci = _chats.indexWhere((c) => c.id == chatId);
    if (ci == -1) return;
    final mi =
    _chats[ci].messages.indexWhere((m) => m.id == messageId);
    if (mi == -1) return;
    final old = _chats[ci].messages[mi];
    if (old.senderId != _me!.id) return;

    _chats[ci].messages[mi] =
        old.copyWith(content: newContent.trim(), isEdited: true);
    notifyListeners();

    try {
      await sb.Supabase.instance.client
          .from('messages')
          .update({'content': newContent.trim(), 'is_edited': true})
          .eq('id', messageId);
    } catch (e) {
      if (kDebugMode) print('🚨 editMessage: $e');
      _chats[ci].messages[mi] = old;
      notifyListeners();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tahrirlashda xatolik'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ─── deleteMessage ────────────────────────────────────────────────────────
  // ✅ FIX: deleteForEveryone=true → DB dan DELETE (ikkala user uchun)
  // ✅ FIX: deleteForEveryone=false → faqat local listdan olib tashlash
  Future<void> deleteMessage(
      String chatId,
      String messageId,
      BuildContext context, {
        required bool deleteForEveryone,
      }) async {
    if (_me == null) return;

    // local xabar bo'lsa ikkalasida ham faqat localdan olib tashlash
    if (messageId.startsWith('local_')) {
      _removeLocal(chatId, messageId);
      return;
    }

    final ci = _chats.indexWhere((c) => c.id == chatId);
    if (ci == -1) return;
    final mi = _chats[ci].messages.indexWhere((m) => m.id == messageId);
    if (mi == -1) return;
    final old = _chats[ci].messages[mi];

    if (deleteForEveryone) {
      // ✅ IKKALA USER UCHUN: DB dan to'liq DELETE
      // Sender kim bo'lishidan qat'iy nazar o'chiriladi
      // Realtime DELETE event boshqa userni ham yangilaydi
      _chats[ci].messages.removeAt(mi);
      _refreshLastMsg(ci);
      notifyListeners();

      try {
        await sb.Supabase.instance.client
            .from('messages')
            .delete()
            .eq('id', messageId);
        // ✅ Realtime DELETE event avtomatik boshqa userni ham yangilaydi
        // _onRealtimeDelete orqali
      } catch (e) {
        if (kDebugMode) print('🚨 deleteMessage (everyone): $e');
        // Rollback
        _chats[ci].messages.insert(mi, old);
        _refreshLastMsg(ci);
        notifyListeners();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("O'chirishda xatolik"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } else {
      // ✅ FAQAT O'ZIM UCHUN: faqat local listdan olib tashlash
      // DB da qoladi, boshqa user ko'ra oladi
      _chats[ci].messages.removeAt(mi);
      _refreshLastMsg(ci);
      notifyListeners();
    }
  }

  // ─── sendImage ────────────────────────────────────────────────────────────
  Future<void> sendImage(
      String chatId,
      XFile xFile,
      String senderName,
      BuildContext context,
      ) async {
    if (_me == null) return;

    final timeNow = DateTime.now().toUtc();
    final localId = 'local_img_${timeNow.millisecondsSinceEpoch}';
    final localMsg = Message(
      id: localId,
      chatId: chatId,
      senderId: _me!.id,
      senderName: senderName,
      content: '__uploading__',
      type: MessageType.image,
      timestamp: _toLocal(timeNow),
      isRead: false,
      isEdited: false,
      isDeleted: false,
    );

    int i = _chats.indexWhere((c) => c.id == chatId);
    if (i == -1) {
      _chats.insert(
        0,
        Chat(
          id: chatId,
          name: senderName,
          type: ChatType.personal,
          memberIds: [_me!.id],
        ),
      );
      i = 0;
    }
    _addMsgAndFormat(_chats[i], localMsg);

    try {
      final path =
          'chat_images/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await xFile.readAsBytes();
      await sb.Supabase.instance.client.storage
          .from('chat_bucket')
          .uploadBinary(path, bytes);
      final url = sb.Supabase.instance.client.storage
          .from('chat_bucket')
          .getPublicUrl(path);

      _updateLocalContent(chatId, localId, url);

      final result = await sb.Supabase.instance.client
          .from('messages')
          .insert({
        'chatid': chatId,
        'senderid': _me!.id,
        'sendername': senderName,
        'content': url,
        'type': 'image',
        'isread': false,
        'is_edited': false,
        'is_deleted': false,
      })
          .select('id')
          .maybeSingle();

      _replaceLocalId(chatId, localId, result?['id']?.toString() ?? '');
    } catch (e) {
      _removeLocal(chatId, localId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Rasm yuklanmadi: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
      if (kDebugMode) print('🚨 sendImage: $e');
    }
  }

  // ─── sendAudio ────────────────────────────────────────────────────────────
  Future<void> sendAudio(
      String chatId,
      String audioPath,
      String senderName,
      BuildContext context,
      String chatName, {
        int audioDuration = 0,
      }) async {
    if (_me == null || audioPath.isEmpty) return;

    final timeNow = DateTime.now().toUtc();
    final localId = 'local_audio_${timeNow.millisecondsSinceEpoch}';

    final localMsg = Message(
      id: localId,
      chatId: chatId,
      senderId: _me!.id,
      senderName: senderName,
      content: '__uploading__',
      type: MessageType.audio,
      timestamp: _toLocal(timeNow),
      isRead: false,
      isEdited: false,
      isDeleted: false,
      audioDuration: audioDuration,
    );

    int ci = _chats.indexWhere((c) => c.id == chatId);
    if (ci == -1) {
      _chats.insert(
        0,
        Chat(
          id: chatId,
          name: chatName,
          type: ChatType.personal,
          memberIds: [_me!.id],
          messages: [],
        ),
      );
      ci = 0;
    }
    _chats[ci].messages.add(localMsg);
    _chats[ci].lastMessage = '🎤 Ovozli xabar';
    _chats[ci].lastMessageTime = _toLocal(timeNow);
    _sortChats();
    notifyListeners();

    try {
      final fileName =
          'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final storagePath = 'chat_audio/$fileName';
      final bytes = await File(audioPath).readAsBytes();
      await sb.Supabase.instance.client.storage
          .from('chat_bucket')
          .uploadBinary(storagePath, bytes);
      final audioUrl = sb.Supabase.instance.client.storage
          .from('chat_bucket')
          .getPublicUrl(storagePath);

      _updateLocalContent(chatId, localId, audioUrl);

      final result = await sb.Supabase.instance.client
          .from('messages')
          .insert({
        'chatid': chatId,
        'senderid': _me!.id,
        'sendername': senderName,
        'content': audioUrl,
        'type': 'audio',
        'isread': false,
        'is_edited': false,
        'is_deleted': false,
        'audio_duration': audioDuration,
      })
          .select('id')
          .maybeSingle();

      _replaceLocalId(chatId, localId, result?['id']?.toString() ?? '');

      _ws.sendMessage(
        chatId: chatId,
        senderId: _me!.id,
        senderName: senderName,
        content: audioUrl,
        type: MessageType.audio,
      );
    } catch (e) {
      _removeLocal(chatId, localId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Ovozli xabar yuborilmadi: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
      if (kDebugMode) print('🚨 sendAudio: $e');
    }
  }

  // ─── loadOldMessages ──────────────────────────────────────────────────────
  Future<void> loadOldMessages() async {
    if (_me == null) return;
    try {
      final usersData = await sb.Supabase.instance.client
          .from('users')
          .select('id, name, avatarurl');
      final userNames = {
        for (var u in usersData)
          (u['id'] as String).toLowerCase():
          u['name'] as String? ?? 'Foydalanuvchi',
      };
      final userAvatars = {
        for (var u in usersData)
          (u['id'] as String).toLowerCase():
          u['avatarurl'] as String? ?? '',
      };

      final data = await sb.Supabase.instance.client
          .from('messages')
          .select()
          .order('created_at', ascending: true);

      _chats.clear();

      for (final row in data) {
        final chatId = row['chatid'] as String? ?? '';
        final senderId = row['senderid'] as String? ?? '';
        final content = row['content'] as String? ?? '';
        if (chatId.isEmpty) continue;

        final myId = _me!.id;
        final otherId = otherIdFromChatId(chatId, myId);
        if (otherId == null ||
            otherId.toLowerCase() == myId.toLowerCase()) continue;

        final normalId = normalizeChatId(myId, otherId);
        final ts = _parseTs(row['created_at'] as String?);
        final isRead = row['isread'] == true;
        final isEdited = row['is_edited'] == true;
        final isDeleted = row['is_deleted'] == true;
        final isImage = _isImageContent(content);
        final isAudio = row['type'] == 'audio';
        final isMine = senderId.toLowerCase() == myId.toLowerCase();
        final audioDuration = row['audio_duration'] as int? ?? 0;

        final msg = Message(
          id: row['id']?.toString() ?? '',
          chatId: normalId,
          senderId: senderId,
          senderName: row['sendername'] as String? ?? '',
          content: isDeleted ? '' : content,
          type: isImage
              ? MessageType.image
              : isAudio
              ? MessageType.audio
              : MessageType.text,
          timestamp: ts,
          isRead: isRead,
          isEdited: isEdited,
          isDeleted: isDeleted,
          replyToId: row['reply_to_id'] as String?,
          replyToContent: row['reply_to_content'] as String?,
          replyToSender: row['reply_to_sender'] as String?,
          audioDuration: isAudio ? audioDuration : null,
        );

        int ci = _chats.indexWhere((c) => c.id == normalId);
        if (ci == -1) {
          final otherIdLower = otherId.toLowerCase();
          final otherName = (userNames[otherIdLower] ?? '').isNotEmpty
              ? userNames[otherIdLower]!
              : (msg.senderName.isNotEmpty
              ? msg.senderName
              : 'Foydalanuvchi');
          final otherAvatar = userAvatars[otherIdLower] ?? '';
          _chats.add(Chat(
            id: normalId,
            name: otherName,
            type: ChatType.personal,
            memberIds: [myId, otherId],
            messages: [],
            unreadCount: 0,
            avatarUrl: otherAvatar.isNotEmpty ? otherAvatar : null,
          ));
          ci = _chats.length - 1;
        }

        if (!_chats[ci].messages.any((m) => m.id == msg.id)) {
          _chats[ci].messages.add(msg);
          if (!isMine && !isRead && !isDeleted) {
            _chats[ci].unreadCount++;
          }
        }
        _chats[ci].lastMessage = isDeleted
            ? "Xabar o'chirildi"
            : _lastMsgText(isImage, isAudio, content);
        _chats[ci].lastMessageTime = ts;
      }

      for (final chat in _chats) {
        chat.messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }
      _sortChats();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 loadOldMessages: $e');
    }
  }

  void _onNewMessage(String chatId, Message msg) {
    final i = _chats.indexWhere((c) => c.id == chatId);
    if (i != -1) {
      final chat = _chats[i];
      final updated = Chat(
        id: chat.id,
        name: chat.name,
        type: chat.type,
        memberIds: chat.memberIds,
        messages: chat.messages,
        lastMessage: msg.content,
        lastMessageTime: msg.timestamp,
        unreadCount: chat.unreadCount,
        avatarUrl: chat.avatarUrl,
      );
      _chats.removeAt(i);
      _chats.insert(0, updated);
    }
    notifyListeners();
  }

  // ─── fetchOrCreateChat ────────────────────────────────────────────────────
  Future<Chat> fetchOrCreateChat(User other) async {
    final myId = _me!.id;
    final chatId = normalizeChatId(myId, other.id);
    final existIdx = _chats.indexWhere((c) => c.id == chatId);
    if (existIdx != -1 && _chats[existIdx].messages.isNotEmpty) {
      return _chats[existIdx];
    }

    Chat current;
    if (existIdx != -1) {
      current = _chats[existIdx];
    } else {
      current = Chat(
        id: chatId,
        name: other.name,
        type: ChatType.personal,
        memberIds: [myId, other.id],
        messages: [],
        avatarUrl: other.avatarUrl,
      );
      _chats.insert(0, current);
    }

    try {
      final data = await sb.Supabase.instance.client
          .from('messages')
          .select()
          .eq('chatid', chatId)
          .order('created_at', ascending: true);

      if (data.isNotEmpty) {
        current.messages.clear();
        current.unreadCount = 0;
        for (final row in data) {
          final content = row['content'] as String? ?? '';
          final senderId = row['senderid'] as String? ?? '';
          final isImage = _isImageContent(content);
          final isAudio = row['type'] == 'audio';
          final ts = _parseTs(row['created_at'] as String?);
          final isRead = row['isread'] == true;
          final isEdited = row['is_edited'] == true;
          final isDeleted = row['is_deleted'] == true;
          final isMine = senderId.toLowerCase() == myId.toLowerCase();
          final audioDuration = row['audio_duration'] as int? ?? 0;

          final msg = Message(
            id: row['id']?.toString() ?? '',
            chatId: chatId,
            senderId: senderId,
            senderName: row['sendername'] as String? ?? '',
            content: isDeleted ? '' : content,
            type: isImage
                ? MessageType.image
                : isAudio
                ? MessageType.audio
                : MessageType.text,
            timestamp: ts,
            isRead: isRead,
            isEdited: isEdited,
            isDeleted: isDeleted,
            replyToId: row['reply_to_id'] as String?,
            replyToContent: row['reply_to_content'] as String?,
            replyToSender: row['reply_to_sender'] as String?,
            audioDuration: isAudio ? audioDuration : null,
          );
          current.messages.add(msg);
          if (!isMine && !isRead && !isDeleted) current.unreadCount++;
        }
        final last = current.messages.last;
        current.lastMessage = last.isDeleted
            ? "Xabar o'chirildi"
            : _lastMsgText(
          last.type == MessageType.image,
          last.type == MessageType.audio,
          last.content,
        );
        current.lastMessageTime = last.timestamp;
      }
    } catch (e) {
      if (kDebugMode) print('🚨 fetchOrCreateChat: $e');
    }
    _sortChats();
    notifyListeners();
    return current;
  }

  // ─── _onIncoming (WebSocket) ──────────────────────────────────────────────
  void _onIncoming(Message msg) {
    if (msg.chatId.isEmpty) return;
    final ci = _chats.indexWhere((c) => c.id == msg.chatId);
    if (ci != -1) {
      if (!_chats[ci].messages.any((m) => m.id == msg.id)) {
        _addMsgAndFormat(_chats[ci], msg);
        if (_activeChatId == msg.chatId) {
          if (msg.senderId != _me?.id) markAsRead(msg.chatId);
        } else if (msg.senderId != _me?.id && !msg.isRead) {
          _chats[ci].unreadCount++;
          notifyListeners();
        }
      }
    } else if (msg.senderId != _me?.id) {
      _chats.insert(
        0,
        Chat(
          id: msg.chatId,
          name: msg.senderName.isNotEmpty ? msg.senderName : 'Foydalanuvchi',
          type: ChatType.personal,
          memberIds: [_me?.id ?? '', msg.senderId],
          messages: [msg],
          lastMessage: _lastMsgText(
            msg.type == MessageType.image,
            msg.type == MessageType.audio,
            msg.content,
          ),
          lastMessageTime: msg.timestamp,
          unreadCount:
          (!msg.isRead && _activeChatId != msg.chatId) ? 1 : 0,
        ),
      );
      _sortChats();
      notifyListeners();
    }
  }

  void _addMsgAndFormat(Chat chat, Message msg) {
    if (!chat.messages.any((m) => m.id == msg.id)) {
      chat.messages.add(msg);
    }
    chat.lastMessage = msg.isDeleted
        ? "Xabar o'chirildi"
        : _lastMsgText(msg.type == MessageType.image,
        msg.type == MessageType.audio, msg.content);
    chat.lastMessageTime = msg.timestamp;
    _sortChats();
    notifyListeners();
  }

  // ─── loadAllUsers ─────────────────────────────────────────────────────────
  Future<void> loadAllUsers() async {
    if (_me == null) return;
    try {
      final data = await sb.Supabase.instance.client
          .from('users')
          .select('id, name, avatarurl, isonline, last_seen')
          .neq('id', _me!.id);

      _allUsers = data.map((r) => User.fromJson(r)).toList();

      for (final r in data) {
        final uid = (r['id'] as String?)?.toLowerCase();
        final ls = r['last_seen'] as String?;
        if (uid != null && ls != null) {
          final utc = DateTime.tryParse(ls)?.toUtc();
          if (utc != null) _lastSeenMap[uid] = utc;
        }
      }

      for (final user in _allUsers) {
        final chatId = normalizeChatId(_me!.id, user.id);
        final ci = _chats.indexWhere((c) => c.id == chatId);
        if (ci != -1) {
          if (_chats[ci].name != user.name ||
              _chats[ci].avatarUrl != user.avatarUrl) {
            _chats[ci] = Chat(
              id: _chats[ci].id,
              name: user.name,
              type: _chats[ci].type,
              memberIds: _chats[ci].memberIds,
              messages: _chats[ci].messages,
              lastMessage: _chats[ci].lastMessage,
              lastMessageTime: _chats[ci].lastMessageTime,
              unreadCount: _chats[ci].unreadCount,
              avatarUrl: user.avatarUrl,
            );
          }
        }
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 loadAllUsers: $e');
    }
  }

  Future<void> _saveUserToDb(String id, String name) async {
    try {
      final sbUser = sb.Supabase.instance.client.auth.currentUser;
      final avatar = sbUser?.userMetadata?['avatar_url'] as String? ??
          sbUser?.userMetadata?['picture'] as String? ??
          '';
      await sb.Supabase.instance.client.from('users').upsert({
        'id': id,
        'name': name,
        'avatarurl': avatar,
        'isonline': true,
        'last_seen': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'id');
    } catch (e) {
      if (kDebugMode) print('🚨 _saveUserToDb: $e');
    }
  }

  void setSearchQuery(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  Future<void> deleteChat(String chatId) async {
    try {
      await sb.Supabase.instance.client
          .from('messages')
          .delete()
          .eq('chatid', chatId);
      _chats.removeWhere((c) => c.id == chatId);
      if (_activeChatId == chatId) _activeChatId = null;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 deleteChat: $e');
    }
  }

  Future<void> deleteUser(String userId) async {
    try {
      await sb.Supabase.instance.client
          .from('users')
          .delete()
          .eq('id', userId);
      _allUsers.removeWhere((u) => u.id == userId);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 deleteUser: $e');
    }
  }

  Future<void> clearChatHistory(
      String chatId, BuildContext context) async {
    try {
      await sb.Supabase.instance.client
          .from('messages')
          .delete()
          .eq('chatid', chatId);
      await _clearHistoryChannel?.sendBroadcastMessage(
        event: 'clear_history',
        payload: {'chat_id': chatId},
      );
      _applyClearHistory(chatId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Chat tarixi o'chirildi"),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (kDebugMode) print('🚨 clearChatHistory: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Xatolik: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ─── logout ───────────────────────────────────────────────────────────────
  // ─── logout ───────────────────────────────────────────────────────────────
  Future<void> logout() async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;

    final uid = _me?.id;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    // DB va presence ni background da tozalash (await qilmaymiz — UI kutmaydi)
    unawaited(_presenceChannel?.untrack().timeout(const Duration(seconds: 2)));

    if (uid != null) {
      unawaited(
        sb.Supabase.instance.client
            .from('users')
            .update({
          'isonline': false,
          'last_seen': DateTime.now().toUtc().toIso8601String(),
        })
            .eq('id', uid)
            .timeout(const Duration(seconds: 3)),
      );
    }

    // Kanallarni yopish
    try {
      _realtimeChannel?.unsubscribe();
      _presenceChannel?.unsubscribe();
      _clearHistoryChannel?.unsubscribe();
    } catch (_) {}
    _realtimeChannel = null;
    _presenceChannel = null;
    _clearHistoryChannel = null;

    // WebSocket
    try {
      await _wsSub?.cancel();
      _wsSub = null;
      (_ws as dynamic).disconnect();
    } catch (_) {}

    // Local state tozalash — notifyListeners KEYIN
    _me = null;
    _activeChatId = null;
    _chats.clear();
    _allUsers.clear();
    _onlineStatuses.clear();
    _lastSeenMap.clear();
    _searchQuery = '';

    _isLoggingOut = false;

    // ✅ notifyListeners oxirida — navigation bilan conflict bo'lmasin
    notifyListeners();

    // Google va Supabase signOut — background da, navigation bloklanmaydi
    unawaited(Future(() async {
      try {
        await Future.wait([
          GoogleSignIn().signOut(),
          GoogleSignIn().disconnect(),
        ]).timeout(const Duration(seconds: 3));
      } catch (_) {}
      try {
        await sb.Supabase.instance.client.auth
            .signOut()
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
    }));
  }
  // ─── deleteAccount ────────────────────────────────────────────────────────
  // ─── deleteAccount ────────────────────────────────────────────────────────
  Future<bool> deleteAccount() async {
    if (_isLoggingOut) return false;
    _isLoggingOut = true;

    final uid = _me?.id;
    if (uid == null) {
      _isLoggingOut = false;
      return false;
    }

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    // Kanallarni yopish
    try {
      await _presenceChannel?.untrack().timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      _realtimeChannel?.unsubscribe();
      _presenceChannel?.unsubscribe();
      _clearHistoryChannel?.unsubscribe();
      _realtimeChannel = null;
      _presenceChannel = null;
      _clearHistoryChannel = null;
    } catch (_) {}

    // WebSocket
    try {
      await _wsSub?.cancel();
      _wsSub = null;
      (_ws as dynamic).disconnect();
    } catch (_) {}

    // DB dan o'chirish (navigation dan OLDIN)
    try {
      await sb.Supabase.instance.client
          .from('messages')
          .delete()
          .or('senderid.eq.$uid,chatid.like.%$uid%')
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      if (kDebugMode) print('🚨 deleteAccount messages: $e');
    }
    try {
      await sb.Supabase.instance.client
          .from('users')
          .delete()
          .eq('id', uid)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      if (kDebugMode) print('🚨 deleteAccount user row: $e');
    }

    // Local state tozalash
    _me = null;
    _activeChatId = null;
    _chats.clear();
    _allUsers.clear();
    _onlineStatuses.clear();
    _lastSeenMap.clear();
    _searchQuery = '';

    _isLoggingOut = false;
    notifyListeners();

    // Google va Supabase signOut — background
    unawaited(Future(() async {
      try {
        await Future.wait([
          GoogleSignIn().signOut(),
          GoogleSignIn().disconnect(),
        ]).timeout(const Duration(seconds: 3));
      } catch (_) {}
      try {
        await sb.Supabase.instance.client.auth
            .signOut()
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
    }));

    return true;
  }
  // ─── dispose ──────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _wsSub?.cancel();
    _realtimeChannel?.unsubscribe();
    _presenceChannel?.unsubscribe();
    _clearHistoryChannel?.unsubscribe();
    super.dispose();
  }

  // ─── Private helpers ──────────────────────────────────────────────────────
  DateTime _parseTs(String? raw) {
    final utc = raw != null
        ? DateTime.tryParse(raw)?.toUtc() ?? DateTime.now().toUtc()
        : DateTime.now().toUtc();
    return _toLocal(utc);
  }

  DateTime _toLocal(DateTime utc) => utc.add(const Duration(hours: 5));

  void _sortChats() {
    _chats.sort(
          (a, b) => (b.lastMessageTime ?? DateTime(0))
          .compareTo(a.lastMessageTime ?? DateTime(0)),
    );
  }

  bool _isImageContent(String c) =>
      c.startsWith('http') &&
          (c.contains('.jpg') ||
              c.contains('.png') ||
              c.contains('chat_images'));

  String _lastMsgText(bool isImage, bool isAudio, String content) {
    if (isImage) return '📷 Rasm';
    if (isAudio) return '🎤 Ovozli xabar';
    return content;
  }

  void _replaceLocalId(String chatId, String localId, String realId) {
    if (realId.isEmpty) return;
    final ci = _chats.indexWhere((c) => c.id == chatId);
    if (ci == -1) return;
    final mi = _chats[ci].messages.indexWhere((m) => m.id == localId);
    if (mi == -1) return;
    _chats[ci].messages[mi] =
        _chats[ci].messages[mi].copyWith(id: realId);
    notifyListeners();
  }

  void _updateLocalContent(String chatId, String localId, String url) {
    final ci = _chats.indexWhere((c) => c.id == chatId);
    if (ci == -1) return;
    final mi = _chats[ci].messages.indexWhere((m) => m.id == localId);
    if (mi == -1) return;
    _chats[ci].messages[mi] =
        _chats[ci].messages[mi].copyWith(content: url);
    notifyListeners();
  }

  void _removeLocal(String chatId, String localId) {
    final ci = _chats.indexWhere((c) => c.id == chatId);
    if (ci == -1) return;
    _chats[ci].messages.removeWhere((m) => m.id == localId);
    notifyListeners();
  }

  void _refreshLastMsg(int ci) {
    final msgs = _chats[ci].messages;
    if (msgs.isEmpty) {
      _chats[ci].lastMessage = null;
      return;
    }
    final visible = msgs.lastWhere(
          (m) => !m.isDeleted,
      orElse: () => msgs.last,
    );
    _chats[ci].lastMessage = visible.isDeleted
        ? "Xabar o'chirildi"
        : _lastMsgText(
      visible.type == MessageType.image,
      visible.type == MessageType.audio,
      visible.content,
    );
  }
}