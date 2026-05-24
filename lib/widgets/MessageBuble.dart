import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/theme/AppTheme.dart';

// ── Helper: timestamp → '14:38' (O'zbekiston vaqti UTC+5) ─────────────────────
String _fmtTime(DateTime dt) {
  final uzb = dt.toUtc().add(const Duration(hours: 0));
  final h = uzb.hour.toString().padLeft(2, '0');
  final m = uzb.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

// ═══════════════════════════════════════════════════════════════════════════════
//  MessageBubble — tashqi widget (ChatScreen ishlatadi)
// ═══════════════════════════════════════════════════════════════════════════════
class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool showSenderName;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Function(String)? onImageTap;
  final Function(String)? onVideoTap;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.showSenderName,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
    this.onImageTap,
    this.onVideoTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: isSelected ? AppTheme.primary.withAlpha(40) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: IgnorePointer(
          ignoring: isSelectionMode,
          child: GestureDetector(
            onTap: onTap,
            onLongPress: onLongPress,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              color: isSelected
                  ? AppTheme.primary.withAlpha(40)
                  : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Align(
                alignment: isMine
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  child: _BubbleContent(
                    message: message,
                    isMine: isMine,
                    showSenderName: showSenderName,
                    onImageTap: onImageTap,
                    onVideoTap: onVideoTap,
                  ),
                ),
              ),
            ),
          ),
        ),      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Bubble content — xabar turiga qarab render
// ═══════════════════════════════════════════════════════════════════════════════
class _BubbleContent extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool showSenderName;
  final Function(String)? onImageTap;
  final Function(String)? onVideoTap;

  const _BubbleContent({
    required this.message,
    required this.isMine,
    required this.showSenderName,
    this.onImageTap,
    this.onVideoTap,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) {
      return _DeletedBubble(isMine: isMine);
    }
    if (message.type == MessageType.audio) {
      return _AudioBubble(
        message: message,
        isMine: isMine,
        showSenderName: showSenderName,
      );
    }
    if (message.type == MessageType.image) {
      return _ImageBubble(
        message: message,
        isMine: isMine,
        showSenderName: showSenderName,
        onImageTap: onImageTap,
      );
    }
    return _TextBubble(
      message: message,
      isMine: isMine,
      showSenderName: showSenderName,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Audio bubble — Telegram uslubida
// ═══════════════════════════════════════════════════════════════════════════════
class _AudioBubble extends StatefulWidget {
  final Message message;
  final bool isMine;
  final bool showSenderName;

  const _AudioBubble({
    required this.message,
    required this.isMine,
    required this.showSenderName,
  });

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  late final AnimationController _waveAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;

  @override
  void initState() {
    super.initState();

    _stateSub = _player.playerStateStream.listen((s) {
      if (!mounted) return;
      setState(() {
        _isPlaying = s.playing;
        _isLoading =
            s.processingState == ProcessingState.loading ||
            s.processingState == ProcessingState.buffering;
      });
      if (s.playing) {
        _waveAnim.repeat(reverse: true);
      } else {
        _waveAnim.stop();
      }
      if (s.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
        setState(() => _position = Duration.zero);
      }
    });

    _posSub = _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });

    _durSub = _player.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d ?? Duration.zero);
    });
  }

  @override
  void dispose() {
    _waveAnim.dispose();
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.idle) {
        setState(() => _isLoading = true);
        try {
          await _player.setUrl(widget.message.content);
        } catch (_) {
          setState(() => _isLoading = false);
          return;
        }
      }
      await _player.play();
    }
  }

  double get _progress {
    if (_duration.inMilliseconds == 0) return 0;
    return (_position.inMilliseconds / _duration.inMilliseconds).clamp(
      0.0,
      1.0,
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isMine ? AppTheme.primary : AppTheme.surface;
    final activeColor = widget.isMine ? Colors.white : AppTheme.primary;
    final inactiveClr = widget.isMine ? Colors.white38 : Colors.white24;
    const textColor = Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(widget.isMine ? 18 : 4),
          bottomRight: Radius.circular(widget.isMine ? 4 : 18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(40),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showSenderName)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                widget.message.senderName,
                style: TextStyle(
                  color: activeColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          if (widget.message.replyToId != null)
            _ReplyPreview(
              senderName: widget.message.replyToSender ?? '',
              content: widget.message.replyToContent ?? '',
              isMine: widget.isMine,
            ),

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _toggle,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: textColor,
                          size: 24,
                        ),
                ),
              ),
              const SizedBox(width: 8),

              SizedBox(
                width: 160,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _WaveformBars(
                      progress: _progress,
                      isPlaying: _isPlaying,
                      activeColor: activeColor,
                      inactiveColor: inactiveClr,
                      animation: _waveAnim,
                    ),
                    const SizedBox(height: 2),
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: SliderComponentShape.noOverlay,
                        activeTrackColor: activeColor,
                        inactiveTrackColor: inactiveClr,
                        thumbColor: activeColor,
                      ),
                      child: Slider(
                        value: _progress,
                        onChanged: (v) {
                          _player.seek(
                            Duration(
                              milliseconds: (v * _duration.inMilliseconds)
                                  .round(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.only(left: 50, top: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isPlaying || _position > Duration.zero
                      ? _fmt(_position)
                      : _fmt(_duration),
                  style: TextStyle(
                    color: textColor.withAlpha(100),
                    fontSize: 11,
                  ),
                ),
                _TimeStatus(
                  time: _fmtTime(widget.message.timestamp),
                  isMine: widget.isMine,
                  isRead: widget.message.isRead,
                  color: textColor.withAlpha(180),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Waveform bars animatsiyasi
// ═══════════════════════════════════════════════════════════════════════════════
class _WaveformBars extends StatelessWidget {
  final double progress;
  final bool isPlaying;
  final Color activeColor;
  final Color inactiveColor;
  final AnimationController animation;

  const _WaveformBars({
    required this.progress,
    required this.isPlaying,
    required this.activeColor,
    required this.inactiveColor,
    required this.animation,
  });

  static const _heights = [
    5.0,
    10.0,
    7.0,
    14.0,
    9.0,
    18.0,
    12.0,
    16.0,
    7.0,
    20.0,
    9.0,
    15.0,
    11.0,
    18.0,
    7.0,
    13.0,
    17.0,
    9.0,
    15.0,
    11.0,
    19.0,
    7.0,
    13.0,
    16.0,
    5.0,
    9.0,
    14.0,
    11.0,
    7.0,
    13.0,
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) => SizedBox(
        height: 22,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(_heights.length, (i) {
            final barPct = i / _heights.length;
            final isPast = barPct <= progress;
            double h = _heights[i];
            if (isPlaying && (barPct - progress).abs() < 0.12) {
              h = h * (0.65 + 0.35 * animation.value);
            }
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  height: h,
                  decoration: BoxDecoration(
                    color: isPast ? activeColor : inactiveColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Text bubble
// ═══════════════════════════════════════════════════════════════════════════════
class _TextBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool showSenderName;

  const _TextBubble({
    required this.message,
    required this.isMine,
    required this.showSenderName,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isMine ? AppTheme.primary : AppTheme.surface;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMine ? 18 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(40),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSenderName)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                message.senderName,
                style: TextStyle(
                  color: isMine ? Colors.white70 : AppTheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          if (message.replyToId != null)
            _ReplyPreview(
              senderName: message.replyToSender ?? '',
              content: message.replyToContent ?? '',
              isMine: isMine,
            ),

          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  message.isEdited ? '${message.content}  ' : message.content,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.isEdited)
                    Text(
                      'tahrirlangan  ',
                      style: TextStyle(
                        color: Colors.white.withAlpha(140),
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  _TimeStatus(
                    time: _fmtTime(message.timestamp),
                    isMine: isMine,
                    isRead: message.isRead,
                    color: Colors.white60,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Image bubble — 240x240 standart size + fullscreen preview
// ═══════════════════════════════════════════════════════════════════════════════
class _ImageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool showSenderName;
  final Function(String)? onImageTap;

  const _ImageBubble({
    required this.message,
    required this.isMine,
    required this.showSenderName,
    this.onImageTap,
  });

  // ✅ Image URL yasab beradi
  String _url() {
    final raw = message.content.trim();

    // Agar allaqachon to'liq URL bo'lsa
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    // Supabase public storage URL
    return 'https://lrkweduvjgmqerygvoaw.supabase.co/storage/v1/object/public/chat_bucket/$raw';
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _url();

    return GestureDetector(
      onTap: () {
        if (onImageTap != null) {
          // ✅ To'liq URL ni uzatish
          if (imageUrl.isNotEmpty) {
            onImageTap!(imageUrl);
          }
        }
      },
      child: Container(
        width: 240,
        height: 240,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(40),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Image.network(
              message.content,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => Container(
                width: 240,
                height: 240,
                color: AppTheme.surfaceLight,
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: AppTheme.textSecondary,
                ),
              ),
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : Container(
                      width: 240,
                      height: 240,
                      color: AppTheme.surfaceLight,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(120),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.fullscreen,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
            Positioned(
              bottom: 6,
              right: 8,
              child: _TimeStatus(
                time: _fmtTime(message.timestamp),
                isMine: isMine,
                isRead: message.isRead,
                color: Colors.white,
                withShadow: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Video bubble — 240x240 + fullscreen preview + play icon
// ═══════════════════════════════════════════════════════════════════════════════
class _VideoBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool showSenderName;
  final Function(String)? onVideoTap;

  const _VideoBubble({
    required this.message,
    required this.isMine,
    required this.showSenderName,
    this.onVideoTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onVideoTap?.call(message.content),
      child: Container(
        width: 240,
        height: 240,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(40),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Container(
              width: 240,
              height: 240,
              color: AppTheme.surfaceLight,
              child: const Icon(
                Icons.video_library_outlined,
                size: 60,
                color: AppTheme.textSecondary,
              ),
            ),
            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 32,
                  color: AppTheme.primary,
                ),
              ),
            ),
            Positioned(
              bottom: 6,
              right: 8,
              child: _TimeStatus(
                time: _fmtTime(message.timestamp),
                isMine: isMine,
                isRead: message.isRead,
                color: Colors.white,
                withShadow: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Sticker bubble — 150x150 stiker
// ═══════════════════════════════════════════════════════════════════════════════
class _StickerBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool showSenderName;

  const _StickerBubble({
    required this.message,
    required this.isMine,
    required this.showSenderName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        message.content,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: AppTheme.surfaceLight,
          child: const Icon(
            Icons.image_not_supported_outlined,
            color: AppTheme.textSecondary,
          ),
        ),
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : Container(
                color: AppTheme.surfaceLight,
                child: const Center(child: CircularProgressIndicator()),
              ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Deleted bubble
// ═══════════════════════════════════════════════════════════════════════════════
class _DeletedBubble extends StatelessWidget {
  final bool isMine;

  const _DeletedBubble({required this.isMine});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMine ? AppTheme.primary.withAlpha(120) : AppTheme.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMine ? 18 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.block_rounded,
            size: 14,
            color: Colors.white.withAlpha(150),
          ),
          const SizedBox(width: 5),
          Text(
            "O'chirilgan xabar",
            style: TextStyle(
              color: Colors.white.withAlpha(150),
              fontSize: 13.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Reply preview
// ═══════════════════════════════════════════════════════════════════════════════
class _ReplyPreview extends StatelessWidget {
  final String senderName;
  final String content;
  final bool isMine;

  const _ReplyPreview({
    required this.senderName,
    required this.content,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = isMine ? Colors.white70 : AppTheme.primary;
    final isAudio =
        content.contains('.m4a') ||
        content.contains('.mp3') ||
        content.contains('audio_');
    final isImage =
        content.startsWith('http') &&
        (content.contains('.jpg') ||
            content.contains('.png') ||
            content.contains('.jpeg') ||
            content.contains('images'));
    final isVideo =
        content.startsWith('http') &&
        (content.contains('.mp4') ||
            content.contains('.mov') ||
            content.contains('video'));

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: accentColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            senderName,
            style: TextStyle(
              color: accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            isAudio
                ? '🎤 Audio xabar'
                : isVideo
                ? '🎬 Video'
                : isImage
                ? '📷 Rasm'
                : content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withAlpha(180),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Vaqt + o'qilgan belgisi — UTC+5 DA
// ═══════════════════════════════════════════════════════════════════════════════
class _TimeStatus extends StatelessWidget {
  final String time;
  final bool isMine;
  final bool isRead;
  final Color color;
  final bool withShadow;

  const _TimeStatus({
    required this.time,
    required this.isMine,
    required this.isRead,
    required this.color,
    this.withShadow = false,
  });

  @override
  Widget build(BuildContext context) {
    final shadows = withShadow
        ? const [Shadow(color: Colors.black54, blurRadius: 4)]
        : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          time, // ← _fmtTime() tomonidan UTC+5 bilan formatlangan
          style: TextStyle(color: color, fontSize: 10.5, shadows: shadows),
        ),
        if (isMine) ...[
          const SizedBox(width: 3),
          Icon(
            isRead ? Icons.done_all_rounded : Icons.done_rounded,
            size: 13,
            color: isRead ? Colors.lightBlueAccent : color,
            shadows: withShadow
                ? const [Shadow(color: Colors.black54, blurRadius: 4)]
                : null,
          ),
        ],
      ],
    );
  }
}
