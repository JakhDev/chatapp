import 'package:flutter/material.dart';
import 'package:chatapp/models/Chat.dart'; // Message modelingiz shu yerda
import 'package:chatapp/theme/AppTheme.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool showSenderName;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.showSenderName,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showSenderName)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Text(message.senderName, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMine ? AppTheme.primary : AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(16),
            ),
            // Rasm bo'lsa rasmni, matn bo'lsa matnni ko'rsatish
            child: message.type == MessageType.image
                ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(message.content, width: 200, fit: BoxFit.cover),
            )
                : Text(message.content, style: TextStyle(color: isMine ? Colors.white : AppTheme.textPrimary)),
          ),
        ],
      ),
    );
  }
}