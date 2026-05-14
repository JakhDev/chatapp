enum MessageType { text, image }
enum ChatType    { personal, group }

// ─────────────────────────────────────────
class User {
  final String id;
  final String name;
  final String avatarUrl;
  bool isOnline;

  User({
    required this.id,
    required this.name,
    this.avatarUrl = '',
    this.isOnline  = false,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
    id:        j['id']        as String,
    name:      j['name']      as String,
    avatarUrl: j['avatarUrl'] as String? ?? '',
    isOnline:  j['isOnline']  as bool?   ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id':        id,
    'name':      name,
    'avatarUrl': avatarUrl,
    'isOnline':  isOnline,
  };
}

// ─────────────────────────────────────────
class Message {
  final String      id;
  final String      senderId;
  final String      senderName;
  final String      content;
  final MessageType type;
  final DateTime    timestamp;
  bool isRead;

  Message({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    this.type      = MessageType.text,
    required this.timestamp,
    this.isRead    = false,
  });

  factory Message.fromJson(Map<String, dynamic> j) => Message(
    id:         j['id']         as String,
    senderId:   j['senderId']   as String,
    senderName: j['senderName'] as String? ?? '',
    content:    j['content']    as String,
    type:       j['type'] == 'image' ? MessageType.image : MessageType.text,
    timestamp:  DateTime.parse(j['timestamp'] as String),
    isRead:     j['isRead']     as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id':         id,
    'senderId':   senderId,
    'senderName': senderName,
    'content':    content,
    'type':       type == MessageType.image ? 'image' : 'text',
    'timestamp':  timestamp.toIso8601String(),
    'isRead':     isRead,
  };
}

// ─────────────────────────────────────────
class Chat {
  final String        id;
  final String        name;
  final ChatType      type;
  final List<String>  memberIds;
  final List<Message> messages;
  String?   lastMessage;
  DateTime? lastMessageTime;
  int       unreadCount;
  String?   avatarUrl;

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