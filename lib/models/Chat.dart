import 'package:flutter/material.dart';

enum MessageType { text, image }
enum ChatType    { personal, group }

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
    id:        j['id']        as String? ?? '',
    name:      j['name']      as String? ?? 'Foydalanuvchi',
    avatarUrl: j['avatarurl'] as String? ?? j['avatarUrl'] as String? ?? '', // Ham kichik, ham katta harf uchun xavfsizlik
    isOnline:  j['isonline']  as bool?   ?? j['isOnline']  as bool?   ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id':        id,
    'name':      name,
    'avatarurl': avatarUrl,
    'isonline':  isOnline,
  };
}

class Message {
  final String      id;
  final String      chatId;
  final String      senderId;
  final String      senderName;
  late final String content;
  final MessageType type;
  final DateTime    timestamp;
  bool isRead;

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.content,
    this.type      = MessageType.text,
    DateTime?      timestamp,
    this.isRead    = false,
  }) : timestamp = timestamp ?? DateTime.now();

  factory Message.fromJson(Map<String, dynamic> j) {
    DateTime ts = DateTime.now();
    // Supabase odatda 'created_at' qaytaradi, agar u bo'lmasa 'timestamp' ni tekshiradi
    final rawTs = (j['created_at'] ?? j['timestamp']) as String?;
    if (rawTs != null && rawTs.isNotEmpty) {
      ts = DateTime.tryParse(rawTs) ?? DateTime.now();
    }

    return Message(
      id:         j['id']?.toString()    ?? '',
      chatId:     (j['chatid'] ?? j['chatId']) as String? ?? '',       // Supabase va lokal uchun xavfsiz mapping
      senderId:   (j['senderid'] ?? j['senderId']) as String? ?? '',
      senderName: (j['sendername'] ?? j['senderName']) as String? ?? '',
      content:    j['content']           as String? ?? '',
      type:       j['type'] == 'image' ? MessageType.image : MessageType.text,
      timestamp:  ts,
      isRead:     (j['is_read'] ?? j['isRead']) as bool? ?? false,
    );
  }

  // Supabase-ga to'g'ridan-to'g'ri insert qilish uchun kalitlar kichik harfda
  Map<String, dynamic> toJson() => {
    'chatid':     chatId,
    'senderid':   senderId,
    'sendername': senderName,
    'content':    content,
    'type':       type == MessageType.image ? 'image' : 'text',
    // 'id' va 'created_at' ni Supabase o'zi avtomat yaratadi, shuning uchun bu yerga shart emas
  };
}

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