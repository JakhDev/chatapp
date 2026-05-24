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

/// UUID format: 8-4-4-4-12 = 36 belgi
/// chatId format: "<uuid1>_<uuid2>"  (faqat bitta _ separator, 73 belgi)
/// Bu funksiya chatId dan part1 va part2 ni xavfsiz ajratadi.
({String part1, String part2})? _splitChatId(String chatId) {
  // UUID = 36 belgi, separator = '_', jami = 73
  if (chatId.length == 73 && chatId[36] == '_') {
    return (part1: chatId.substring(0, 36), part2: chatId.substring(37));
  }
  // Fallback: birinchi '_' bo'yicha (guruh yoki boshqa format uchun)
  final idx = chatId.indexOf('_');
  if (idx == -1) return null;
  final p1 = chatId.substring(0, idx);
  final p2 = chatId.substring(idx + 1);
  if (p1.isEmpty || p2.isEmpty) return null;
  return (part1: p1, part2: p2);
}

/// Normalizatsiya: har doim kichikroq UUID oldin → bir xil chatId
String normalizeChatId(String id1, String id2) {
  final ids = [id1, id2]..sort();
  return '${ids[0]}_${ids[1]}';
}

/// chatId dan "men"ga tegishli bo'lmagan otherId ni qaytaradi
String? otherIdFromChatId(String chatId, String myId) {
  final parts = _splitChatId(chatId);
  if (parts == null) return null;
  if (parts.part1 == myId) return parts.part2;
  if (parts.part2 == myId) return parts.part1;
  return null; // bu foydalanuvchining chati emas
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

  final Map<String, bool>     _onlineStatuses = {};
  final Map<String, DateTime> _lastSeenMap    = {};

  // ─── Public getters ───────────────────────────────────────────────────────

  User? get currentUser => _me;

  Map<String, bool>     get onlineStatuses => Map.unmodifiable(_onlineStatuses);
  Map<String, DateTime> get lastSeenMap    => Map.unmodifiable(_lastSeenMap);

  bool      isUserOnline(String userId) => _onlineStatuses[userId] ?? false;
  DateTime? getLastSeen(String userId)  => _lastSeenMap[userId];

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
      final name =
          sbUser.userMetadata?['full_name'] as String? ??
              sbUser.userMetadata?['name'] as String? ??
              sbUser.email ??
              'User';
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
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _updateOwnLastSeen();
    });
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
          final uid = (p.payload as Map<String, dynamic>)['user_id']?.toString();
          if (uid != null) onlineIds.add(uid);
        }
      });
      for (final u in _allUsers) {
        _onlineStatuses[u.id] = onlineIds.contains(u.id);
      }
      // O'zimizni online deb belgilash (presence sync da o'zimiz ham bor)
      if (_me != null) _onlineStatuses[_me!.id] = true;
      notifyListeners();
    })
        .onPresenceJoin((payload) {
      final userId = payload.newPresences.isNotEmpty
          ? payload.newPresences.first.payload['user_id'] as String?
          : null;
      if (userId != null) {
        _onlineStatuses[userId] = true;
        notifyListeners();
      }
    })
        .onPresenceLeave((payload) {
      final userId = payload.leftPresences.isNotEmpty
          ? payload.leftPresences.first.payload['user_id'] as String?
          : null;
      if (userId == null || userId == _me?.id) return; // o'zimiz emas
      _onlineStatuses[userId] = false;
      // FIX: UTC saqla, UI da +5 qo'shiladi — ikki marta qo'shilmaydi
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

  // ─── Realtime (Supabase) ──────────────────────────────────────────────────
  void _subscribeRealtime() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = sb.Supabase.instance.client
        .channel('public:messages')
        .onPostgresChanges(
      event   : sb.PostgresChangeEvent.insert,
      schema  : 'public',
      table   : 'messages',
      callback: (p) => _onRealtimeMessage(p.newRecord),
    )
        .onPostgresChanges(
      event   : sb.PostgresChangeEvent.update,
      schema  : 'public',
      table   : 'messages',
      callback: (p) => _onRealtimeUpdate(p.newRecord),
    );
    _realtimeChannel?.subscribe();
  }

  void _onRealtimeUpdate(Map<String, dynamic> row) {
    final msgId     = row['id']?.toString() ?? '';
    final chatId    = row['chatid'] as String? ?? '';
    final isDeleted = row['is_deleted'] == true;
    final isEdited  = row['is_edited']  == true;
    final newContent= row['content']    as String? ?? '';
    final isRead    = row['isread']     == true;

    final ci = _chats.indexWhere((c) => c.id == chatId);
    if (ci == -1) return;
    final mi = _chats[ci].messages.indexWhere((m) => m.id == msgId);
    if (mi == -1) return;
    final old = _chats[ci].messages[mi];

    _chats[ci].messages[mi] = old.copyWith(
      content  : isDeleted ? '' : newContent,
      isEdited : isEdited,
      isDeleted: isDeleted,
      isRead   : isRead,
    );
    notifyListeners();
  }

  void _onRealtimeMessage(Map<String, dynamic> row) {
    if (_me == null) return;

    final chatId     = row['chatid']     as String? ?? '';
    final msgId      = row['id']?.toString() ?? '';
    final senderId   = row['senderid']   as String? ?? '';
    final senderName = row['sendername'] as String? ?? '';
    final content    = row['content']    as String? ?? '';
    final isRead     = row['isread']     == true;
    if (chatId.isEmpty || content.isEmpty) return;

    // FIX: UTC dan o'qib, UI da +5 qo'shiladi (ikki marta emas)
    final rawTs  = row['created_at'] as String? ?? row['timestamp'] as String?;
    final ts     = _parseTs(rawTs);

    final isImage       = _isImageContent(content);
    final isAudio       = row['type'] == 'audio';
    final audioDuration = row['audio_duration'] as int? ?? 0;

    final msg = Message(
      id             : msgId,
      chatId         : chatId,
      senderId       : senderId,
      senderName     : senderName,
      content        : content,
      type           : isImage ? MessageType.image : isAudio ? MessageType.audio : MessageType.text,
      timestamp      : ts,
      isRead         : isRead,
      isEdited       : false,
      isDeleted      : false,
      replyToId      : row['reply_to_id']      as String?,
      replyToContent : row['reply_to_content'] as String?,
      replyToSender  : row['reply_to_sender']  as String?,
      audioDuration  : isAudio ? audioDuration : null,
    );

    final isMine = senderId == _me!.id;
    final ci     = _chats.indexWhere((c) => c.id == chatId);

    if (ci != -1) {
      final chat       = _chats[ci];
      final pendingIdx = chat.messages.indexWhere(
            (m) =>
        m.id == msgId ||
            (m.id.startsWith('local_') && m.content == content && m.senderId == senderId),
      );

      if (pendingIdx != -1) {
        chat.messages[pendingIdx] = msg;
      } else if (!chat.messages.any((m) => m.id == msgId)) {
        chat.messages.add(msg);
        if (!isMine && _activeChatId != chatId && !isRead) chat.unreadCount++;
      }

      chat.lastMessage     = _lastMsgText(isImage, isAudio, content);
      chat.lastMessageTime = ts;

      if (_activeChatId == chatId && !isMine) {
        chat.unreadCount = 0;
        markAsRead(chatId);
      }
    } else {
      // Yangi chat — otherId ni to'g'ri aniqla
      final otherId = otherIdFromChatId(chatId, _me!.id) ?? senderId;
      final other   = _allUsers.firstWhere(
            (u) => u.id == otherId,
        orElse: () => User(
          id  : otherId,
          name: senderName.isNotEmpty ? senderName : 'Foydalanuvchi',
        ),
      );

      // Normalizatsiya qilingan chatId bilan insert
      final normalId = normalizeChatId(_me!.id, otherId);
      _chats.insert(
        0,
        Chat(
          id              : normalId,
          name            : other.name,
          type            : ChatType.personal,
          memberIds       : [_me!.id, otherId],
          messages        : [msg],
          lastMessage     : _lastMsgText(isImage, isAudio, content),
          lastMessageTime : ts,
          unreadCount     : (!isMine && _activeChatId != normalId && !isRead) ? 1 : 0,
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
    final timeNow   = DateTime.now().toUtc();
    final localId   = 'local_${timeNow.millisecondsSinceEpoch}';

    final localMsg = Message(
      id             : localId,
      chatId         : chatId,
      senderId       : _me!.id,
      senderName     : _me!.name,
      content        : cleanText,
      type           : MessageType.text,
      timestamp      : _toLocal(timeNow),
      isRead         : false,
      isEdited       : false,
      isDeleted      : false,
      replyToId      : replyTo?.id,
      replyToContent : replyTo?.content,
      replyToSender  : replyTo?.senderName,
    );

    int i = _chats.indexWhere((c) => c.id == chatId);
    if (i == -1) {
      _chats.insert(0, Chat(
        id       : chatId,
        name     : chatName,
        type     : ChatType.personal,
        memberIds: [_me!.id],
        messages : [],
      ));
      i = 0;
    }
    _addMsgAndFormat(_chats[i], localMsg);
    _ws.sendMessage(
      chatId    : chatId,
      senderId  : _me!.id,
      senderName: _me!.name,
      content   : cleanText,
    );

    try {
      final rows = await sb.Supabase.instance.client.from('messages').insert({
        'chatid'          : chatId,
        'senderid'        : _me!.id,
        'sendername'      : _me!.name,
        'content'         : cleanText,
        'type'            : 'text',
        'isread'          : false,
        'is_edited'       : false,
        'is_deleted'      : false,
        if (replyTo != null) 'reply_to_id'     : replyTo.id,
        if (replyTo != null) 'reply_to_content': replyTo.content,
        if (replyTo != null) 'reply_to_sender' : replyTo.senderName,
      }).select('id').maybeSingle();

      _replaceLocalId(chatId, localId, rows?['id']?.toString() ?? '');
    } catch (e) {
      if (kDebugMode) print('⚠️ sendText error: $e');
      _removeLocal(chatId, localId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content        : Text('Xabar yuborilmadi: $e'),
          backgroundColor: Colors.red,
          behavior       : SnackBarBehavior.floating,
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
    final mi = _chats[ci].messages.indexWhere((m) => m.id == messageId);
    if (mi == -1) return;
    final old = _chats[ci].messages[mi];
    if (old.senderId != _me!.id) return;

    _chats[ci].messages[mi] = old.copyWith(
      content : newContent.trim(),
      isEdited: true,
    );
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
          content        : Text('Tahrirlashda xatolik'),
          backgroundColor: Colors.red,
          behavior       : SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ─── deleteMessage ────────────────────────────────────────────────────────
  Future<void> deleteMessage(
      String chatId,
      String messageId,
      BuildContext context,
      ) async {
    if (_me == null) return;
    if (messageId.startsWith('local_')) {
      _removeLocal(chatId, messageId);
      return;
    }

    final ci = _chats.indexWhere((c) => c.id == chatId);
    if (ci == -1) return;
    final mi = _chats[ci].messages.indexWhere((m) => m.id == messageId);
    if (mi == -1) return;
    final old = _chats[ci].messages[mi];
    if (old.senderId != _me!.id) return;

    _chats[ci].messages[mi] = old.copyWith(isDeleted: true, content: '');
    _refreshLastMsg(ci);
    notifyListeners();

    try {
      await sb.Supabase.instance.client
          .from('messages')
          .update({'is_deleted': true})
          .eq('id', messageId);
    } catch (e) {
      if (kDebugMode) print('🚨 deleteMessage: $e');
      _chats[ci].messages[mi] = old;
      notifyListeners();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content        : Text("O'chirishda xatolik"),
          backgroundColor: Colors.red,
          behavior       : SnackBarBehavior.floating,
        ));
      }
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
      id        : localId,
      chatId    : chatId,
      senderId  : _me!.id,
      senderName: senderName,
      content   : '__uploading__',
      type      : MessageType.image,
      timestamp : _toLocal(timeNow),
      isRead    : false,
      isEdited  : false,
      isDeleted : false,
    );

    int i = _chats.indexWhere((c) => c.id == chatId);
    if (i == -1) {
      _chats.insert(0, Chat(
        id       : chatId,
        name     : senderName,
        type     : ChatType.personal,
        memberIds: [_me!.id],
      ));
      i = 0;
    }
    _addMsgAndFormat(_chats[i], localMsg);

    try {
      final path  = 'chat_images/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await xFile.readAsBytes();
      await sb.Supabase.instance.client.storage.from('chat_bucket').uploadBinary(path, bytes);
      final url   = sb.Supabase.instance.client.storage.from('chat_bucket').getPublicUrl(path);

      _updateLocalContent(chatId, localId, url);

      final result = await sb.Supabase.instance.client.from('messages').insert({
        'chatid'    : chatId,
        'senderid'  : _me!.id,
        'sendername': senderName,
        'content'   : url,
        'type'      : 'image',
        'isread'    : false,
        'is_edited' : false,
        'is_deleted': false,
      }).select('id').maybeSingle();

      _replaceLocalId(chatId, localId, result?['id']?.toString() ?? '');
    } catch (e) {
      _removeLocal(chatId, localId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content : Text('Rasm yuklanmadi: $e'),
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
      id           : localId,
      chatId       : chatId,
      senderId     : _me!.id,
      senderName   : senderName,
      content      : '__uploading__',
      type         : MessageType.audio,
      timestamp    : _toLocal(timeNow),
      isRead       : false,
      isEdited     : false,
      isDeleted    : false,
      audioDuration: audioDuration,
    );

    int ci = _chats.indexWhere((c) => c.id == chatId);
    if (ci == -1) {
      _chats.insert(0, Chat(
        id       : chatId,
        name     : chatName,
        type     : ChatType.personal,
        memberIds: [_me!.id],
        messages : [],
      ));
      ci = 0;
    }
    _chats[ci].messages.add(localMsg);
    _chats[ci].lastMessage     = '🎤 Ovozli xabar';
    _chats[ci].lastMessageTime = _toLocal(timeNow);
    _sortChats();
    notifyListeners();

    try {
      final fileName   = 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final storagePath= 'chat_audio/$fileName';
      final bytes      = await File(audioPath).readAsBytes();
      await sb.Supabase.instance.client.storage.from('chat_bucket').uploadBinary(storagePath, bytes);
      final audioUrl   = sb.Supabase.instance.client.storage.from('chat_bucket').getPublicUrl(storagePath);

      _updateLocalContent(chatId, localId, audioUrl);

      final result = await sb.Supabase.instance.client.from('messages').insert({
        'chatid'        : chatId,
        'senderid'      : _me!.id,
        'sendername'    : senderName,
        'content'       : audioUrl,
        'type'          : 'audio',
        'isread'        : false,
        'is_edited'     : false,
        'is_deleted'    : false,
        'audio_duration': audioDuration,
      }).select('id').maybeSingle();

      _replaceLocalId(chatId, localId, result?['id']?.toString() ?? '');

      _ws.sendMessage(
        chatId    : chatId,
        senderId  : _me!.id,
        senderName: senderName,
        content   : audioUrl,
        type      : MessageType.audio,
      );
    } catch (e) {
      _removeLocal(chatId, localId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content : Text('Ovozli xabar yuborilmadi: $e'),
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
      final usersData = await sb.Supabase.instance.client.from('users').select('id, name');
      final userNames = {
        for (var u in usersData)
          u['id'] as String: u['name'] as String? ?? 'Foydalanuvchi',
      };

      final data = await sb.Supabase.instance.client
          .from('messages')
          .select()
          .order('created_at', ascending: true);

      _chats.clear();

      for (final row in data) {
        final chatId   = row['chatid']   as String? ?? '';
        final senderId = row['senderid'] as String? ?? '';
        final content  = row['content']  as String? ?? '';
        if (chatId.isEmpty) continue;

        // FIX: otherId ni UUID-safe aniqla
        final otherId = otherIdFromChatId(chatId, _me!.id);
        if (otherId == null || otherId == _me!.id) continue;

        // Normalizatsiya
        final normalId  = normalizeChatId(_me!.id, otherId);
        final ts        = _parseTs(row['created_at'] as String?);
        final isRead    = row['isread']     == true;
        final isEdited  = row['is_edited']  == true;
        final isDeleted = row['is_deleted'] == true;
        final isImage   = _isImageContent(content);
        final isAudio   = row['type'] == 'audio';
        final isMine    = senderId == _me!.id;
        final audioDuration = row['audio_duration'] as int? ?? 0;

        final msg = Message(
          id             : row['id']?.toString() ?? '',
          chatId         : normalId,
          senderId       : senderId,
          senderName     : row['sendername'] as String? ?? '',
          content        : isDeleted ? '' : content,
          type           : isImage ? MessageType.image : isAudio ? MessageType.audio : MessageType.text,
          timestamp      : ts,
          isRead         : isRead,
          isEdited       : isEdited,
          isDeleted      : isDeleted,
          replyToId      : row['reply_to_id']      as String?,
          replyToContent : row['reply_to_content'] as String?,
          replyToSender  : row['reply_to_sender']  as String?,
          audioDuration  : isAudio ? audioDuration : null,
        );

        int ci = _chats.indexWhere((c) => c.id == normalId);
        if (ci == -1) {
          final otherName = (userNames[otherId] ?? '').isNotEmpty
              ? userNames[otherId]!
              : (msg.senderName.isNotEmpty ? msg.senderName : 'Foydalanuvchi');
          _chats.add(Chat(
            id       : normalId,
            name     : otherName,
            type     : ChatType.personal,
            memberIds: [_me!.id, otherId],
            messages : [],
            unreadCount: 0,
          ));
          ci = _chats.length - 1;
        }

        if (!_chats[ci].messages.any((m) => m.id == msg.id)) {
          _chats[ci].messages.add(msg);
          if (!isMine && !isRead && !isDeleted) _chats[ci].unreadCount++;
        }
        _chats[ci].lastMessage     = isDeleted ? "Xabar o'chirildi" : _lastMsgText(isImage, isAudio, content);
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

  // ─── fetchOrCreateChat ────────────────────────────────────────────────────
  Future<Chat> fetchOrCreateChat(User other) async {
    final chatId    = normalizeChatId(_me!.id, other.id);
    final existIdx  = _chats.indexWhere((c) => c.id == chatId);
    if (existIdx != -1 && _chats[existIdx].messages.isNotEmpty) {
      return _chats[existIdx];
    }

    Chat current;
    if (existIdx != -1) {
      current = _chats[existIdx];
    } else {
      current = Chat(
        id       : chatId,
        name     : other.name,
        type     : ChatType.personal,
        memberIds: [_me!.id, other.id],
        messages : [],
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
          final content  = row['content']   as String? ?? '';
          final senderId = row['senderid']  as String? ?? '';
          final isImage  = _isImageContent(content);
          final isAudio  = row['type'] == 'audio';
          final ts       = _parseTs(row['created_at'] as String?);
          final isRead   = row['isread']     == true;
          final isEdited = row['is_edited']  == true;
          final isDeleted= row['is_deleted'] == true;
          final isMine   = senderId == _me!.id;
          final audioDuration = row['audio_duration'] as int? ?? 0;

          final msg = Message(
            id             : row['id']?.toString() ?? '',
            chatId         : chatId,
            senderId       : senderId,
            senderName     : row['sendername'] as String? ?? '',
            content        : isDeleted ? '' : content,
            type           : isImage ? MessageType.image : isAudio ? MessageType.audio : MessageType.text,
            timestamp      : ts,
            isRead         : isRead,
            isEdited       : isEdited,
            isDeleted      : isDeleted,
            replyToId      : row['reply_to_id']      as String?,
            replyToContent : row['reply_to_content'] as String?,
            replyToSender  : row['reply_to_sender']  as String?,
            audioDuration  : isAudio ? audioDuration : null,
          );
          current.messages.add(msg);
          if (!isMine && !isRead && !isDeleted) current.unreadCount++;
        }
        final last = current.messages.last;
        current.lastMessage     = last.isDeleted ? "Xabar o'chirildi" : _lastMsgText(
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
      _chats.insert(0, Chat(
        id             : msg.chatId,
        name           : msg.senderName.isNotEmpty ? msg.senderName : 'Foydalanuvchi',
        type           : ChatType.personal,
        memberIds      : [_me?.id ?? '', msg.senderId],
        messages       : [msg],
        lastMessage    : _lastMsgText(
          msg.type == MessageType.image,
          msg.type == MessageType.audio,
          msg.content,
        ),
        lastMessageTime: msg.timestamp,
        unreadCount    : (!msg.isRead && _activeChatId != msg.chatId) ? 1 : 0,
      ));
      _sortChats();
      notifyListeners();
    }
  }

  void _addMsgAndFormat(Chat chat, Message msg) {
    if (!chat.messages.any((m) => m.id == msg.id)) chat.messages.add(msg);
    chat.lastMessage = msg.isDeleted
        ? "Xabar o'chirildi"
        : _lastMsgText(msg.type == MessageType.image, msg.type == MessageType.audio, msg.content);
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
        final uid = r['id']        as String?;
        final ls  = r['last_seen'] as String?;
        if (uid != null && ls != null) {
          // FIX: DB dan UTC saqlanadi, _toLocal() bilan local qilinadi
          final utc = DateTime.tryParse(ls)?.toUtc();
          if (utc != null) _lastSeenMap[uid] = utc;
        }
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 loadAllUsers: $e');
    }
  }

  Future<void> _saveUserToDb(String id, String name) async {
    try {
      final avatar = sb.Supabase.instance.client.auth.currentUser
          ?.userMetadata?['avatar_url'] as String? ?? '';
      await sb.Supabase.instance.client.from('users').upsert({
        'id'        : id,
        'name'      : name,
        'avatarurl' : avatar,
        'isonline'  : true,
        'last_seen' : DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'id');
    } catch (e) {
      if (kDebugMode) print('🚨 _saveUserToDb: $e');
    }
  }

  void setSearchQuery(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  // ─── deleteChat ───────────────────────────────────────────────────────────
  Future<void> deleteChat(String chatId) async {
    try {
      await sb.Supabase.instance.client.from('messages').delete().eq('chatid', chatId);
      _chats.removeWhere((c) => c.id == chatId);
      if (_activeChatId == chatId) _activeChatId = null;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 deleteChat: $e');
    }
  }

  Future<void> deleteUser(String userId) async {
    try {
      await sb.Supabase.instance.client.from('users').delete().eq('id', userId);
      _allUsers.removeWhere((u) => u.id == userId);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 deleteUser: $e');
    }
  }

  // ─── clearChatHistory ─────────────────────────────────────────────────────
  Future<void> clearChatHistory(String chatId, BuildContext context) async {
    try {
      await sb.Supabase.instance.client.from('messages').delete().eq('chatid', chatId);
      await _clearHistoryChannel?.sendBroadcastMessage(
        event  : 'clear_history',
        payload: {'chat_id': chatId},
      );
      _applyClearHistory(chatId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content : Text("Chat tarixi o'chirildi"),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (kDebugMode) print('🚨 clearChatHistory: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content : Text('Xatolik: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ─── logout ───────────────────────────────────────────────────────────────
  Future<void> logout() async {
    try {
      if (_me != null) {
        await sb.Supabase.instance.client.from('users').update({
          'isonline' : false,
          'last_seen': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', _me!.id);
        await _presenceChannel?.untrack();
      }
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;

      _realtimeChannel?.unsubscribe();
      _presenceChannel?.unsubscribe();
      _clearHistoryChannel?.unsubscribe();
      _realtimeChannel     = null;
      _presenceChannel     = null;
      _clearHistoryChannel = null;

      await sb.Supabase.instance.client.auth.signOut();
      try {
        await GoogleSignIn().signOut();
        await GoogleSignIn().disconnect();
      } catch (_) {}

      await _wsSub?.cancel();
      _wsSub = null;
      try { (_ws as dynamic).disconnect(); } catch (_) {}

      _me            = null;
      _activeChatId  = null;
      _chats.clear();
      _allUsers.clear();
      _onlineStatuses.clear();
      _lastSeenMap.clear();
      _searchQuery = '';
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 logout: $e');
    }
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

  /// DB dan kelgan UTC string → local DateTime (UTC+5)
  DateTime _parseTs(String? raw) {
    final utc = raw != null
        ? DateTime.tryParse(raw)?.toUtc() ?? DateTime.now().toUtc()
        : DateTime.now().toUtc();
    return _toLocal(utc);
  }

  /// UTC → UTC+5
  DateTime _toLocal(DateTime utc) => utc.add(const Duration(hours: 5));

  void _sortChats() {
    _chats.sort(
          (a, b) => (b.lastMessageTime ?? DateTime(0))
          .compareTo(a.lastMessageTime ?? DateTime(0)),
    );
  }

  bool _isImageContent(String c) =>
      c.startsWith('http') &&
          (c.contains('.jpg') || c.contains('.png') || c.contains('chat_images'));

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
    _chats[ci].messages[mi] = _chats[ci].messages[mi].copyWith(id: realId);
    notifyListeners();
  }

  void _updateLocalContent(String chatId, String localId, String url) {
    final ci = _chats.indexWhere((c) => c.id == chatId);
    if (ci == -1) return;
    final mi = _chats[ci].messages.indexWhere((m) => m.id == localId);
    if (mi == -1) return;
    _chats[ci].messages[mi] = _chats[ci].messages[mi].copyWith(content: url);
    notifyListeners();
  }

  void _removeLocal(String chatId, String localId) {
    final ci = _chats.indexWhere((c) => c.id == chatId);
    if (ci == -1) return;
    _chats[ci].messages.removeWhere((m) => m.id == localId);
    notifyListeners();
  }

  void _refreshLastMsg(int ci) {
    final visible = _chats[ci].messages.lastWhere(
          (m) => !m.isDeleted,
      orElse: () => _chats[ci].messages.last,
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