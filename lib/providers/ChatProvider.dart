import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/services/WebSocketService.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:google_sign_in/google_sign_in.dart';

class ChatProvider extends ChangeNotifier {
  final WebSocketService _ws;
  StreamSubscription? _wsSub;
  sb.RealtimeChannel? _realtimeChannel;
  sb.RealtimeChannel? _presenceChannel;
  sb.RealtimeChannel? _clearHistoryChannel;

  User? _me;
  final List<Chat> _chats = [];
  String _searchQuery = '';
  List<User> _allUsers = [];
  String? _activeChatId;

  // Online status tracking
  final Map<String, bool> _onlineStatuses = {};
  final Map<String, DateTime> _lastSeenMap = {};

  User? get currentUser => _me;

  List<User> get allUsers => List.unmodifiable(_allUsers);

  Map<String, bool> get onlineStatuses => Map.unmodifiable(_onlineStatuses);

  Map<String, DateTime> get lastSeenMap => Map.unmodifiable(_lastSeenMap);

  bool isUserOnline(String userId) => _onlineStatuses[userId] ?? false;

  DateTime? getLastSeen(String userId) => _lastSeenMap[userId];

  List<Chat> get chats {
    if (_searchQuery.isEmpty) return List.unmodifiable(_chats);
    return List.unmodifiable(
      _chats.where(
        (c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase()),
      ),
    );
  }

  List<Chat> get personalChats =>
      List.unmodifiable(_chats.where((c) => c.type == ChatType.personal));

  List<Chat> get groupChats =>
      List.unmodifiable(_chats.where((c) => c.type == ChatType.group));

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
    _me = User(id: id, name: name, isOnline: true);
    _ws.connect(_me!.id);
    _subscribeRealtime();
    _subscribePresence();
    _subscribeClearHistory();
    notifyListeners();
    loadAllUsers();
    _saveUserToDb(id, name);
    loadOldMessages();
  }

  // ─── Presence (online/offline) ────────────────────────────────────────────
  void _subscribePresence() {
    _presenceChannel?.unsubscribe();
    if (_me == null) return;

    _presenceChannel = sb.Supabase.instance.client
        .channel('online_users')
        .onPresenceSync((payload) {
          final state = _presenceChannel?.presenceState() ?? {};
          final onlineIds = <String>{};
          // final state = _presenceChannel?.presenceState() ?? {};

          (state as Map).forEach((key, value) {
            final presences = value as List;

            for (final p in presences) {
              final payload = p.payload as Map<String, dynamic>;
              final userId = payload['user_id']?.toString();

              if (userId != null) {
                onlineIds.add(userId);
              }
            }
          });
          for (final u in _allUsers) {
            _onlineStatuses[u.id] = onlineIds.contains(u.id);
          }
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
          if (userId != null) {
            _onlineStatuses[userId] = false;
            _lastSeenMap[userId] = DateTime.now();
            // Update last_seen in DB
            _updateLastSeen(userId);
            notifyListeners();
          }
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

  // ─── Clear history broadcast channel ─────────────────────────────────────
  void _subscribeClearHistory() {
    _clearHistoryChannel?.unsubscribe();
    _clearHistoryChannel = sb.Supabase.instance.client
        .channel('clear_history_events')
        .onBroadcast(
          event: 'clear_history',
          callback: (payload) {
            final chatId = payload['chat_id'] as String?;
            if (chatId == null) return;
            _applyClearHistory(chatId);
          },
        )
        .subscribe();
  }

  void _applyClearHistory(String chatId) {
    final chatIdx = _chats.indexWhere((c) => c.id == chatId);
    if (chatIdx != -1) {
      _chats[chatIdx].messages.clear();
      _chats[chatIdx].lastMessage = null;
      _chats[chatIdx].lastMessageTime = null;
      _chats[chatIdx].unreadCount = 0;
      notifyListeners();
    }
  }

  void _subscribeRealtime() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = sb.Supabase.instance.client
        .channel('public:messages')
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
        );
    _realtimeChannel?.subscribe();
  }

  void _onRealtimeUpdate(Map<String, dynamic> row) {
    final msgId = row['id']?.toString() ?? '';
    final chatId = row['chatid'] as String? ?? '';
    final isDeleted = row['is_deleted'] == true;
    final isEdited = row['is_edited'] == true;
    final newContent = row['content'] as String? ?? '';
    final isRead = row['isread'] == true;

    final chatIdx = _chats.indexWhere((c) => c.id == chatId);
    if (chatIdx == -1) return;
    final chat = _chats[chatIdx];
    final msgIdx = chat.messages.indexWhere((m) => m.id == msgId);
    if (msgIdx == -1) return;
    final old = chat.messages[msgIdx];

    chat.messages[msgIdx] = old.copyWith(
      content: isDeleted ? '' : newContent,
      isEdited: isEdited,
      isDeleted: isDeleted,
      isRead: isRead,
    );
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

    final rawTs = row['created_at'] as String? ?? row['timestamp'] as String?;
    // Convert to UZB time (UTC+5)
    final utcTime = rawTs != null
        ? DateTime.tryParse(rawTs)?.toUtc() ?? DateTime.now().toUtc()
        : DateTime.now().toUtc();
    final ts = utcTime.add(const Duration(hours: 5));

    final isImage = _isImageContent(content);
    final isAudio = row['type'] == 'audio';

    final msg = Message(
      id: msgId,
      chatId: chatId,
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
    );

    final isMine = senderId == _me!.id;
    final chatIdx = _chats.indexWhere((c) => c.id == chatId);

    if (chatIdx != -1) {
      final chat = _chats[chatIdx];

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
        if (!isMine && _activeChatId != chatId && !isRead) chat.unreadCount++;
      }
      chat.lastMessage = isImage
          ? '📷 Rasm'
          : isAudio
          ? '🎤 Audio'
          : content;
      chat.lastMessageTime = ts;
      if (_activeChatId == chatId && !isMine) {
        chat.unreadCount = 0;
        markAsRead(chatId);
      }
    } else {
      final idList = chatId.split('_');
      final otherId = idList.first == _me!.id ? idList.last : idList.first;
      final other = _allUsers.firstWhere(
        (u) => u.id == otherId,
        orElse: () => User(
          id: otherId,
          name: senderName.isNotEmpty ? senderName : 'Foydalanuvchi',
        ),
      );
      _chats.insert(
        0,
        Chat(
          id: chatId,
          name: other.name,
          type: ChatType.personal,
          memberIds: [_me!.id, otherId],
          messages: [msg],
          lastMessage: isImage
              ? '📷 Rasm'
              : isAudio
              ? '🎤 Audio'
              : content,
          lastMessageTime: ts,
          unreadCount: (!isMine && _activeChatId != chatId && !isRead) ? 1 : 0,
        ),
      );
    }
    _sortChats();
    notifyListeners();
  }

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

  Future<void> sendText(
    String chatId,
    String text,
    String chatName,
    BuildContext context, {
    Message? replyTo,
  }) async {
    if (_me == null || text.trim().isEmpty) return;
    final cleanText = text.trim();
    // Use UZB time (UTC+5)
    final timeNow = DateTime.now().toUtc().add(const Duration(hours: 5));
    final localId = 'local_${timeNow.millisecondsSinceEpoch}';

    final localMsg = Message(
      id: localId,
      chatId: chatId,
      senderId: _me!.id,
      senderName: _me!.name,
      content: cleanText,
      type: MessageType.text,
      timestamp: timeNow,
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

      final realId = rows?['id']?.toString() ?? '';
      if (realId.isNotEmpty) {
        final chatIdx = _chats.indexWhere((c) => c.id == chatId);
        if (chatIdx != -1) {
          final idx = _chats[chatIdx].messages.indexWhere(
            (m) => m.id == localId,
          );
          if (idx != -1) {
            _chats[chatIdx].messages[idx] = _chats[chatIdx].messages[idx]
                .copyWith(id: realId);
            notifyListeners();
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ Full insert failed, fallback: $e');
      try {
        final rows2 = await sb.Supabase.instance.client
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
            })
            .select('id')
            .maybeSingle();

        final realId2 = rows2?['id']?.toString() ?? '';
        if (realId2.isNotEmpty) {
          final chatIdx = _chats.indexWhere((c) => c.id == chatId);
          if (chatIdx != -1) {
            final idx = _chats[chatIdx].messages.indexWhere(
              (m) => m.id == localId,
            );
            if (idx != -1) {
              _chats[chatIdx].messages[idx] = _chats[chatIdx].messages[idx]
                  .copyWith(id: realId2);
              notifyListeners();
            }
          }
        }
      } catch (e2) {
        if (kDebugMode) print('🚨 sendText error: $e2');
        final chatIdx = _chats.indexWhere((c) => c.id == chatId);
        if (chatIdx != -1) {
          _chats[chatIdx].messages.removeWhere((m) => m.id == localId);
          notifyListeners();
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Xabar yuborilmadi: $e2'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> editMessage(
    String chatId,
    String messageId,
    String newContent,
    BuildContext context,
  ) async {
    if (_me == null || newContent.trim().isEmpty) return;
    if (messageId.startsWith('local_')) return;

    final chatIdx = _chats.indexWhere((c) => c.id == chatId);
    if (chatIdx == -1) return;
    final msgIdx = _chats[chatIdx].messages.indexWhere(
      (m) => m.id == messageId,
    );
    if (msgIdx == -1) return;
    final old = _chats[chatIdx].messages[msgIdx];
    if (old.senderId != _me!.id) return;

    _chats[chatIdx].messages[msgIdx] = old.copyWith(
      content: newContent.trim(),
      isEdited: true,
    );
    notifyListeners();

    try {
      await sb.Supabase.instance.client
          .from('messages')
          .update({'content': newContent.trim(), 'is_edited': true})
          .eq('id', messageId);
    } catch (e) {
      if (kDebugMode) print('🚨 editMessage error: $e');
      _chats[chatIdx].messages[msgIdx] = old;
      notifyListeners();
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tahrirlashda xatolik'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> deleteMessage(
    String chatId,
    String messageId,
    BuildContext context,
  ) async {
    if (_me == null) return;
    if (messageId.startsWith('local_')) {
      final chatIdx = _chats.indexWhere((c) => c.id == chatId);
      if (chatIdx != -1) {
        _chats[chatIdx].messages.removeWhere((m) => m.id == messageId);
        notifyListeners();
      }
      return;
    }

    final chatIdx = _chats.indexWhere((c) => c.id == chatId);
    if (chatIdx == -1) return;
    final msgIdx = _chats[chatIdx].messages.indexWhere(
      (m) => m.id == messageId,
    );
    if (msgIdx == -1) return;
    final old = _chats[chatIdx].messages[msgIdx];
    if (old.senderId != _me!.id) return;

    _chats[chatIdx].messages[msgIdx] = old.copyWith(
      isDeleted: true,
      content: '',
    );
    final lastVisible = _chats[chatIdx].messages.lastWhere(
      (m) => !m.isDeleted,
      orElse: () => old,
    );
    _chats[chatIdx].lastMessage = lastVisible.isDeleted
        ? "Xabar o'chirildi"
        : (lastVisible.type == MessageType.image
              ? '📷 Rasm'
              : lastVisible.content);
    notifyListeners();

    try {
      await sb.Supabase.instance.client
          .from('messages')
          .update({'is_deleted': true})
          .eq('id', messageId);
    } catch (e) {
      if (kDebugMode) print('🚨 deleteMessage error: $e');
      _chats[chatIdx].messages[msgIdx] = old;
      notifyListeners();
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("O'chirishda xatolik"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> sendImage(
    String chatId,
    XFile xFile,
    String senderName,
    BuildContext context,
  ) async {
    if (_me == null) return;

    // ✅ 1. Darhol local xabar ko'rsatish
    final timeNow = DateTime.now().toUtc().add(const Duration(hours: 5));
    final localId = 'local_img_${timeNow.millisecondsSinceEpoch}';

    final localMsg = Message(
      id: localId,
      chatId: chatId,
      senderId: _me!.id,
      senderName: senderName,
      content: '__uploading__',
      // placeholder
      type: MessageType.image,
      timestamp: timeNow,
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
      // ✅ 2. Storage ga yuklash
      final path = 'chat_images/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await xFile.readAsBytes();

      await sb.Supabase.instance.client.storage
          .from('chat_bucket')
          .uploadBinary(path, bytes);

      final url = sb.Supabase.instance.client.storage
          .from('chat_bucket')
          .getPublicUrl(path);

      // ✅ 3. Local xabarni real URL bilan yangilash
      final ci = _chats.indexWhere((c) => c.id == chatId);
      if (ci != -1) {
        final mi = _chats[ci].messages.indexWhere((m) => m.id == localId);
        if (mi != -1) {
          _chats[ci].messages[mi] = _chats[ci].messages[mi].copyWith(
            content: url,
          );
          notifyListeners();
        }
      }

      // ✅ 4. DB ga saqlash
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

      // ✅ 5. Real ID bilan almashtirish
      if (result != null) {
        final realId = result['id']?.toString() ?? '';
        if (realId.isNotEmpty) {
          final ci2 = _chats.indexWhere((c) => c.id == chatId);
          if (ci2 != -1) {
            final mi2 = _chats[ci2].messages.indexWhere((m) => m.id == localId);
            if (mi2 != -1) {
              _chats[ci2].messages[mi2] = _chats[ci2].messages[mi2].copyWith(
                id: realId,
              );
              notifyListeners();
            }
          }
        }
      }
    } catch (e) {
      // Xato bo'lsa local xabarni olib tashlash
      final ci = _chats.indexWhere((c) => c.id == chatId);
      if (ci != -1) {
        _chats[ci].messages.removeWhere((m) => m.id == localId);
        notifyListeners();
      }
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rasm yuklanmadi: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      if (kDebugMode) print('🚨 sendImage: $e');
    }
  }

  // 🎤 Audio — optimistic UI: tezda chatda paydo bo'lsin
  Future<void> sendAudio(
    String chatId,
    String audioPath,
    String senderName,
    BuildContext context,
    String chatName,
  ) async {
    if (_me == null || audioPath.isEmpty) return;

    // 1️⃣ Optimistic local message — darhol UI da ko'rinsin
    final timeNow = DateTime.now().toUtc().add(const Duration(hours: 5));
    final localId = 'local_audio_${timeNow.millisecondsSinceEpoch}';
    const placeholderUrl = '__uploading__';

    final localMsg = Message(
      id: localId,
      chatId: chatId,
      senderId: _me!.id,
      senderName: senderName,
      content: placeholderUrl,
      type: MessageType.audio,
      timestamp: timeNow,
      isRead: false,
      isEdited: false,
      isDeleted: false,
    );

    int chatIdx = _chats.indexWhere((c) => c.id == chatId);
    if (chatIdx == -1) {
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
      chatIdx = 0;
    }
    _chats[chatIdx].messages.add(localMsg);
    _chats[chatIdx].lastMessage = '🎤 Audio';
    _chats[chatIdx].lastMessageTime = timeNow;
    _sortChats();
    notifyListeners();

    try {
      // 2️⃣ Storage ga yuklash
      final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final storagePath = 'chat_audio/$fileName';
      final file = File(audioPath);
      final bytes = await file.readAsBytes();

      await sb.Supabase.instance.client.storage
          .from('chat_bucket')
          .uploadBinary(storagePath, bytes);

      final audioUrl = sb.Supabase.instance.client.storage
          .from('chat_bucket')
          .getPublicUrl(storagePath);

      // 3️⃣ Local message ni real URL bilan yangilash
      final ci = _chats.indexWhere((c) => c.id == chatId);
      if (ci != -1) {
        final mi = _chats[ci].messages.indexWhere((m) => m.id == localId);
        if (mi != -1) {
          _chats[ci].messages[mi] = _chats[ci].messages[mi].copyWith(
            content: audioUrl,
          );
          notifyListeners();
        }
      }

      // 4️⃣ DB ga saqlash
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
          })
          .select('id')
          .maybeSingle();

      // 5️⃣ Real ID bilan almashtirish
      if (result != null) {
        final realId = result['id']?.toString() ?? '';
        if (realId.isNotEmpty) {
          final ci2 = _chats.indexWhere((c) => c.id == chatId);
          if (ci2 != -1) {
            final mi2 = _chats[ci2].messages.indexWhere((m) => m.id == localId);
            if (mi2 != -1) {
              _chats[ci2].messages[mi2] = _chats[ci2].messages[mi2].copyWith(
                id: realId,
              );
              notifyListeners();
            }
          }
        }
      }

      // 6️⃣ WebSocket broadcast
      _ws.sendMessage(
        chatId: chatId,
        senderId: _me!.id,
        senderName: senderName,
        content: audioUrl,
        type: MessageType.audio,
      );
    } catch (e) {
      // Yuborilmagan audio ni UI dan olib tashlash
      final ci = _chats.indexWhere((c) => c.id == chatId);
      if (ci != -1) {
        _chats[ci].messages.removeWhere((m) => m.id == localId);
        notifyListeners();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Audio yuborilmadi: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      if (kDebugMode) print('🚨 sendAudio error: $e');
    }
  }

  Future<void> loadOldMessages() async {
    if (_me == null) return;
    try {
      final usersData = await sb.Supabase.instance.client
          .from('users')
          .select('id, name');
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
        final chatId = row['chatid'] as String? ?? '';
        final senderId = row['senderid'] as String? ?? '';
        final content = row['content'] as String? ?? '';
        if (chatId.isEmpty) continue;

        final rawTs =
            row['created_at'] as String? ?? row['timestamp'] as String?;
        // UZB time (UTC+5)
        final utcTime = rawTs != null
            ? DateTime.tryParse(rawTs)?.toUtc() ?? DateTime.now().toUtc()
            : DateTime.now().toUtc();
        final ts = utcTime.add(const Duration(hours: 5));

        final isRead = row['isread'] == true;
        final isEdited = row['is_edited'] == true;
        final isDeleted = row['is_deleted'] == true;
        final isImage = _isImageContent(content);
        final isAudio = row['type'] == 'audio';

        final isMine = senderId == _me!.id;

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
        );

        final idList = chatId.split('_');
        var normalizedId = chatId;
        var otherId = _me!.id;
        if (idList.length >= 2) {
          idList.sort();
          normalizedId = idList.join('_');
          otherId = idList.first == _me!.id ? idList.last : idList.first;
        }
        if (otherId == _me!.id) continue;

        int chatIdx = _chats.indexWhere((c) => c.id == normalizedId);
        if (chatIdx == -1) {
          _chats.add(
            Chat(
              id: normalizedId,
              name:
                  (userNames[otherId] ??
                          (senderId == _me!.id
                              ? 'Foydalanuvchi'
                              : msg.senderName))
                      .isEmpty
                  ? 'Foydalanuvchi'
                  : (userNames[otherId] ?? msg.senderName),
              type: ChatType.personal,
              memberIds: [_me!.id, otherId],
              messages: [],
              unreadCount: 0,
            ),
          );
          chatIdx = _chats.length - 1;
        }

        if (!_chats[chatIdx].messages.any((m) => m.id == msg.id)) {
          _chats[chatIdx].messages.add(msg);
          if (!isMine && !isRead && !isDeleted) _chats[chatIdx].unreadCount++;
        }
        _chats[chatIdx].lastMessage = isDeleted
            ? "Xabar o'chirildi"
            : (isImage
                  ? '📷 Rasm'
                  : isAudio
                  ? '🎤 Audio'
                  : content);
        _chats[chatIdx].lastMessageTime = ts;
      }

      for (var chat in _chats)
        chat.messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _sortChats();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 loadOldMessages: $e');
    }
  }

  Future<Chat> fetchOrCreateChat(User other) async {
    final ids = [_me!.id, other.id]..sort();
    final chatId = '${ids[0]}_${ids[1]}';
    final existingIdx = _chats.indexWhere((c) => c.id == chatId);
    if (existingIdx != -1 && _chats[existingIdx].messages.isNotEmpty)
      return _chats[existingIdx];

    Chat current;
    if (existingIdx != -1) {
      current = _chats[existingIdx];
    } else {
      current = Chat(
        id: chatId,
        name: other.name,
        type: ChatType.personal,
        memberIds: [_me!.id, other.id],
        messages: [],
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
          final rawTs = row['created_at'] as String?;
          final utcTime = rawTs != null
              ? DateTime.tryParse(rawTs)?.toUtc() ?? DateTime.now().toUtc()
              : DateTime.now().toUtc();
          final ts = utcTime.add(const Duration(hours: 5));
          final isRead = row['isread'] == true;
          final isEdited = row['is_edited'] == true;
          final isDeleted = row['is_deleted'] == true;
          final isMine = senderId == _me!.id;

          final msg = Message(
            id: row['id']?.toString() ?? '',
            chatId: chatId,
            senderId: senderId,
            senderName: row['sendername'] as String? ?? '',
            content: isDeleted ? '' : content,
            type: isImage ? MessageType.image : MessageType.text,
            timestamp: ts,
            isRead: isRead,
            isEdited: isEdited,
            isDeleted: isDeleted,
            replyToId: row['reply_to_id'] as String?,
            replyToContent: row['reply_to_content'] as String?,
            replyToSender: row['reply_to_sender'] as String?,
          );
          current.messages.add(msg);
          if (!isMine && !isRead && !isDeleted) current.unreadCount++;
        }
        final last = current.messages.last;
        current.lastMessage = last.isDeleted
            ? "Xabar o'chirildi"
            : (last.type == MessageType.image ? '📷 Rasm' : last.content);
        current.lastMessageTime = last.timestamp;
      }
    } catch (e) {
      if (kDebugMode) print('🚨 fetchOrCreateChat: $e');
    }
    _sortChats();
    notifyListeners();
    return current;
  }

  void _onIncoming(Message msg) {
    if (msg.chatId.isEmpty) return;
    final chatIdx = _chats.indexWhere((c) => c.id == msg.chatId);
    if (chatIdx != -1) {
      final isDup = _chats[chatIdx].messages.any((m) => m.id == msg.id);
      if (!isDup) {
        _addMsgAndFormat(_chats[chatIdx], msg);
        if (_activeChatId == msg.chatId) {
          if (msg.senderId != _me?.id) markAsRead(msg.chatId);
        } else if (msg.senderId != _me?.id && !msg.isRead) {
          _chats[chatIdx].unreadCount++;
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
          lastMessage: msg.type == MessageType.image ? '📷 Rasm' : msg.content,
          lastMessageTime: msg.timestamp,
          unreadCount: (!msg.isRead && _activeChatId != msg.chatId) ? 1 : 0,
        ),
      );
      _sortChats();
      notifyListeners();
    }
  }

  void _addMsgAndFormat(Chat chat, Message msg) {
    if (!chat.messages.any((m) => m.id == msg.id)) chat.messages.add(msg);
    chat.lastMessage = msg.isDeleted
        ? "Xabar o'chirildi"
        : (msg.type == MessageType.image ? '📷 Rasm' : msg.content);
    chat.lastMessageTime = msg.timestamp;
    _sortChats();
    notifyListeners();
  }

  void _sortChats() {
    _chats.sort(
      (a, b) => (b.lastMessageTime ?? DateTime(0)).compareTo(
        a.lastMessageTime ?? DateTime(0),
      ),
    );
  }

  bool _isImageContent(String c) =>
      c.startsWith('http') &&
      (c.contains('.jpg') || c.contains('.png') || c.contains('chat_images'));

  Future<void> loadAllUsers() async {
    if (_me == null) return;
    try {
      final data = await sb.Supabase.instance.client
          .from('users')
          .select('id, name, avatarurl, isonline, last_seen')
          .neq('id', _me!.id);
      _allUsers = data.map((r) => User.fromJson(r)).toList();
      // Load last_seen times
      for (final r in data) {
        final uid = r['id'] as String?;
        final ls = r['last_seen'] as String?;
        if (uid != null && ls != null) {
          final utc = DateTime.tryParse(ls)?.toUtc();
          if (utc != null) {
            _lastSeenMap[uid] = utc.add(const Duration(hours: 5));
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
      final avatar =
          sb
                  .Supabase
                  .instance
                  .client
                  .auth
                  .currentUser
                  ?.userMetadata?['avatar_url']
              as String? ??
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
      await sb.Supabase.instance.client.from('users').delete().eq('id', userId);
      _allUsers.removeWhere((u) => u.id == userId);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('🚨 deleteUser: $e');
    }
  }

  // 🗑️ Chat history o'chirish — barcha foydalanuvchilarda real-time ko'rinsin
  Future<void> clearChatHistory(String chatId, BuildContext context) async {
    try {
      // DB dan o'chirish
      await sb.Supabase.instance.client
          .from('messages')
          .delete()
          .eq('chatid', chatId);

      // Broadcast — boshqa foydalanuvchilarga ham yuborish
      await sb.Supabase.instance.client
          .channel('clear_history_events')
          .sendBroadcastMessage(
            event: 'clear_history',
            payload: {'chat_id': chatId},
          );

      // O'zimizda ham apply qilish
      _applyClearHistory(chatId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Chat tarixi o'chirildi"),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) print('🚨 clearChatHistory error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Xatolik: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> logout() async {
    try {
      if (_me != null) {
        await sb.Supabase.instance.client
            .from('users')
            .update({
              'isonline': false,
              'last_seen': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', _me!.id);
        await _presenceChannel?.untrack();
      }
      _realtimeChannel?.unsubscribe();
      _presenceChannel?.unsubscribe();
      _clearHistoryChannel?.unsubscribe();
      _realtimeChannel = null;
      _presenceChannel = null;
      _clearHistoryChannel = null;
      await sb.Supabase.instance.client.auth.signOut();
      try {
        await GoogleSignIn().signOut();
        await GoogleSignIn().disconnect();
      } catch (_) {}
      await _wsSub?.cancel();
      _wsSub = null;
      try {
        (_ws as dynamic).disconnect();
      } catch (_) {}
      _me = null;
      _activeChatId = null;
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

  @override
  void dispose() {
    _wsSub?.cancel();
    _realtimeChannel?.unsubscribe();
    _presenceChannel?.unsubscribe();
    _clearHistoryChannel?.unsubscribe();
    super.dispose();
  }
}
