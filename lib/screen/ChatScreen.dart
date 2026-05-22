import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/providers/ChatProvider.dart';
import 'package:chatapp/theme/AppTheme.dart';
import 'package:chatapp/widgets/AvatarWidget.dart';

import '../widgets/MessageBuble.dart';

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

  bool        _typing          = false;
  Message?    _replyTo;
  Set<String> _selected        = {};
  bool        _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(
          () => setState(() => _typing = _textCtrl.text.trim().isNotEmpty),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().openChat(widget.chat.id);
      context.read<ChatProvider>().markAsRead(widget.chat.id);
      FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
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

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _pickImage() async {
    final XFile? f = await _picker.pickImage(source: ImageSource.gallery);
    if (f == null || !mounted) return;
    context
        .read<ChatProvider>()
        .sendImage(widget.chat.id, f, widget.chat.name, context);
  }

  void _onLongPress(Message msg) {
    if (msg.id.startsWith('local_')) return;
    // ✅ FIX 2: faqat o'z xabarlarini select qilish mumkin
    final myId = context.read<ChatProvider>().currentUser?.id ?? '';
    if (msg.senderId != myId) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isSelectionMode = true;
      _selected = {msg.id};
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

  Future<void> _deleteSelected() async {
    final ids = List<String>.from(_selected);
    _cancelSelection();
    for (final id in ids) {
      await context
          .read<ChatProvider>()
          .deleteMessage(widget.chat.id, id, context);
    }
  }

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
      content: Text('Nusxa olindi'),
      duration: Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _onTap(Message msg, String myId) {
    if (_isSelectionMode) {
      // ✅ FIX 3: local_ xabarni select qilishga yo'l qo'yma
      if (!msg.id.startsWith('local_')) _toggleSelect(msg.id);
      return;
    }
    if (msg.senderId == myId &&
        !msg.isDeleted &&
        msg.type == MessageType.text &&
        !msg.id.startsWith('local_')) { // ✅ FIX 3: local_ xabarni tahrirlashga yo'l qo'yma
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.edit_rounded,
                      color: AppTheme.primary, size: 18),
                ),
                const SizedBox(width: 10),
                const Text('Xabarni tahrirlash',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
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
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                    const BorderSide(color: AppTheme.primary, width: 1.5),
                  ),
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
                    child: const Text('Bekor',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
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
                      final newText = ctrl.text.trim();
                      if (newText.isEmpty) return;
                      context.read<ChatProvider>().editMessage(
                          widget.chat.id, msg.id, newText, context);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Saqlash',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete() {
    final count = _selected.length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("$count ta xabarni o'chirish",
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        content: Text(
          '$count ta xabar barcha uchun o\'chiriladi.',
          style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Bekor',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteSelected();
            },
            child: const Text("O'chirish",
                style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w700)),
          ),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.chat.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const Text('Onlayn',
                  style: TextStyle(
                      color: AppTheme.online, fontSize: 11)),
            ],
          ),
        ),
      ]),
      actions: [
        IconButton(
            icon: const Icon(Icons.videocam_outlined,
                color: AppTheme.textSecondary),
            onPressed: () {}),
        IconButton(
            icon: const Icon(Icons.call_outlined,
                color: AppTheme.textSecondary),
            onPressed: () {}),
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
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600),
        ),
      ),
      actions: [
        if (_selected.length == 1)
          IconButton(
            tooltip: 'Nusxa olish',
            icon: const Icon(Icons.copy_rounded,
                color: AppTheme.textSecondary),
            onPressed: _copySelected,
          ),
        IconButton(
          tooltip: "O'chirish",
          icon:    const Icon(Icons.delete_outline_rounded,
              color: Colors.redAccent),
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
      onPopInvokedWithResult: (didPop, _) {
        if (_isSelectionMode) _cancelSelection();
        if (didPop) context.read<ChatProvider>().closeChat();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: _isSelectionMode ? _selectionAppBar() : _normalAppBar(),
        body: Column(children: [

          Expanded(
            child: msgs.isEmpty
                ? const _EmptyChat()
                : ListView.builder(
              controller: _scrollCtrl,
              reverse:    true,
              padding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 8),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final index  = msgs.length - 1 - i;
                final msg    = msgs[index];
                final isMine = msg.senderId == myId;

                return _SwipeableMessage(
                  key:     ValueKey(msg.id),
                  isMine:  isMine,
                  // ✅ FIX 3: local_ xabarni swipe/select dan bloklash
                  enabled: !_isSelectionMode && !msg.isDeleted && !msg.id.startsWith('local_'),
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

          if (_replyTo != null)
            _ReplyBar(
              message:  _replyTo!,
              onCancel: () => setState(() => _replyTo = null),
            ),

          _InputBar(
            controller:  _textCtrl,
            focusNode:   _focusNode,
            isTyping:    _typing,
            onSend:      _send,
            onPickImage: _pickImage,
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Swipe-to-reply wrapper
// ═══════════════════════════════════════════════════════════════════════════════
class _SwipeableMessage extends StatefulWidget {
  final Widget        child;
  final bool          isMine;
  final bool          enabled;
  final VoidCallback  onSwipe;

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
      child: Stack(
        children: [
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
        ],
      ),
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
    return Container(
      color:   AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(children: [
        // Chiziq
        Container(
          width: 3, height: 52,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        // ✅ FIX 1: rasm bo'lsa thumbnail ko'rsatish
        if (isImage) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              message.content,
              width: 44, height: 44,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 44, height: 44,
                color: AppTheme.surfaceLight,
                child: const Icon(Icons.image_rounded,
                    color: AppTheme.textSecondary, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(message.senderName,
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                isImage ? '📷 Rasm' : message.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded,
              color: AppTheme.textSecondary, size: 20),
          onPressed: onCancel,
        ),
      ]),
    );
  }
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

  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.isTyping,
    required this.onSend,
    required this.onPickImage,
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
              focusNode:  focusNode,
              controller: controller,
              maxLines:   null,
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
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
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
            child: _CircleBtn(
              key:       ValueKey(isTyping),
              icon:      isTyping ? Icons.send_rounded : Icons.mic_rounded,
              isPrimary: true,
              onTap:     isTyping ? onSend : () {},
            ),
          ),
        ),
      ]),
    );
  }
}

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
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          color:  isPrimary ? AppTheme.primary : AppTheme.surfaceLight,
          shape:  BoxShape.circle,
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
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline_rounded,
              size: 56, color: AppTheme.textSecondary),
          SizedBox(height: 12),
          Text("Hali xabarlar yo'q",
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          SizedBox(height: 6),
          Text('Birinchi xabarni yuboring 👋',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}