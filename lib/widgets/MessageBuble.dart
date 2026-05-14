import 'dart:io';
import 'package:flutter/material.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/theme/AppTheme.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool    isMine;
  final bool    showSenderName;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.showSenderName = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top:    showSenderName ? 12 : 3,
        bottom: 3,
        left:   isMine ? 48 : 0,
        right:  isMine ? 0  : 48,
      ),
      child: Column(
        crossAxisAlignment:
        isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Sender name (group only)
          if (showSenderName)
            Padding(
              padding: const EdgeInsets.only(left: 14, bottom: 4),
              child: Text(message.senderName,
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),

          // Bubble
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72),
            decoration: BoxDecoration(
              color: isMine ? AppTheme.myMsgBg : AppTheme.otherMsgBg,
              borderRadius: BorderRadius.only(
                topLeft:     const Radius.circular(18),
                topRight:    const Radius.circular(18),
                bottomLeft:  Radius.circular(isMine ? 18 : 4),
                bottomRight: Radius.circular(isMine ? 4  : 18),
              ),
              boxShadow: [
                BoxShadow(
                  color: isMine
                      ? AppTheme.primary.withOpacity(.2)
                      : Colors.black.withOpacity(.15),
                  blurRadius: 8, offset: const Offset(0, 2),
                ),
              ],
            ),
            child: message.type == MessageType.image
                ? _ImageContent(message: message, isMine: isMine)
                : _TextContent(message: message, isMine: isMine),
          ),

          // Time + status
          Padding(
            padding: EdgeInsets.only(
              top:   3,
              left:  isMine ? 0 : 4,
              right: isMine ? 4 : 0,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_fmt(message.timestamp),
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 10)),
              if (isMine) ...[
                const SizedBox(width: 3),
                const Icon(Icons.done_all, size: 12, color: AppTheme.accent),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ── Text bubble ───────────────────────────────────────────────
class _TextContent extends StatelessWidget {
  final Message message;
  final bool    isMine;
  const _TextContent({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Text(
      message.content,
      style: TextStyle(
          color: isMine ? Colors.white : AppTheme.textPrimary,
          fontSize: 15, height: 1.4),
    ),
  );
}

// ── Image bubble ──────────────────────────────────────────────
class _ImageContent extends StatelessWidget {
  final Message message;
  final bool    isMine;
  const _ImageContent({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final isNet = message.content.startsWith('http');
    final radius = BorderRadius.only(
      topLeft:     const Radius.circular(18),
      topRight:    const Radius.circular(18),
      bottomLeft:  Radius.circular(isMine ? 18 : 4),
      bottomRight: Radius.circular(isMine ? 4  : 18),
    );

    Widget img;
    if (isNet) {
      img = Image.network(message.content,
          width: 220, height: 220, fit: BoxFit.cover,
          loadingBuilder: (_, child, p) =>
          p == null ? child : _placeholder(),
          errorBuilder: (_, __, ___) => _error());
    } else {
      img = Image.file(File(message.content),
          width: 220, height: 220, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _error());
    }

    return ClipRRect(borderRadius: radius, child: img);
  }

  Widget _placeholder() => Container(
    width: 220, height: 220, color: AppTheme.surfaceLight,
    child: const Center(
        child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)),
  );

  Widget _error() => Container(
    width: 220, height: 100, color: AppTheme.surfaceLight,
    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.broken_image_outlined, color: AppTheme.textSecondary, size: 30),
      SizedBox(height: 6),
      Text('Yuklanmadi', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
    ]),
  );
}