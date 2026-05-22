import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/theme/AppTheme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screen/FullScreenImage.dart';

class MessageBubble extends StatelessWidget {
  final Message      message;
  final bool         isMine;
  final bool         showSenderName;
  final bool         isSelected;
  final bool         isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.showSenderName,
    required this.onTap,
    required this.onLongPress,
    this.isSelected      = false,
    this.isSelectionMode = false,
  });

  String _fmtTime(DateTime dt) {
    final t = dt.toUtc().add(const Duration(hours: 5));
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  BorderRadius get _radius => BorderRadius.only(
    topLeft:     const Radius.circular(18),
    topRight:    const Radius.circular(18),
    bottomLeft:  Radius.circular(isMine ? 18 : 4),
    bottomRight: Radius.circular(isMine ? 4 : 18),
  );

  @override
  Widget build(BuildContext context) {
    final timeStr = _fmtTime(message.timestamp);
    final isImage = message.type == MessageType.image;

    return GestureDetector(
      onTap:       onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: isSelected
            ? AppTheme.primary.withAlpha(40)
            : Colors.transparent,
        padding: EdgeInsets.only(
          top: 2, bottom: 2,
          left:  isMine ? 60 : 4,
          right: isMine ? 4 : 60,
        ),
        child: Row(
          mainAxisAlignment:
          isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [

            // ── Selection checkbox (Telegram uslubi) ──────────────────────
            if (isSelectionMode)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, right: 6, left: 6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? AppTheme.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 14)
                      : null,
                ),
              ),

            // ── Bubble ────────────────────────────────────────────────────
            Flexible(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: message.isDeleted
                      ? AppTheme.surfaceLight.withAlpha(180)
                      : isMine
                      ? AppTheme.myMsgBg
                      : AppTheme.otherMsgBg,
                  borderRadius: _radius,
                ),
                child: ClipRRect(
                  borderRadius: _radius,
                  child: message.isDeleted
                      ? _DeletedContent(isMine: isMine, timeStr: timeStr)
                      : isImage
                      ? _ImageContent(
                    content: message.content,
                    timeStr: timeStr,
                    isMine:  isMine,
                    isRead:  message.isRead,
                  )
                      : _TextContent(
                    message:        message,
                    timeStr:        timeStr,
                    isMine:         isMine,
                    showSenderName: showSenderName,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  O'chirilgan xabar
// ═══════════════════════════════════════════════════════════════════════════════
class _DeletedContent extends StatelessWidget {
  final bool   isMine;
  final String timeStr;
  const _DeletedContent({required this.isMine, required this.timeStr});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block_rounded,
              size: 14, color: Colors.white.withAlpha(100)),
          const SizedBox(width: 5),
          Text("O'chirilgan xabar.",
              style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: Colors.white.withAlpha(120))),
          const SizedBox(width: 8),
          Text(timeStr,
              style: TextStyle(
                  fontSize: 11, color: Colors.white.withAlpha(80))),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Matn xabari
// ═══════════════════════════════════════════════════════════════════════════════
class _TextContent extends StatelessWidget {
  final Message message;
  final String  timeStr;
  final bool    isMine;
  final bool    showSenderName;

  const _TextContent({
    required this.message,
    required this.timeStr,
    required this.isMine,
    required this.showSenderName,
  });

  static const _nameColors = [
    Color(0xFF6C63FF), Color(0xFF00D4AA), Color(0xFFFF6584),
    Color(0xFFFFB347), Color(0xFF4FC3F7), Color(0xFFAB47BC),
  ];

  Color _nameColor(String name) =>
      _nameColors[name.hashCode.abs() % _nameColors.length];

  @override
  Widget build(BuildContext context) {
    final hasReply = message.replyToId != null &&
        (message.replyToContent?.isNotEmpty ?? false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Guruhda kim yozgani ──────────────────────────────────────────
          if (showSenderName) ...[
            Text(message.senderName,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _nameColor(message.senderName))),
            const SizedBox(height: 3),
          ],

          // ── Reply preview ────────────────────────────────────────────────
          if (hasReply)
            _ReplyPreview(
              sender:  message.replyToSender ?? '',
              content: message.replyToContent ?? '',
              isMine:  isMine,
            ),

          // ── Matn + vaqt + galochka ───────────────────────────────────────
          Wrap(
            alignment:      WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(message.content,
                  style: const TextStyle(
                      fontSize: 15, color: Colors.white, height: 1.4)),
              const SizedBox(width: 6),
              _MetaRow(
                timeStr:  timeStr,
                isMine:   isMine,
                isRead:   message.isRead,
                isEdited: message.isEdited,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Reply preview (xabar ichida)
// ═══════════════════════════════════════════════════════════════════════════════
class _ReplyPreview extends StatelessWidget {
  final String sender;
  final String content;
  final bool   isMine;

  const _ReplyPreview({
    required this.sender,
    required this.content,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: isMine
            ? Colors.white.withAlpha(25)
            : Colors.black.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isMine
                ? Colors.white.withAlpha(180)
                : AppTheme.primary,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sender.isNotEmpty)
            Text(sender,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isMine
                        ? Colors.white.withAlpha(220)
                        : AppTheme.primary)),
          const SizedBox(height: 1),
          Text(content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withAlpha(160))),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Vaqt + galochka + tahrirlangan belgisi
// ═══════════════════════════════════════════════════════════════════════════════
class _MetaRow extends StatelessWidget {
  final String timeStr;
  final bool   isMine;
  final bool   isRead;
  final bool   isEdited;   // ✅ Faqat DB dan true kelganda ko'rinadi

  const _MetaRow({
    required this.timeStr,
    required this.isMine,
    required this.isRead,
    required this.isEdited,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // "Tahrirlangan" — faqat isEdited == true bo'lganda
        if (isEdited) ...[
          Text('tahrirlangan',
              style: TextStyle(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: Colors.white.withAlpha(120))),
          const SizedBox(width: 3),
        ],
        Text(timeStr,
            style: TextStyle(
                fontSize: 11,
                color: isMine
                    ? Colors.white.withAlpha(153)
                    : const Color(0xFF8899A6))),
        if (isMine) ...[
          const SizedBox(width: 3),
          Icon(
            isRead
                ? Icons.done_all_rounded
                : Icons.done_rounded,
            size:  14,
            color: isRead
                ? const Color(0xFF6EC9CB)
                : Colors.white.withAlpha(140),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Rasm xabari
// ═══════════════════════════════════════════════════════════════════════════════
class _ImageContent extends StatelessWidget {
  final String content;
  final bool   isMine;
  final String timeStr;
  final bool   isRead;

  const _ImageContent({
    required this.content,
    required this.isMine,
    required this.timeStr,
    required this.isRead,
  });

  String _extractUrl() {
    try {
      final data  = jsonDecode(content) as Map<String, dynamic>;
      final value = (data['fileName'] as String? ?? '').trim();
      if (value.isEmpty) return '';
      if (value.startsWith('http')) return value;
      return Supabase.instance.client.storage
          .from('chat_images')
          .getPublicUrl(value);
    } catch (_) {}
    final raw = content.trim();
    if (raw.startsWith('http')) return raw;
    return Supabase.instance.client.storage
        .from('chat_images')
        .getPublicUrl(raw);
  }

  @override
  Widget build(BuildContext context) {
    final url = _extractUrl();
    if (url.isEmpty) return _brokenImage();

    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(
              builder: (_) => FullScreenImage(imageUrl: url))),
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
                maxWidth: 260, minWidth: 120, minHeight: 80),
            child: Image.network(
              url,
              fit: BoxFit.contain,
              width: double.infinity,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: 220, height: 140,
                  color: const Color(0xFF1E2C3A),
                  child: Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                          : null,
                      strokeWidth: 2.5,
                      color: AppTheme.primary,
                    ),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => _brokenImage(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color:        Colors.black.withAlpha(120),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _MetaRow(
                timeStr:  timeStr,
                isMine:   isMine,
                isRead:   isRead,
                isEdited: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brokenImage() => Container(
    width: 220, height: 140,
    color: const Color(0xFF2A3A4A),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image_not_supported_rounded,
            size: 40, color: Colors.white.withAlpha(100)),
        const SizedBox(height: 8),
        Text('Rasm yuklanmadi',
            style: TextStyle(
                fontSize: 12, color: Colors.white.withAlpha(120))),
      ],
    ),
  );
}