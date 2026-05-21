import 'package:flutter/material.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/theme/AppTheme.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool showSenderName;
  final bool isRead; // ✅ O'qilganmi yoki yo'q

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.showSenderName,
    this.isRead = false,
  });

  // UTC+5 — O'zbekiston vaqti
  String _formatTime(DateTime dateTime) {
    final uzb    = dateTime.toUtc().add(const Duration(hours: 5));
    final hour   = uzb.hour.toString().padLeft(2, '0');
    final minute = uzb.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final isImage = message.type == MessageType.image;
    final timeStr = _formatTime(message.timestamp);

    return Padding(
      padding: EdgeInsets.only(
        top: 2, bottom: 2,
        left:  isMine ? 60 : 8,
        right: isMine ? 8  : 60,
      ),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: CustomPaint(
                // painter: _TailPainter(
                //   isMine: isMine,
                //   color: isMine ? AppTheme.primary : const Color(0xFF1E2C3A),
                // ),
                child: Container(
                  margin: EdgeInsets.only(
                    left:  isMine ? 0 : 6,
                    right: isMine ? 6 : 0,
                  ),
                  decoration: BoxDecoration(
                    color: isMine ? AppTheme.primary : const Color(0xFF1E2C3A),
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(16),
                      topRight:    const Radius.circular(16),
                      bottomLeft:  Radius.circular(isMine ? 16 : 4),
                      bottomRight: Radius.circular(isMine ? 4  : 16),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(16),
                      topRight:    const Radius.circular(16),
                      bottomLeft:  Radius.circular(isMine ? 16 : 4),
                      bottomRight: Radius.circular(isMine ? 4  : 16),
                    ),
                    child: isImage
                        ? _ImageContent(
                      url:     message.content,
                      timeStr: timeStr,
                      isMine:  isMine,
                      isRead:  isRead,
                    )
                        : _TextContent(
                      text:           message.content,
                      timeStr:        timeStr,
                      isMine:         isMine,
                      isRead:         isRead,
                      showSenderName: showSenderName,
                      senderName:     message.senderName,
                    ),
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

// ── Vaqt + galochka row ───────────────────────────────────────────────────────
class _TimeRow extends StatelessWidget {
  final String timeStr;
  final bool   isMine;
  final bool   isRead;

  const _TimeRow({
    required this.timeStr,
    required this.isMine,
    required this.isRead,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          timeStr,
          style: TextStyle(
            fontSize: 11,
            color: isMine
                ? Colors.white.withOpacity(0.6)
                : const Color(0xFF8899A6),
          ),
        ),
        // ✅ Faqat o'z xabarlarimizda galochka chiqadi
        if (isMine) ...[
          const SizedBox(width: 3),
          Icon(
            // O'qilgan → 2 ta galochka, O'qilmagan → 1 ta galochka
            isRead ? Icons.done_all_rounded : Icons.done_rounded,
            size: 14,
            color: isRead
                ? const Color(0xFF6EC9CB) // Ko'k (o'qilgan)
                : Colors.white.withOpacity(0.55), // Oq (yuborilgan)
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
  final bool   isMine;
  final bool   isRead;
  final bool   showSenderName;
  final String senderName;

  const _TextContent({
    required this.text,
    required this.timeStr,
    required this.isMine,
    required this.isRead,
    required this.showSenderName,
    required this.senderName,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Guruh chatda ismi
          if (showSenderName)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                senderName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _nameColor(senderName),
                ),
              ),
            ),

          // Matn + vaqt + galochka
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: isMine ? Colors.white : const Color(0xFFE8EDF2),
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: _TimeRow(
                  timeStr: timeStr,
                  isMine:  isMine,
                  isRead:  isRead,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _nameColor(String name) {
    final colors = [
      const Color(0xFF6EC9CB),
      const Color(0xFFFF7F7F),
      const Color(0xFF8BC9FF),
      const Color(0xFFFFD97A),
      const Color(0xFFFF9ECA),
      const Color(0xFF7AFFA0),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }
}

// ── Rasm xabari ──────────────────────────────────────────────────────────────
class _ImageContent extends StatelessWidget {
  final String url;
  final String timeStr;
  final bool   isMine;
  final bool   isRead;

  const _ImageContent({
    required this.url,
    required this.timeStr,
    required this.isMine,
    required this.isRead,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Image.network(
          url,
          width:  220,
          height: 220,
          fit:    BoxFit.cover,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return Container(
              width: 220, height: 220,
              color: const Color(0xFF1A2733),
              child: Center(
                child: CircularProgressIndicator(
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                      progress.expectedTotalBytes!
                      : null,
                  color: AppTheme.primary,
                  strokeWidth: 2,
                ),
              ),
            );
          },
        ),
        // Vaqt + galochka rasm ustida
        Positioned(
          bottom: 6,
          right:  8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(10),
            ),
            child: _TimeRow(
              timeStr: timeStr,
              isMine:  isMine,
              isRead:  isRead,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Xabar dumi ───────────────────────────────────────────────────────────────
// class _TailPainter extends CustomPainter {
//   final bool  isMine;
//   final Color color;
//
//   const _TailPainter({required this.isMine, required this.color});
//
//   @override
//   void paint(Canvas canvas, Size size) {
//     final paint = Paint()..color = color;
//     final path  = Path();
//
//     if (isMine) {
//       path.moveTo(size.width + 6, size.height);
//       path.lineTo(size.width - 2, size.height - 14);
//       path.lineTo(size.width - 2, size.height);
//     } else {
//       path.moveTo(-6, size.height);
//       path.lineTo( 2, size.height - 14);
//       path.lineTo( 2, size.height);
//     }
//
//     path.close();
//     canvas.drawPath(path, paint);
//   }
//
//   @override
//   bool shouldRepaint(_TailPainter old) =>
//       old.isMine != isMine || old.color != color;
// }