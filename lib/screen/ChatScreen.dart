import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/providers/ChatProvider.dart';
import 'package:chatapp/theme/AppTheme.dart';
import 'package:chatapp/widgets/AvatarWidget.dart';
import 'package:chatapp/widgets/MessageBuble.dart';
import 'package:chatapp/services/AudioService.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;
  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final _textCtrl   = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode  = FocusNode();
  final _picker     = ImagePicker();
  final _audioSvc   = AudioService();

  bool        _typing          = false;
  Message?    _replyTo;
  Set<String> _selected        = {};
  bool        _isSelectionMode = false;
  bool        _isRecording     = false;
  Duration    _recordingDuration = Duration.zero;
  Timer?      _recordTimer;

  late final AnimationController _recordAnim = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(
            () => setState(() => _typing = _textCtrl.text.trim().isNotEmpty));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().openChat(widget.chat.id);
      context.read<ChatProvider>().markAsRead(widget.chat.id);
      FocusScope.of(context).requestFocus(_focusNode);
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _recordAnim.dispose();
    _recordTimer?.cancel();
    _audioSvc.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _send() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    context.read<ChatProvider>().sendText(
      widget.chat.id, text, widget.chat.name, context,
      replyTo: _replyTo,
    );
    _textCtrl.clear();
    setState(() => _replyTo = null);
    _scrollToBottom();
  }

  Future<void> _pickImage() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: AppTheme.primary),
            title: const Text('Kamera',
                style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: AppTheme.accent),
            title: const Text('Galereya',
                style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (src == null) return;
    final file = await _picker.pickImage(source: src, imageQuality: 80);
    if (file == null || !mounted) return;
    context.read<ChatProvider>().sendImage(
        widget.chat.id, file, widget.chat.name, context);
  }

  Future<void> _startAudioRecording() async {
    final ok = await _audioSvc.startRecording();
    if (!ok) return;
    setState(() {
      _isRecording       = true;
      _recordingDuration = Duration.zero;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() =>
      _recordingDuration += const Duration(seconds: 1));
    });
  }

  Future<void> _stopAudioRecording() async {
    _recordTimer?.cancel();
    final path = await _audioSvc.stopRecording();
    setState(() => _isRecording = false);
    if (path == null || !mounted) return;
    context.read<ChatProvider>().sendAudio(
        widget.chat.id, path, widget.chat.name, context, widget.chat.name);
    _scrollToBottom();
  }

  Future<void> _cancelAudioRecording() async {
    _recordTimer?.cancel();
    await _audioSvc.cancelRecording();
    setState(() {
      _isRecording       = false;
      _recordingDuration = Duration.zero;
    });
  }

  void _onLongPress(Message msg) {
    if (msg.id.startsWith('local_') || msg.isDeleted) return;
    final myId = context.read<ChatProvider>().currentUser?.id ?? '';
    if (msg.senderId != myId) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isSelectionMode = true;
      _selected        = {msg.id};
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _isSelectionMode = false;
      } else {
        _selected.add(id);
      }
    });
  }

  void _cancelSelection() => setState(() {
    _isSelectionMode = false;
    _selected.clear();
  });

  void _copySelected() {
    final msgs  = context.read<ChatProvider>().messages(widget.chat.id);
    final texts = _selected
        .map((id) => msgs.firstWhere((m) => m.id == id,
        orElse: () => msgs.first))
        .where((m) => m.type == MessageType.text)
        .map((m) => m.content)
        .join('\n');
    Clipboard.setData(ClipboardData(text: texts));
    _cancelSelection();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content:  Text('Nusxa olindi'),
      duration: Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _deleteSelected() async {
    final ids = List<String>.from(_selected);
    _cancelSelection();
    for (final id in ids) {
      await context.read<ChatProvider>().deleteMessage(
          widget.chat.id, id, context);
    }
  }

  void _confirmDelete() {
    final count = _selected.length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("$count ta xabarni o'chirish",
            style: const TextStyle(color: AppTheme.textPrimary,
                fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('$count ta xabar barcha uchun o\'chiriladi.',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Bekor qilish',
                  style: TextStyle(color: AppTheme.textSecondary))),
          TextButton(
              onPressed: () { Navigator.pop(ctx); _deleteSelected(); },
              child: const Text("O'chirish",
                  style: TextStyle(color: Colors.redAccent,
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  void _onTap(Message msg, String myId) {
    if (_isSelectionMode) {
      if (!msg.id.startsWith('local_') && !msg.isDeleted) _toggleSelect(msg.id);
      return;
    }
    if (msg.senderId == myId &&
        !msg.isDeleted &&
        msg.type == MessageType.text &&
        !msg.id.startsWith('local_')) {
      _showEditDialog(msg);
    }
  }

  void _showEditDialog(Message msg) {
    final ctrl = TextEditingController(text: msg.content);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.edit_rounded,
                        color: AppTheme.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('Xabarni tahrirlash',
                      style: TextStyle(color: AppTheme.textPrimary,
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  autofocus:  true,
                  maxLines:   null,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    filled:    true,
                    fillColor: AppTheme.surfaceLight,
                    hintText:  'Xabarni kiriting...',
                    hintStyle: const TextStyle(color: AppTheme.textSecondary),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: AppTheme.primary, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: AppTheme.surfaceLight,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Bekor qilish',
                          style: TextStyle(color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        final t = ctrl.text.trim();
                        if (t.isEmpty) return;
                        context.read<ChatProvider>().editMessage(
                            widget.chat.id, msg.id, t, context);
                        Navigator.pop(ctx);
                      },
                      child: const Text('Saqlash',
                          style: TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ]),
        ),
      ),
    );
  }

  // 🎯 MORE MENU
  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
            title: const Text("Chat history o'chirish",
                style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: const Text('Barcha xabarlar o\'chiriladi',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            onTap: () {
              Navigator.pop(ctx);
              _confirmClearHistory();
            },
          ),
          const Divider(height: 1, color: AppTheme.surfaceLight),
          ListTile(
            leading: const Icon(Icons.search_outlined, color: AppTheme.primary),
            title: const Text('Izlash',
                style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () => Navigator.pop(ctx),
          ),
        ]),
      ),
    );
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Chat history o'chirish?",
            style: TextStyle(color: AppTheme.textPrimary,
                fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text('Bu amal qaytarib bo\'lmaydi. Barcha xabarlar o\'chiriladi.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Bekor qilish',
                  style: TextStyle(color: AppTheme.textSecondary))),
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.read<ChatProvider>().clearChatHistory(widget.chat.id, context);
              },
              child: const Text("O'chirish",
                  style: TextStyle(color: Colors.redAccent,
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  PreferredSizeWidget _normalAppBar() {
    final isGroup = widget.chat.type == ChatType.group;
    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(children: [
        AvatarWidget(name: widget.chat.name, size: 38, isGroup: isGroup),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.chat.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textPrimary,
                    fontSize: 15, fontWeight: FontWeight.w600)),
            const Text('Onlayn',
                style: TextStyle(color: AppTheme.online, fontSize: 11)),
          ]),
        ),
      ]),
      actions: [
        // ➕ MORE BUTTON (Video va Call o'rniga)
        IconButton(
            tooltip: "Batafsil",
            icon: const Icon(Icons.more_vert_rounded,
                color: AppTheme.textSecondary),
            onPressed: _showMoreMenu),
      ],
    );
  }

  PreferredSizeWidget _selectionAppBar() {
    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: Colors.white),
        onPressed: _cancelSelection,
      ),
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: Text(
          '${_selected.length} ta tanlandi',
          key: ValueKey(_selected.length),
          style: const TextStyle(color: AppTheme.textPrimary,
              fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      actions: [
        if (_selected.length == 1)
          IconButton(
            tooltip:  'Nusxa olish',
            icon:     const Icon(Icons.copy_rounded, color: AppTheme.textSecondary),
            onPressed: _copySelected,
          ),
        IconButton(
          tooltip:  "O'chirish",
          icon:     const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
          onPressed: _confirmDelete,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final msgs     = provider.messages(widget.chat.id);
    final myId     = provider.currentUser?.id ?? '';
    final isGroup  = widget.chat.type == ChatType.group;

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (_isSelectionMode) { _cancelSelection(); return; }
        if (didPop) context.read<ChatProvider>().closeChat();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: _isSelectionMode ? _selectionAppBar() : _normalAppBar(),
        body: Column(children: [

          // ── Messages list with date separators ──
          Expanded(
            child: msgs.isEmpty
                ? const _EmptyChat()
                : ListView.builder(
              controller: _scrollCtrl,
              reverse:    true,
              padding:    const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 8),
              itemCount:  msgs.length * 2, // Date separators uchun
              itemBuilder: (_, i) {
                // Date separator
                if (i % 2 == 0) {
                  final msgIndex = (i ~/ 2);
                  if (msgIndex >= msgs.length) return null;

                  final msg = msgs[msgs.length - 1 - msgIndex];
                  final showDate = msgIndex == msgs.length - 1 ||
                      !_isSameDay(msg.timestamp,
                          msgs[msgs.length - 2 - msgIndex].timestamp);

                  if (!showDate) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _formatDate(msg.timestamp),
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }

                // Message
                final msgIndex = (i ~/ 2);
                final index    = msgs.length - 1 - msgIndex;
                final msg      = msgs[index];
                final isMine   = msg.senderId == myId;
                final canSwipe = !_isSelectionMode &&
                    !msg.isDeleted &&
                    !msg.id.startsWith('local_');

                return _SwipeableMessage(
                  key:     ValueKey(msg.id),
                  isMine:  isMine,
                  enabled: canSwipe,
                  onSwipe: () => setState(() => _replyTo = msg),
                  child: MessageBubble(
                    message:         msg,
                    isMine:          isMine,
                    showSenderName:  isGroup && !isMine,
                    isSelected:      _selected.contains(msg.id),
                    isSelectionMode: _isSelectionMode,
                    onTap:           () => _onTap(msg, myId),
                    onLongPress:     () => _onLongPress(msg),
                  ),
                );
              },
            ),
          ),

          // ── Reply bar ──
          if (_replyTo != null)
            _ReplyBar(
              message:  _replyTo!,
              onCancel: () => setState(() => _replyTo = null),
            ),

          // ── Input ──
          _InputBar(
            controller:        _textCtrl,
            focusNode:         _focusNode,
            isTyping:          _typing,
            onSend:            _send,
            onPickImage:       _pickImage,
            isRecording:       _isRecording,
            recordingDuration: _recordingDuration,
            onStartRecording:  _startAudioRecording,
            onStopRecording:   _stopAudioRecording,
            onCancelRecording: _cancelAudioRecording,
            recordAnimation:   _recordAnim,
          ),
        ]),
      ),
    );
  }

  // 📅 Kunlar ajratish uchun helper methods
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    if (_isSameDay(dt, now)) {
      return "Bugun";
    } else if (_isSameDay(dt, yesterday)) {
      return "Kecha";
    } else if (dt.year == now.year) {
      return "${_monthName(dt.month)} ${dt.day}";
    } else {
      return "${dt.day}.${dt.month}.${dt.year}";
    }
  }

  String _monthName(int m) {
    const names = [
      'Yan', 'Fev', 'Mar', 'Apr', 'May', 'Iyn',
      'Iyl', 'Avg', 'Sen', 'Okt', 'Noy', 'Dek',
    ];
    return names[m - 1];
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Swipe-to-reply
// ═══════════════════════════════════════════════════════════════════════════════
class _SwipeableMessage extends StatefulWidget {
  final Widget       child;
  final bool         isMine;
  final bool         enabled;
  final VoidCallback onSwipe;

  const _SwipeableMessage({
    super.key,
    required this.child,
    required this.isMine,
    required this.onSwipe,
    this.enabled = true,
  });

  @override
  State<_SwipeableMessage> createState() => _SwipeableMessageState();
}

class _SwipeableMessageState extends State<_SwipeableMessage> {
  double _drag      = 0;
  bool   _triggered = false;

  static const double _threshold = 64;
  static const double _maxDrag   = 80;

  void _onUpdate(DragUpdateDetails d) {
    if (!widget.enabled) return;
    setState(() {
      _drag = (_drag + d.delta.dx).clamp(0, _maxDrag);
      if (_drag >= _threshold && !_triggered) {
        _triggered = true;
        HapticFeedback.mediumImpact();
        widget.onSwipe();
      }
    });
  }

  void _onEnd(DragEndDetails _) => setState(() {
    _drag      = 0;
    _triggered = false;
  });

  @override
  Widget build(BuildContext context) {
    final progress = (_drag / _threshold).clamp(0.0, 1.0);

    return GestureDetector(
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd:    _onEnd,
      child: Stack(children: [
        Positioned(
          left:   widget.isMine ? null : 10,
          right:  widget.isMine ? 10 : null,
          top: 0, bottom: 0,
          child: Opacity(
            opacity: progress,
            child: Transform.scale(
              scale: 0.5 + 0.5 * progress,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.reply_rounded,
                    color: AppTheme.primary, size: 18),
              ),
            ),
          ),
        ),
        AnimatedContainer(
          duration: _drag == 0
              ? const Duration(milliseconds: 200)
              : Duration.zero,
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(_drag, 0, 0),
          child: widget.child,
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Reply bar
// ═══════════════════════════════════════════════════════════════════════════════
class _ReplyBar extends StatelessWidget {
  final Message      message;
  final VoidCallback onCancel;

  const _ReplyBar({required this.message, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final isImage = message.type == MessageType.image;
    final isAudio = message.type == MessageType.audio;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.surfaceLight)),
      ),
      child: Row(children: [
        Container(
          width: 3, height: 42,
          decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(message.senderName,
                style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              isImage ? '📷 Rasm' : isAudio ? '🎤 Audio' : message.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12),
            ),
          ]),
        ),
        if (isImage)
          Container(
            width: 36, height: 36,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: AppTheme.surfaceLight),
            child: const Icon(Icons.image_outlined,
                color: AppTheme.textSecondary, size: 18),
          ),
        IconButton(
          icon: const Icon(Icons.close,
              color: AppTheme.textSecondary, size: 18),
          onPressed: onCancel,
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Empty chat
// ═══════════════════════════════════════════════════════════════════════════════
class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.chat_bubble_outline_rounded,
          size: 56, color: AppTheme.textSecondary),
      SizedBox(height: 12),
      Text("Hali xabarlar yo'q",
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
      SizedBox(height: 6),
      Text('Birinchi xabarni yuboring 👋',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Input bar
// ═══════════════════════════════════════════════════════════════════════════════
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode             focusNode;
  final bool                  isTyping;
  final VoidCallback          onSend;
  final VoidCallback          onPickImage;
  final bool                  isRecording;
  final Duration              recordingDuration;
  final VoidCallback          onStartRecording;
  final VoidCallback          onStopRecording;
  final VoidCallback          onCancelRecording;
  final AnimationController   recordAnimation;

  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.isTyping,
    required this.onSend,
    required this.onPickImage,
    required this.isRecording,
    required this.recordingDuration,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onCancelRecording,
    required this.recordAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color:   AppTheme.background,
      padding: EdgeInsets.fromLTRB(
          8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: _CircleBtn(icon: Icons.add_rounded, onTap: onPickImage),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: TextField(
              focusNode:       focusNode,
              controller:      controller,
              maxLines:        null,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 15),
              decoration: InputDecoration(
                hintText:  'Xabar yozing...',
                hintStyle: const TextStyle(color: AppTheme.textSecondary),
                filled:    true,
                fillColor: AppTheme.surfaceLight,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.emoji_emotions_outlined,
                      color: AppTheme.textSecondary, size: 20),
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: isRecording
                ? _RecordingRow(
              key:               const ValueKey('rec'),
              duration:          recordingDuration,
              onStop:            onStopRecording,
              onCancel:          onCancelRecording,
              animation:         recordAnimation,
            )
                : _CircleBtn(
              key:       const ValueKey('btn'),
              icon:      isTyping ? Icons.send_rounded : Icons.mic_rounded,
              isPrimary: true,
              onTap:     isTyping ? onSend : onStartRecording,
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Circle button ─────────────────────────────────────────────────────────────
class _CircleBtn extends StatelessWidget {
  final IconData     icon;
  final bool         isPrimary;
  final VoidCallback onTap;

  const _CircleBtn({
    super.key,
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 46, height: 46,
      decoration: BoxDecoration(
        color: isPrimary ? AppTheme.primary : AppTheme.surfaceLight,
        shape: BoxShape.circle,
        boxShadow: isPrimary
            ? [BoxShadow(
            color:      AppTheme.primary.withAlpha(80),
            blurRadius: 12,
            offset:     const Offset(0, 4))]
            : null,
      ),
      child: Icon(icon,
          color: isPrimary ? Colors.white : AppTheme.textSecondary,
          size:  22),
    ),
  );
}

// ── Recording row ─────────────────────────────────────────────────────────────
class _RecordingRow extends StatelessWidget {
  final Duration            duration;
  final VoidCallback        onStop;
  final VoidCallback        onCancel;
  final AnimationController animation;

  const _RecordingRow({
    super.key,
    required this.duration,
    required this.onStop,
    required this.onCancel,
    required this.animation,
  });

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      GestureDetector(
        onTap: onCancel,
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
              color: Colors.red.withAlpha(200),
              shape: BoxShape.circle),
          child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
        ),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ScaleTransition(
            scale: animation.drive(Tween(begin: 0.8, end: 1.0)),
            child: Container(
              width: 10, height: 10,
              decoration: const BoxDecoration(
                  color: Colors.red, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 8),
          Text(_fmt(duration),
              style: const TextStyle(color: AppTheme.textPrimary,
                  fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: onStop,
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(
                color:      AppTheme.primary.withAlpha(80),
                blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
        ),
      ),
    ],
  );
}