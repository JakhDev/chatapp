import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/providers/ChatProvider.dart';
import 'package:chatapp/theme/AppTheme.dart';
import 'package:chatapp/widgets/AvatarWidget.dart';
import 'package:chatapp/widgets/MessageBuble.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;
  const ChatScreen({super.key, required this.chat});

  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl   = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker     = ImagePicker();
  bool  _typing     = false;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(
            () => setState(() => _typing = _textCtrl.text.trim().isNotEmpty));
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    context.read<ChatProvider>().sendText(widget.chat.id, text);
    _textCtrl.clear();
    _toBottom();
  }

  Future<void> _pickImage() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: AppTheme.primary),
            title: const Text('Kamera', style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: AppTheme.accent),
            title: const Text('Galereya', style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (src == null) return;
    final file = await _picker.pickImage(source: src, imageQuality: 80);
    if (file == null || !mounted) return;
    context.read<ChatProvider>().sendImage(widget.chat.id, file.path);
    _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider  = context.watch<ChatProvider>();
    final msgs      = provider.messages(widget.chat.id);
    final myId      = provider.currentUser?.id ?? '';
    final isGroup   = widget.chat.type == ChatType.group;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: AppTheme.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(children: [
          AvatarWidget(name: widget.chat.name, size: 38, isGroup: isGroup),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.chat.name,
                  style: const TextStyle(color: AppTheme.textPrimary,
                      fontSize: 15, fontWeight: FontWeight.w700)),
              Text(
                isGroup
                    ? '${widget.chat.memberIds.length} a\'zo'
                    : 'Onlayn',
                style: const TextStyle(color: AppTheme.online, fontSize: 11),
              ),
            ]),
          ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_outlined, color: AppTheme.textSecondary),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.call_outlined, color: AppTheme.textSecondary),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(children: [
        // ── Messages ──
        Expanded(
          child: msgs.isEmpty
              ? const _EmptyChat()
              : ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: msgs.length,
            itemBuilder: (_, i) {
              final msg    = msgs[i];
              final isMine = msg.senderId == myId || msg.senderId == 'me';
              final showName = isGroup && !isMine &&
                  (i == 0 || msgs[i - 1].senderId != msg.senderId);
              return MessageBubble(
                  message: msg, isMine: isMine, showSenderName: showName);
            },
          ),
        ),
        // ── Input bar ──
        _InputBar(
          controller:  _textCtrl,
          isTyping:    _typing,
          onSend:      _send,
          onPickImage: _pickImage,
        ),
      ]),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────
class _EmptyChat extends StatelessWidget {
  const _EmptyChat();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
            color: AppTheme.surfaceLight, shape: BoxShape.circle),
        child: const Icon(Icons.waving_hand_outlined,
            size: 38, color: AppTheme.primary),
      ),
      const SizedBox(height: 14),
      const Text('Salom deb yozing! 👋',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
    ]),
  );
}

// ── Input bar ─────────────────────────────────────────────────
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool           isTyping;
  final VoidCallback   onSend;
  final VoidCallback   onPickImage;

  const _InputBar({
    required this.controller,
    required this.isTyping,
    required this.onSend,
    required this.onPickImage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12, right: 12, top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.surfaceLight)),
      ),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.add_circle_outline,
              color: AppTheme.primary, size: 26),
          onPressed: onPickImage,
        ),
        Expanded(
          child: TextField(
            controller: controller,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
            maxLines: 4, minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Xabar yozing...',
              filled: true,
              fillColor: AppTheme.surfaceLight,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44, height: 44,
          decoration: BoxDecoration(
            gradient: isTyping
                ? const LinearGradient(colors: [AppTheme.primary, AppTheme.accent])
                : null,
            color:  isTyping ? null : AppTheme.surfaceLight,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(
              isTyping ? Icons.send_rounded : Icons.mic_outlined,
              color: isTyping ? Colors.white : AppTheme.textSecondary,
              size: 20,
            ),
            onPressed: isTyping ? onSend : () {},
          ),
        ),
      ]),
    );
  }
}