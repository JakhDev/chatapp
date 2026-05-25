import 'dart:async';
import 'dart:ui';
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
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'FullScreenImage.dart';

String _fmtTime(DateTime dt) {
  return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class ChatScreen extends StatefulWidget {
  final Chat chat;
  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  final _picker = ImagePicker();
  final _audioSvc = AudioService();

  bool _typing = false;
  bool _showScrollButton = false;
  Message? _replyTo;
  Message? _editingMsg;
  Set<String> _selected = {};
  bool _isSelectionMode = false;
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordTimer;

  late final AnimationController _recordAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final AnimationController _recordRippleAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  late final AnimationController _inputHideAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    value: 1.0,
  );

  late final Animation<double> _inputFade = CurvedAnimation(
    parent: _inputHideAnim,
    curve: Curves.easeInOut,
  );

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(
          () => setState(() => _typing = _textCtrl.text.trim().isNotEmpty),
    );
    _scrollCtrl.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ChatProvider>();
      provider.openChat(widget.chat.id);
      provider.markAsRead(widget.chat.id);
      FocusScope.of(context).requestFocus(_focusNode);
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    });
  }

  void _onScroll() {
    final atBottom = _scrollCtrl.offset <= 100;
    if (_showScrollButton == atBottom) {
      setState(() => _showScrollButton = !atBottom);
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _recordAnim.dispose();
    _recordRippleAnim.dispose();
    _inputHideAnim.dispose();
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
      setState(() => _showScrollButton = false);
    }
  }

  void _send() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    if (_editingMsg != null) {
      context.read<ChatProvider>().editMessage(
        widget.chat.id,
        _editingMsg!.id,
        text,
        context,
      );
      _cancelEdit();
      return;
    }

    context.read<ChatProvider>().sendText(
      widget.chat.id,
      text,
      widget.chat.name,
      context,
      replyTo: _replyTo,
    );
    _textCtrl.clear();
    setState(() => _replyTo = null);
    _scrollToBottom();
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null || !mounted) return;
    context.read<ChatProvider>().sendImage(
      widget.chat.id,
      file,
      widget.chat.name,
      context,
    );
  }

  Future<void> _startAudioRecording() async {
    final ok = await _audioSvc.startRecording();
    if (!ok || !mounted) return;
    _inputHideAnim.reverse();
    _recordRippleAnim.repeat();
    setState(() {
      _isRecording = true;
      _recordingDuration = Duration.zero;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _recordingDuration += const Duration(seconds: 1));
      }
    });
  }

  Future<void> _stopAudioRecording() async {
    _recordTimer?.cancel();
    _recordRippleAnim.stop();
    _recordRippleAnim.reset();
    _inputHideAnim.forward();
    final path = await _audioSvc.stopRecording();
    setState(() => _isRecording = false);
    if (path == null || !mounted) return;

    context.read<ChatProvider>().sendAudio(
      widget.chat.id,
      path,
      widget.chat.name,
      context,
      widget.chat.name,
      audioDuration: _recordingDuration.inSeconds,
    );
    _scrollToBottom();
  }

  Future<void> _cancelAudioRecording() async {
    _recordTimer?.cancel();
    _recordRippleAnim.stop();
    _recordRippleAnim.reset();
    _inputHideAnim.forward();
    await _audioSvc.cancelRecording();
    setState(() {
      _isRecording = false;
      _recordingDuration = Duration.zero;
    });
  }

  void _onLongPress(Message msg) {
    if (msg.id.startsWith('local_') || msg.isDeleted) return;
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

  void _copySelected() {
    final msgs = context.read<ChatProvider>().messages(widget.chat.id);
    final texts = _selected
        .map((id) => msgs.firstWhere((m) => m.id == id, orElse: () => msgs.first))
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

  // FIX 1: deleteForEveryone=true bo'lsa BARCHA tanlangan xabarlar o'chadi
  // (sender kim bo'lishidan qat'iy nazar)
  Future<void> _deleteSelected({required bool deleteForEveryone}) async {
    final ids = List<String>.from(_selected);
    _cancelSelection();
    for (final id in ids) {
      await context.read<ChatProvider>().deleteMessage(
        widget.chat.id,
        id,
        context,
        deleteForEveryone: deleteForEveryone,
      );
    }
  }

  // FIX 1: Dialog — checkbox belgisi tanlangan bo'lsa ikkala user uchun o'chiradi
  void _confirmDelete() {
    final count = _selected.length;
    final c = AppColorsContext.of(context);
    // ✅ Default: checkbox BELGILANGAN (ikkala user uchun o'chirish)
    bool deleteForEveryone = true;

    // ✅ Other user nomi
    final provider = context.read<ChatProvider>();
    final myId = provider.currentUser?.id ?? '';
    final otherId = otherIdFromChatId(widget.chat.id, myId) ?? '';
    final otherUser = provider.allUsers
        .where((u) => u.id.toLowerCase() == otherId.toLowerCase())
        .firstOrNull;
    final otherName = otherUser?.name ?? widget.chat.name;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),

          // ── Sarlavha ──────────────────────────────────────────────────────
          title: Text(
            "$count ta xabarni o'chirish",
            style: TextStyle(color: c.textPrimary,
                fontSize: 16, fontWeight: FontWeight.w700),
          ),

          // ── Kontent ───────────────────────────────────────────────────────
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Haqiqatan ham bu xabarni o'chirib tashlamoqchimisiz?",
                style: TextStyle(color: c.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 16),

              // ── Checkbox row ──────────────────────────────────────────────
              // ✅ Row bosish ham checkbox ni toggle qiladi
              InkWell(
                onTap: () => setDialogState(
                        () => deleteForEveryone = !deleteForEveryone),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      // ✅ Telegram uslubi checkbox
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          color: deleteForEveryone
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: deleteForEveryone
                                ? AppColors.primary
                                : c.textSecondary,
                            width: 2,
                          ),
                        ),
                        child: deleteForEveryone
                            ? const Icon(Icons.check,
                            color: Colors.white, size: 14)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          // ✅ Other user nomi ko'rsatiladi
                          '$otherName uchun ham o\'chirilsin',
                          style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── Actions ───────────────────────────────────────────────────────
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Bekor qilish',
                  style: TextStyle(color: c.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _deleteSelected(deleteForEveryone: deleteForEveryone);
              },
              child: const Text("O'chirish",
                  style: TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
  void _onTap(Message msg, String myId) {
    if (_isSelectionMode) {
      if (!msg.id.startsWith('local_') && !msg.isDeleted) {
        _toggleSelect(msg.id);
      }
      return;
    }
    if (msg.senderId == myId &&
        !msg.isDeleted &&
        msg.type == MessageType.text &&
        !msg.id.startsWith('local_')) {
      _startEdit(msg);
    }
  }

  void _startEdit(Message msg) {
    setState(() {
      _editingMsg = msg;
      _replyTo = null;
      _textCtrl.text = msg.content;
    });
    Future.delayed(const Duration(milliseconds: 50), () {
      _textCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: msg.content.length),
      );
      _focusNode.requestFocus();
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingMsg = null;
      _textCtrl.clear();
    });
    _focusNode.unfocus();
  }

  void _showFullScreenImage(String imagePath) {
    final provider = context.read<ChatProvider>();
    final msgs = provider
        .messages(widget.chat.id)
        .where((m) => !m.isDeleted && m.type == MessageType.image)
        .toList();
    final imageUrls = msgs.map((m) => _extractImageUrl(m.content)).toList();
    final index = imageUrls.indexOf(imagePath);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenImage(
          imageUrls: imageUrls,
          initialIndex: index < 0 ? 0 : index,
        ),
      ),
    );
  }

  String _extractImageUrl(String content) {
    if (content.startsWith('http')) return content;
    return content;
  }

  void _showMoreMenu() {
    final c = AppColorsContext.of(context);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.3),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5 * anim.value, sigmaY: 5 * anim.value),
        child: Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(color: Colors.transparent),
            ),
            Positioned(
              top: kToolbarHeight + MediaQuery.of(ctx).padding.top + 4,
              right: 12,
              child: ScaleTransition(
                scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                child: Opacity(
                  opacity: anim.value,
                  child: Material(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                    elevation: 8,
                    child: Container(
                      width: 220,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _menuItem(
                            icon: Icons.delete_sweep_outlined,
                            title: "Chatni tozalash",
                            color: Colors.redAccent,
                            onTap: () {
                              Navigator.pop(ctx);
                              _confirmClearHistory();
                            },
                          ),
                        ],
                      ),
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

  Widget _menuItem({
    required IconData icon,
    required String title,
    Color? color,
    VoidCallback? onTap,
  }) {
    final c = AppColorsContext.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color ?? c.textPrimary),
            const SizedBox(width: 12),
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    color: color ?? c.textPrimary,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  void _confirmClearHistory() {
    final c = AppColorsContext.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Chat tarixini tozalash?",
            style:
            TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text("Barcha xabarlar o'chiriladi.",
            style: TextStyle(color: c.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Bekor qilish', style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<ChatProvider>().clearChatHistory(widget.chat.id, context);
            },
            child: const Text("O'chirish",
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _normalAppBar() {
    final c = AppColorsContext.of(context);
    final isGroup = widget.chat.type == ChatType.group;
    final provider = context.read<ChatProvider>();
    final myId = provider.currentUser?.id ?? '';
    final otherId = otherIdFromChatId(widget.chat.id, myId) ?? '';
    final isOnline = provider.isUserOnline(otherId);
    final lastSeen = provider.getLastSeen(otherId);

    final otherUser = isGroup
        ? null
        : provider.allUsers
        .where((u) => u.id.toLowerCase() == otherId.toLowerCase())
        .firstOrNull;

    // FIX 2: avatarUrl — Google photo support
    final avatarUrl = otherUser?.avatarUrl ?? widget.chat.avatarUrl;

    return AppBar(
      backgroundColor: c.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: c.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: GestureDetector(
        onTap: otherUser != null && !isGroup
            ? () => _showUserProfile(otherUser, c)
            : null,
        child: Row(
          children: [
            _ChatAvatar(
              chat: widget.chat,
              provider: provider,
              isGroup: isGroup,
              otherId: otherId,
              isOnline: isOnline,
              avatarUrl: avatarUrl,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.chat.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                  if (!isGroup)
                    _OnlineStatus(isOnline: isOnline, lastSeen: lastSeen)
                  else
                    Text(
                      "${widget.chat.memberIds.length} a'zo",
                      style: TextStyle(color: c.textSecondary, fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: "Batafsil",
          icon: Icon(Icons.more_vert_rounded, color: c.textSecondary),
          onPressed: _showMoreMenu,
        ),
      ],
    );
  }

  // FIX 3: User profile dialog — email va ID ham ko'rinsin
  void _showUserProfile(User user, ThemeColors c) {
    final sbUser = sb.Supabase.instance.client.auth.currentUser;
    // otherId uchun email yo'q (faqat o'zimiznikini bilamiz),
    // shuning uchun email faqat currentUser uchun
    final provider = context.read<ChatProvider>();
    final myId = provider.currentUser?.id ?? '';
    final otherId = otherIdFromChatId(widget.chat.id, myId) ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar — Google photo support
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(80),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                  ? ClipOval(
                child: Image.network(
                  user.avatarUrl!,
                  fit: BoxFit.cover,
                  width: 80,
                  height: 80,
                  errorBuilder: (_, __, ___) => _initials(user.name),
                ),
              )
                  : _initials(user.name),
            ),
            const SizedBox(height: 16),
            // Name
            Text(
              user.name,
              style: TextStyle(
                  color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            // Online status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(30),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    color: context.watch<ChatProvider>().isUserOnline(user.id)
                        ? Colors.greenAccent
                        : Colors.grey,
                    size: 8,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    context.watch<ChatProvider>().isUserOnline(user.id)
                        ? 'Onlayn'
                        : 'Oflayn',
                    style: TextStyle(
                        color: context.watch<ChatProvider>().isUserOnline(user.id)
                            ? AppColors.online
                            : c.textSecondary,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // FIX 3: ID ma'lumotini ko'rsatish
            _profileInfoRow(
              icon: Icons.fingerprint_rounded,
              label: 'ID',
              value: user.id.length >= 8
                  ? user.id.substring(0, 8).toUpperCase()
                  : user.id.toUpperCase(),
              c: c,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Yopish',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _profileInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required ThemeColors c,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(color: c.textSecondary, fontSize: 11)),
              Text(value,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _initials(String name) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
            color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
      ),
    );
  }

  PreferredSizeWidget _selectionAppBar() {
    final c = AppColorsContext.of(context);
    return AppBar(
      backgroundColor: c.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: Icon(Icons.close_rounded, color: c.textPrimary),
        onPressed: _cancelSelection,
      ),
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: Text(
          '${_selected.length} ta tanlandi',
          key: ValueKey(_selected.length),
          style: TextStyle(
              color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      actions: [
        if (_selected.length == 1)
          IconButton(
            tooltip: 'Nusxa olish',
            icon: Icon(Icons.copy_rounded, color: c.textSecondary),
            onPressed: _copySelected,
          ),
        IconButton(
          tooltip: "O'chirish",
          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
          onPressed: _confirmDelete,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsContext.of(context);
    final provider = context.watch<ChatProvider>();
    final myId = provider.currentUser?.id ?? '';
    final isGroup = widget.chat.type == ChatType.group;
    final msgs = provider
        .messages(widget.chat.id)
        .where((m) => !m.isDeleted)
        .toList();

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (_isSelectionMode) {
          _cancelSelection();
          return;
        }
        if (didPop) context.read<ChatProvider>().closeChat();
      },
      child: Scaffold(
        backgroundColor: c.background,
        appBar: _isSelectionMode ? _selectionAppBar() : _normalAppBar(),
        body: Column(
          children: [
            Expanded(
              child: msgs.isEmpty
                  ? _EmptyChat(c: c)
                  : Stack(
                children: [
                  ListView.builder(
                    controller: _scrollCtrl,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 8),
                    itemCount: msgs.length,
                    itemBuilder: (_, i) {
                      final index = msgs.length - 1 - i;
                      final msg = msgs[index];
                      final isMine = msg.senderId == myId;
                      final canSwipe = !_isSelectionMode &&
                          !msg.isDeleted &&
                          !msg.id.startsWith('local_');
                      final showDate = index == 0 ||
                          !_isSameDay(
                              msg.timestamp, msgs[index - 1].timestamp);

                      return Column(
                        children: [
                          if (showDate)
                            _DateSeparator(date: msg.timestamp, c: c),
                          _SwipeableMessage(
                            key: ValueKey(msg.id),
                            isMine: isMine,
                            enabled: canSwipe,
                            onSwipe: () => setState(() => _replyTo = msg),
                            child: MessageBubble(
                              message: msg,
                              isMine: isMine,
                              showSenderName: isGroup && !isMine,
                              isSelected: _selected.contains(msg.id),
                              isSelectionMode: _isSelectionMode,
                              onTap: () => _onTap(msg, myId),
                              onLongPress: () => _onLongPress(msg),
                              onImageTap: _showFullScreenImage,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: AnimatedScale(
                      scale: _showScrollButton ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: FloatingActionButton(
                        mini: true,
                        backgroundColor: AppColors.primary,
                        onPressed: _scrollToBottom,
                        child: const Icon(Icons.arrow_downward_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_editingMsg != null)
              _EditBanner(message: _editingMsg!, onCancel: _cancelEdit, c: c),
            if (_replyTo != null && _editingMsg == null)
              _ReplyBar(
                message: _replyTo!,
                onCancel: () => setState(() => _replyTo = null),
                c: c,
              ),
            _InputBar(
              controller: _textCtrl,
              focusNode: _focusNode,
              isTyping: _typing,
              isEditing: _editingMsg != null,
              isRecording: _isRecording,
              recordingDuration: _recordingDuration,
              recordAnimation: _recordAnim,
              recordRippleAnim: _recordRippleAnim,
              inputFade: _inputFade,
              onSend: _send,
              onPickImage: _pickImage,
              onStartRecording: _startAudioRecording,
              onStopRecording: _stopAudioRecording,
              onCancelRecording: _cancelAudioRecording,
              c: c,
            ),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Chat avatar — Google photo support
// ─────────────────────────────────────────────────────────────────────────────
class _ChatAvatar extends StatelessWidget {
  final Chat chat;
  final ChatProvider provider;
  final bool isGroup;
  final String otherId;
  final bool isOnline;
  final String? avatarUrl;

  const _ChatAvatar({
    required this.chat,
    required this.provider,
    required this.isGroup,
    required this.otherId,
    required this.isOnline,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorsContext.of(context);

    return Stack(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withAlpha(80),
          ),
          // FIX 2: Google avatar URL ni ko'rsatish
          child: avatarUrl != null && avatarUrl!.isNotEmpty
              ? ClipOval(
            child: Image.network(
              avatarUrl!,
              fit: BoxFit.cover,
              width: 38,
              height: 38,
              errorBuilder: (_, __, ___) => _initials(chat.name, isGroup),
            ),
          )
              : _initials(chat.name, isGroup),
        ),
        if (!isGroup && isOnline)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.online,
                shape: BoxShape.circle,
                border: Border.all(color: c.background, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }

  Widget _initials(String name, bool isGroup) {
    return Center(
      child: isGroup
          ? const Icon(Icons.group_rounded, color: Colors.white, size: 20)
          : Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Online status
// ─────────────────────────────────────────────────────────────────────────────
class _OnlineStatus extends StatelessWidget {
  final bool isOnline;
  final DateTime? lastSeen;
  const _OnlineStatus({required this.isOnline, this.lastSeen});

  String _formatLastSeen(DateTime utc) {
    final uzb = utc.add(const Duration(hours: 5));
    final now = DateTime.now().toUtc().add(const Duration(hours: 5));
    final diff = now.difference(uzb);
    if (diff.inMinutes < 1) return 'Hozirgina';
    if (diff.inMinutes < 60) return '${diff.inMinutes} daqiqa oldin';
    if (diff.inHours < 24) return '${diff.inHours} soat oldin';
    if (diff.inDays < 7) return '${diff.inDays} kun oldin';
    return '${uzb.day.toString().padLeft(2, '0')}.${uzb.month.toString().padLeft(2, '0')}.${uzb.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (isOnline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration:
            const BoxDecoration(color: AppColors.online, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          const Text('Onlayn',
              style: TextStyle(color: AppColors.online, fontSize: 11)),
        ],
      );
    }
    if (lastSeen != null) {
      return Text(
        _formatLastSeen(lastSeen!),
        style: TextStyle(
            color: AppColorsContext.of(context).textSecondary, fontSize: 11),
      );
    }
    return Text('Oflayn',
        style: TextStyle(
            color: AppColorsContext.of(context).textSecondary, fontSize: 11));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Date separator
// ─────────────────────────────────────────────────────────────────────────────
class _DateSeparator extends StatelessWidget {
  final DateTime date;
  final ThemeColors c;
  const _DateSeparator({required this.date, required this.c});

  String _format() {
    final t = date;
    final now = DateTime.now().toUtc().add(const Duration(hours: 5));
    final yest = now.subtract(const Duration(days: 1));
    if (_same(t, now)) return 'Bugun';
    if (_same(t, yest)) return 'Kecha';
    if (t.year == now.year) {
      const m = [
        '',
        'Yanvar',
        'Fevral',
        'Mart',
        'Aprel',
        'May',
        'Iyun',
        'Iyul',
        'Avgust',
        'Sentabr',
        'Oktabr',
        'Noyabr',
        'Dekabr'
      ];
      return '${t.day} ${m[t.month]}';
    }
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
  }

  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: c.surfaceLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(_format(),
            style: TextStyle(
                color: c.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Swipeable message
// ─────────────────────────────────────────────────────────────────────────────
class _SwipeableMessage extends StatefulWidget {
  final Widget child;
  final bool isMine;
  final bool enabled;
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
  double _drag = 0;
  bool _triggered = false;

  static const double _threshold = 64;
  static const double _maxDrag = 80;

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
    _drag = 0;
    _triggered = false;
  });

  @override
  Widget build(BuildContext context) {
    final progress = (_drag / _threshold).clamp(0.0, 1.0);
    return GestureDetector(
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      child: Stack(
        children: [
          Positioned(
            left: widget.isMine ? null : 10,
            right: widget.isMine ? 10 : null,
            top: 0,
            bottom: 0,
            child: Opacity(
              opacity: progress,
              child: Transform.scale(
                scale: 0.5 + 0.5 * progress,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.reply_rounded,
                      color: AppColors.primary, size: 18),
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration: _drag == 0 ? const Duration(milliseconds: 200) : Duration.zero,
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_drag, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reply bar
// ─────────────────────────────────────────────────────────────────────────────
class _ReplyBar extends StatelessWidget {
  final Message message;
  final VoidCallback onCancel;
  final ThemeColors c;

  const _ReplyBar({required this.message, required this.onCancel, required this.c});

  @override
  Widget build(BuildContext context) {
    final isImage = message.type == MessageType.image;
    final isAudio = message.type == MessageType.audio;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.surfaceLight)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message.senderName,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  isImage ? '📷 Rasm' : isAudio ? '🎤 Audio' : message.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: c.textSecondary, size: 18),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Empty chat
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyChat extends StatelessWidget {
  final ThemeColors c;
  const _EmptyChat({required this.c});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.chat_bubble_outline_rounded, size: 56, color: c.textSecondary),
        const SizedBox(height: 12),
        Text("Hali xabarlar yo'q",
            style: TextStyle(color: c.textSecondary, fontSize: 14)),
        const SizedBox(height: 6),
        Text('Birinchi xabarni yuboring 👋',
            style: TextStyle(color: c.textSecondary, fontSize: 12)),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Input bar
// ─────────────────────────────────────────────────────────────────────────────
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isTyping;
  final bool isEditing;
  final bool isRecording;
  final Duration recordingDuration;
  final AnimationController recordAnimation;
  final AnimationController recordRippleAnim;
  final Animation<double> inputFade;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onCancelRecording;
  final ThemeColors c;

  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.isTyping,
    required this.isEditing,
    required this.isRecording,
    required this.recordingDuration,
    required this.recordAnimation,
    required this.recordRippleAnim,
    required this.inputFade,
    required this.onSend,
    required this.onPickImage,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onCancelRecording,
    required this.c,
  });

  @override
  Widget build(BuildContext context) => Container(
    color: c.background,
    padding: EdgeInsets.fromLTRB(
        8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position:
          Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
              .animate(anim),
          child: child,
        ),
      ),
      child: isRecording
          ? _RecordingBar(
        key: const ValueKey('rec'),
        duration: recordingDuration,
        onStop: onStopRecording,
        onCancel: onCancelRecording,
        animation: recordAnimation,
        rippleAnim: recordRippleAnim,
        c: c,
      )
          : _NormalBar(
        key: const ValueKey('normal'),
        controller: controller,
        focusNode: focusNode,
        isTyping: isTyping,
        isEditing: isEditing,
        inputFade: inputFade,
        onSend: onSend,
        onPickImage: onPickImage,
        onStartRec: onStartRecording,
        c: c,
      ),
    ),
  );
}

class _NormalBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isTyping;
  final bool isEditing;
  final Animation<double> inputFade;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final VoidCallback onStartRec;
  final ThemeColors c;

  const _NormalBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isTyping,
    required this.isEditing,
    required this.inputFade,
    required this.onSend,
    required this.onPickImage,
    required this.onStartRec,
    required this.c,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      if (!isEditing)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: _CircleBtn(icon: Icons.add_rounded, onTap: onPickImage, c: c),
        ),
      const SizedBox(width: 8),
      Expanded(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 120),
          child: TextField(
            focusNode: focusNode,
            controller: controller,
            maxLines: null,
            textInputAction: TextInputAction.newline,
            style: TextStyle(color: c.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: isEditing ? 'Xabarni tahrirlash...' : 'Xabar yozing...',
              hintStyle: TextStyle(color: c.textSecondary),
              filled: true,
              fillColor: c.surfaceLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: _CircleBtn(
          icon: isTyping || isEditing ? Icons.send_rounded : Icons.mic_rounded,
          isPrimary: true,
          onTap: isTyping || isEditing ? onSend : onStartRec,
          c: c,
        ),
      ),
    ],
  );
}

class _RecordingBar extends StatelessWidget {
  final Duration duration;
  final VoidCallback onStop;
  final VoidCallback onCancel;
  final AnimationController animation;
  final AnimationController rippleAnim;
  final ThemeColors c;

  const _RecordingBar({
    super.key,
    required this.duration,
    required this.onStop,
    required this.onCancel,
    required this.animation,
    required this.rippleAnim,
    required this.c,
  });

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      GestureDetector(
        onTap: onCancel,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
              color: Colors.red.withAlpha(200), shape: BoxShape.circle),
          child: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: c.surfaceLight,
            borderRadius: BorderRadius.circular(23),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: rippleAnim,
                      builder: (_, __) => Transform.scale(
                        scale: 1.0 + 0.8 * rippleAnim.value,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red
                                .withOpacity(0.3 * (1 - rippleAnim.value)),
                          ),
                        ),
                      ),
                    ),
                    AnimatedBuilder(
                      animation: animation,
                      builder: (_, __) => Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.red
                              .withOpacity(0.6 + 0.4 * animation.value),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(_fmt(duration),
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('Yozilmoqda...',
                  style: TextStyle(color: c.textSecondary, fontSize: 14)),
            ],
          ),
        ),
      ),
      const SizedBox(width: 10),
      GestureDetector(
        onTap: onStop,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withAlpha(80),
                blurRadius: 12,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
        ),
      ),
    ],
  );
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;
  final ThemeColors c;

  const _CircleBtn({
    super.key,
    required this.icon,
    required this.onTap,
    required this.c,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: isPrimary ? AppColors.primary : c.surfaceLight,
        shape: BoxShape.circle,
        boxShadow: isPrimary
            ? [
          BoxShadow(
            color: AppColors.primary.withAlpha(80),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ]
            : null,
      ),
      child: Icon(
        icon,
        color: isPrimary ? Colors.white : c.textSecondary,
        size: 22,
      ),
    ),
  );
}

class _EditBanner extends StatelessWidget {
  final Message message;
  final VoidCallback onCancel;
  final ThemeColors c;

  const _EditBanner(
      {required this.message, required this.onCancel, required this.c});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
    decoration: BoxDecoration(
      color: c.surface,
      border: Border(top: BorderSide(color: c.surfaceLight)),
    ),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.edit_rounded,
              color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Xabarni tahrirlash',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 1),
              Text(message.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textSecondary, fontSize: 12)),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.close_rounded, color: c.textSecondary, size: 20),
          onPressed: onCancel,
        ),
      ],
    ),
  );
}