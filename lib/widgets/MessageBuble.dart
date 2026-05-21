import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/theme/AppTheme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screen/FullScreenImage.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool showSenderName;
  final bool isRead;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.showSenderName,
    this.isRead = false,
  });

  String _formatTime(DateTime dateTime) {
    final uzb = dateTime.toUtc().add(const Duration(hours: 5));
    final hour = uzb.hour.toString().padLeft(2, '0');
    final minute = uzb.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final isImage = message.type == MessageType.image;
    final timeStr = _formatTime(message.timestamp);

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMine ? 16 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 16),
    );

    return Padding(
      padding: EdgeInsets.only(
        top: 2,
        bottom: 2,
        left: isMine ? 60 : 4,
        right: isMine ? 4 : 60,
      ),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4), // top/bottom bo'sh joy
          decoration: BoxDecoration(
            color: isMine ? AppTheme.primary : const Color(0xFF1E2C3A),
            borderRadius: radius,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: isImage
                ? _ImageContent(
              content: message.content,
              timeStr: timeStr,
              isMine: isMine,
              isRead: isRead,
            )
                : _TextContent(
              text: message.content,
              timeStr: timeStr,
              isMine: isMine,
              isRead: isRead,
              showSenderName: showSenderName,
              senderName: message.senderName,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Vaqt + galochka ──────────────────────────────────────────────────────────
class _TimeRow extends StatelessWidget {
  final String timeStr;
  final bool isMine;
  final bool isRead;

  const _TimeRow({
    required this.timeStr,
    required this.isMine,
    required this.isRead,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeStr,
          style: TextStyle(
            fontSize: 11,
            // FIX: withOpacity o'rniga withAlpha (deprecated emas)
            color: isMine
                ? Colors.white.withAlpha(153) // 0.6 * 255 ≈ 153
                : const Color(0xFF8899A6),
          ),
        ),
        if (isMine) ...[
          const SizedBox(width: 3),
          Icon(
            isRead ? Icons.done_all_rounded : Icons.done_rounded,
            size: 14,
            color: isRead
                ? const Color(0xFF6EC9CB)
                : Colors.white.withAlpha(140), // 0.55 * 255 ≈ 140
          ),
        ],
      ],
    );
  }
}

// ── Matn xabari ──────────────────────────────────────────────────────────────
class _TextContent extends StatelessWidget {
  final String text;
  final String timeStr;
  final String senderName;
  final bool isMine;
  final bool isRead;
  final bool showSenderName;

  const _TextContent({
    required this.text,
    required this.timeStr,
    required this.isMine,
    required this.isRead,
    required this.showSenderName,
    required this.senderName,
  });

  Color _nameColor(String name) {
    const colors = [Colors.blue, Colors.green, Colors.orange, Colors.pink];
    return colors[name.hashCode.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showSenderName)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                senderName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _nameColor(senderName),
                ),
              ),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                text,
                style: const TextStyle(fontSize: 15, color: Colors.white),
              ),
              const SizedBox(width: 6),
              _TimeRow(timeStr: timeStr, isMine: isMine, isRead: isRead),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Rasm xabari ──────────────────────────────────────────────────────────────
class _ImageContent extends StatelessWidget {
  final String content;
  final bool isMine;
  final String timeStr;
  final bool isRead;

  const _ImageContent({
    required this.content,
    required this.isMine,
    required this.timeStr,
    required this.isRead,
  });

  /// contentdan to'liq public URL ajratib oladi
  String _extractPublicUrl() {
    // 1) JSON formatda kelsa: {"fileName": "..."}
    try {
      final data = jsonDecode(content) as Map<String, dynamic>;
      final value = (data['fileName'] as String? ?? '').trim();

      if (value.isEmpty) return '';

      // Allaqachon to'liq URL bo'lsa — shundayicha qaytaramiz
      if (value.startsWith('http://') || value.startsWith('https://')) {
        return value;
      }

      // Faqat fayl nomi bo'lsa — getPublicUrl() bilan quramiz
      return Supabase.instance.client.storage
          .from('chat_images')
          .getPublicUrl(value);
    } catch (_) {}

    // 2) JSON emas — to'g'ridan-to'g'ri URL yoki fayl nomi
    final raw = content.trim();
    if (raw.isEmpty) return '';

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw; // Allaqachon to'liq URL
    }

    return Supabase.instance.client.storage
        .from('chat_images')
        .getPublicUrl(raw);
  }

  @override
  Widget build(BuildContext context) {
    final publicUrl = _extractPublicUrl();

    // URL bo'sh bo'lsa darhol broken UI ko'rsatamiz
    if (publicUrl.isEmpty) {
      return _brokenImage();
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FullScreenImage(imageUrl: publicUrl),
          ),
        );
      },
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          // Tabiiy o'lcham, max 260 kenglk
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 260,
              minWidth: 120,
              minHeight: 80,
            ),
            child: Image.network(
              publicUrl,
              fit: BoxFit.contain, // Rasmni kesmasdan to'liq ko'rsatadi
              width: double.infinity,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return _LoadingImage(loadingProgress: loadingProgress);
              },
              errorBuilder: (context, error, stackTrace) => _brokenImage(),
            ),
          ),
          // Vaqt overlay
          Padding(
            padding: const EdgeInsets.all(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(120),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _TimeRow(
                timeStr: timeStr,
                isMine: isMine,
                isRead: isRead,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Rasm yuklanmasa yoki URL bo'sh bo'lsa ko'rinadigan widget
  Widget _brokenImage() {
    return Container(
      width: 220,
      height: 140,
      color: const Color(0xFF2A3A4A),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_not_supported_rounded,
              size: 40, color: Colors.white.withAlpha(100)),
          const SizedBox(height: 8),
          Text(
            'Rasm yuklanmadi',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withAlpha(120),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Yuklanish animatsiyasi ────────────────────────────────────────────────────
class _LoadingImage extends StatelessWidget {
  final ImageChunkEvent loadingProgress;

  const _LoadingImage({required this.loadingProgress});

  @override
  Widget build(BuildContext context) {
    final total = loadingProgress.expectedTotalBytes;
    final loaded = loadingProgress.cumulativeBytesLoaded;
    final progress = total != null ? loaded / total : null;

    return Container(
      width: 220,
      height: 140,
      color: const Color(0xFF1E2C3A),
      child: Center(
        child: CircularProgressIndicator(
          value: progress,
          strokeWidth: 2.5,
          color: AppTheme.primary,
        ),
      ),
    );
  }
}