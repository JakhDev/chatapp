import 'dart:convert';

enum ChatType { personal, group }

enum MessageType { text, image, audio }

class Chat {
  String id;
  String name;
  ChatType type;
  List<String> memberIds;
  List<Message> messages;
  String? lastMessage;
  DateTime? lastMessageTime;
  int unreadCount;
  String? avatarUrl; // FIXED: Avatar URL qo'shildi

  Chat({
    required this.id,
    required this.name,
    required this.type,
    required this.memberIds,
    this.messages = const [],
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.avatarUrl, // FIXED: Constructor parametriga qo'shildi
  });

  // Getter: last message sender id
  String? get lastMessageSenderId {
    if (messages.isEmpty) return null;
    return messages.last.senderId;
  }

  // Getter: last message is read
  bool? get lastMessageIsRead {
    if (messages.isEmpty) return null;
    return messages.last.isRead;
  }

  Chat copyWith({
    String? id,
    String? name,
    ChatType? type,
    List<String>? memberIds,
    List<Message>? messages,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    String? avatarUrl, // FIXED: copyWith'ga qo'shildi
  }) {
    return Chat(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      memberIds: memberIds ?? this.memberIds,
      messages: messages ?? this.messages,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      avatarUrl: avatarUrl ?? this.avatarUrl, // FIXED
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.toString().split('.').last,
      'memberIds': memberIds,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime?.toIso8601String(),
      'unreadCount': unreadCount,
      'avatarUrl': avatarUrl, // FIXED
    };
  }

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] == 'group' ? ChatType.group : ChatType.personal,
      memberIds: List<String>.from(json['memberIds'] ?? []),
      lastMessage: json['lastMessage'],
      lastMessageTime: json['lastMessageTime'] != null
          ? DateTime.parse(json['lastMessageTime'])
          : null,
      unreadCount: json['unreadCount'] ?? 0,
      avatarUrl: json['avatarUrl'], // FIXED
    );
  }
}

class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  String content;
  final MessageType type;
  final DateTime timestamp;
  bool isRead;
  bool isEdited;
  bool isDeleted;
  final String? replyToId;
  final String? replyToContent;
  final String? replyToSender;
  final int? audioDuration;

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    this.isEdited = false,
    this.isDeleted = false,
    this.replyToId,
    this.replyToContent,
    this.replyToSender,
    this.audioDuration,
  });

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
  }) {
    return Message(
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
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chatId': chatId,
      'senderId': senderId,
      'senderName': senderName,
      'content': content,
      'type': type.toString().split('.').last,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
      'isEdited': isEdited,
      'isDeleted': isDeleted,
      'replyToId': replyToId,
      'replyToContent': replyToContent,
      'replyToSender': replyToSender,
      'audioDuration': audioDuration,
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? '',
      chatId: json['chatId'] ?? '',
      senderId: json['senderId'] ?? '',
      senderName: json['senderName'] ?? '',
      content: json['content'] ?? '',
      type: json['type'] == 'image'
          ? MessageType.image
          : json['type'] == 'audio'
          ? MessageType.audio
          : MessageType.text,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      isRead: json['isRead'] ?? false,
      isEdited: json['isEdited'] ?? false,
      isDeleted: json['isDeleted'] ?? false,
      replyToId: json['replyToId'],
      replyToContent: json['replyToContent'],
      replyToSender: json['replyToSender'],
      audioDuration: json['audioDuration'],
    );
  }
}

class User {
  final String id;
  final String name;
  final bool isOnline;
  final String? avatarUrl; // FIXED: Avatar URL qo'shildi

  User({
    required this.id,
    required this.name,
    this.isOnline = false,
    this.avatarUrl, // FIXED: Constructor parametriga qo'shildi
  });

  User copyWith({
    String? id,
    String? name,
    bool? isOnline,
    String? avatarUrl, // FIXED: copyWith'ga qo'shildi
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      isOnline: isOnline ?? this.isOnline,
      avatarUrl: avatarUrl ?? this.avatarUrl, // FIXED
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isonline': isOnline,
      'avatarurl': avatarUrl, // FIXED: Supabase column nomiga mos
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      isOnline: json['isonline'] ?? false,
      avatarUrl: json['avatarurl'], // FIXED: Supabase column nomiga mos
    );
  }
}