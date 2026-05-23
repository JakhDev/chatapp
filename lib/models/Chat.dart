enum MessageType { text, image, audio }

enum ChatType { personal, group }

// ── User ──────────────────────────────────────────────────────────────────────
class User {
  final String id;
  final String name;
  final String avatarUrl;
  final String email;
  bool isOnline;

  User({
    required this.id,
    required this.name,
    this.avatarUrl = '',
    this.email = '',
    this.isOnline = false,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? 'Foydalanuvchi',
    avatarUrl: j['avatarurl'] as String? ?? j['avatarUrl'] as String? ?? '',
    email: j['email'] as String? ?? '',
    isOnline: j['isonline'] as bool? ?? j['isOnline'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatarurl': avatarUrl,
    'email': email,
    'isonline': isOnline,
  };
}

// ── Message ───────────────────────────────────────────────────────────────────
class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final bool isRead;
  final bool isEdited;
  final bool isDeleted;
  final String? replyToId;
  final String? replyToContent;
  final String? replyToSender;
  final int? audioDuration; // ovozli xabar davomiyligi (soniyalarda)

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.content,
    this.type = MessageType.text,
    DateTime? timestamp,
    this.isRead = false,
    this.isEdited = false,
    this.isDeleted = false,
    this.replyToId,
    this.replyToContent,
    this.replyToSender,
    this.audioDuration,
  }) : timestamp = timestamp ?? DateTime.now();

  Message copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? senderName,
    String? content,
    MessageType? type,
    DateTime? timestamp,
    bool? isRead,
    bool? isEdited,
    bool? isDeleted,
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
    int? audioDuration,
  }) => Message(
    id: id ?? this.id,
    chatId: chatId ?? this.chatId,
    senderId: senderId ?? this.senderId,
    senderName: senderName ?? this.senderName,
    content: content ?? this.content,
    type: type ?? this.type,
    timestamp: timestamp ?? this.timestamp,
    isRead: isRead ?? this.isRead,
    isEdited: isEdited ?? this.isEdited,
    isDeleted: isDeleted ?? this.isDeleted,
    replyToId: replyToId ?? this.replyToId,
    replyToContent: replyToContent ?? this.replyToContent,
    replyToSender: replyToSender ?? this.replyToSender,
    audioDuration: audioDuration ?? this.audioDuration,
  );

  factory Message.fromJson(Map<String, dynamic> j) {
    final rawTs = j['created_at'] as String? ?? j['timestamp'] as String?;
    final ts = rawTs != null
        ? DateTime.tryParse(rawTs) ?? DateTime.now()
        : DateTime.now();

    return Message(
      id: j['id']?.toString() ?? '',
      chatId: (j['chatid'] ?? j['chatId']) as String? ?? '',
      senderId: (j['senderid'] ?? j['senderId']) as String? ?? '',
      senderName: (j['sendername'] ?? j['senderName']) as String? ?? '',
      content: j['content'] as String? ?? '',
      type: j['type'] == 'image'
          ? MessageType.image
          : j['type'] == 'audio'
          ? MessageType.audio
          : MessageType.text,
      timestamp: ts,
      isRead: (j['isread'] ?? j['is_read'] ?? j['isRead']) as bool? ?? false,
      isEdited:
      (j['isedited'] ?? j['is_edited'] ?? j['isEdited']) as bool? ?? false,
      isDeleted:
      (j['isdeleted'] ?? j['is_deleted'] ?? j['isDeleted']) as bool? ??
          false,
      replyToId: j['reply_to_id'] as String?,
      replyToContent: j['reply_to_content'] as String?,
      replyToSender: j['reply_to_sender'] as String?,
      audioDuration: j['audio_duration'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'chatid': chatId,
    'senderid': senderId,
    'sendername': senderName,
    'content': content,
    'type': type == MessageType.image
        ? 'image'
        : type == MessageType.audio
        ? 'audio'
        : 'text',
    'isread': isRead,
    'is_edited': isEdited,
    'is_deleted': isDeleted,
    'reply_to_id': replyToId,
    'reply_to_content': replyToContent,
    'reply_to_sender': replyToSender,
    if (audioDuration != null) 'audio_duration': audioDuration,
  };
}

// ── Chat ──────────────────────────────────────────────────────────────────────
class Chat {
  final String id;
  final String name;
  final ChatType type;
  final List<String> memberIds;
  final List<Message> messages;
  String? lastMessage;
  DateTime? lastMessageTime;
  int unreadCount;
  String? avatarUrl;

  Chat({
    required this.id,
    required this.name,
    required this.type,
    required this.memberIds,
    List<Message>? messages,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.avatarUrl,
  }) : messages = messages ?? [];
}