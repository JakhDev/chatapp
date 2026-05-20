import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/providers/ChatProvider.dart';
import 'package:chatapp/theme/AppTheme.dart';
import 'package:chatapp/widgets/AvatarWidget.dart';
import 'package:chatapp/widgets/MessageBuble.dart'; // Loyihadagi import fayl nomi

class ChatScreen extends StatefulWidget {
  final Chat chat;
  const ChatScreen({super.key, required this.chat});

  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();
  bool _typing = false;
  int _oldMsgCount = 0; // Yangi xabarlar kelganini solishtirish uchun profilaktika

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(
            () => setState(() => _typing = _textCtrl.text.trim().isNotEmpty));

    // Oyna ochilgandan 100ms keyin bazadan eski xabarlar yuklanib bo'lingach, eng pastga tushadi
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _toBottom(isAnimated: false);
      });
    });
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

    // To'g'ri tartib: chatId, text, chatName, context
    context.read<ChatProvider>().sendText(
      widget.chat.id,
      text,
      widget.chat.name, // Chatning haqiqiy ismi (Yozishma so'zini yo'qotish uchun)
      context,          // n harfi bilan to'g'ri yozilgan context
    );

    _textCtrl.clear();
    _toBottom(isAnimated: true);
  }

  Future<void> _pickImage() async {
    // Navigator.pop dan keladigan qiymatni xavfsiz olish
    final ImageSource? src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: AppTheme.primary),
            title: const Text('Kamera', style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: AppTheme.accent),
            title: const Text('Galereya', style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );

    if (src == null) return;
    final file = await _picker.pickImage(source: src, imageQuality: 80);
    if (file == null || !mounted) return;

    if (file != null) {
      // 🔥 TO'G'RI TARTIB: chatId, filePath, chatName, context
      context.read<ChatProvider>().sendImage(
        widget.chat.id,
        file.path,
        widget.chat.name, // Chatning haqiqiy ismi (Jakhongir M)
        context,          // n harfi bilan to'g'ri yozilgan context
      );
    }    _toBottom(isAnimated: true);
  }

  // Scrollni pastga tushirish funksiyasi mukammallashtirildi
  void _toBottom({bool isAnimated = true}) {
    if (!mounted || !_scrollCtrl.hasClients) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        final maxScroll = _scrollCtrl.position.maxScrollExtent;
        if (isAnimated) {
          _scrollCtrl.animateTo(
            maxScroll,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        } else {
          _scrollCtrl.jumpTo(maxScroll);
        }
      }
    });
  }

  // ── VAQTNI FORMATLASH FUNKSIYASI (HH:mm) ─────────────────────────────────
  String _formatMessageTime(DateTime dateTime) {
    // 🔥 .toLocal() orqali vaqtni qurilmaning (O'zbekiston) vaqt zonasiga o'giramiz
    final localTime = dateTime.toLocal();

    final hour = localTime.hour.toString().padLeft(2, '0');
    final minute = localTime.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final msgs = provider.messages(widget.chat.id);
    final myId = provider.currentUser?.id ?? '';
    final isGroup = widget.chat.type == ChatType.group;

    // 🔥 XAVFSIZ REALTIME SCROLL: Faqat yangi xabar kelgandagina pastga tushadi, cheksiz sikl bermaydi!
    if (msgs.length != _oldMsgCount) {
      _oldMsgCount = msgs.length;
      _toBottom(isAnimated: true);
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
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
                isGroup ? '${widget.chat.memberIds.length} a\'zo' : 'Onlayn',
                style: const TextStyle(color: AppTheme.online, fontSize: 11),
              ),
            ]),
          ),
        ]),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(children: [
          Expanded(
            child: msgs.isEmpty
                ? const _EmptyChat()
                : ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final msg = msgs[i];
                final isMine = msg.senderId == myId || msg.senderId == 'me';
                final showName = isGroup && !isMine &&
                    (i == 0 || msgs[i - 1].senderId != msg.senderId);

                // 🔥 XATOLIKDAN MUTLAQ HIMOYA (TRY-CATCH)
                // NoSuchMethodError bermasligi uchun xavfsiz tekshiramiz
                bool isMessageRead = false;
                try {
                  final dynamic dynamicMsg = msg;
                  isMessageRead = dynamicMsg.isRead == true ||
                      dynamicMsg.isSeen == true ||
                      dynamicMsg.seen == true;
                } catch (_) {
                  isMessageRead = false; // Agar modelda bunday maydon umuman bo'lmasa xato bermaydi
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Align(
                    alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        MessageBubble(
                            message: msg, isMine: isMine, showSenderName: showName),
                        const SizedBox(height: 2),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                            children: [
                              Text(
                                _formatMessageTime(msg.timestamp),
                                style: TextStyle(
                                  color: AppTheme.textSecondary.withOpacity(0.5),
                                  fontSize: 10,
                                ),
                              ),
                              // Faqat shaxsiy chatda va biz yuborgan xabarlarda galochka chiqadi
                              if (isMine && !isGroup) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  isMessageRead ? Icons.done_all_rounded : Icons.done_rounded,
                                  size: 14,
                                  color: isMessageRead ? AppTheme.online : AppTheme.textSecondary.withOpacity(0.4),
                                ),
                              ]
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          _InputBar(
            controller: _textCtrl,
            isTyping: _typing,
            onSend: _send,
            onPickImage: _pickImage,
          ),
        ]),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
            color: AppTheme.surfaceLight, shape: BoxShape.circle),
        child: const Icon(Icons.waving_hand_outlined, size: 38, color: AppTheme.primary),
      ),
      const SizedBox(height: 14),
      const Text('Salom deb yozing! 👋',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
    ]),
  );
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isTyping;
  final VoidCallback onSend;
  final VoidCallback onPickImage;

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
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary, size: 26),
            onPressed: onPickImage,
          ),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
            maxLines: 4,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
              hintText: 'Xabar yozing...',
              filled: true,
              fillColor: AppTheme.surfaceLight,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: isTyping
                  ? const LinearGradient(colors: [AppTheme.primary, AppTheme.accent])
                  : null,
              color: isTyping ? null : AppTheme.surfaceLight,
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
        ),
      ]),
    );
  }
}