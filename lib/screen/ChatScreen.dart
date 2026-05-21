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

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  final _picker = ImagePicker();
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(() => setState(() => _typing = _textCtrl.text.trim().isNotEmpty));

    // Chatga kirganda klaviaturani avtomatik ochish
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
      // O'qilgan deb belgilash
      context.read<ChatProvider>().markAsRead(widget.chat.id);
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
    context.read<ChatProvider>().sendText(widget.chat.id, text, widget.chat.name, context);
    _textCtrl.clear();
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null || !mounted) return;
    context.read<ChatProvider>().sendImage(widget.chat.id, pickedFile, widget.chat.name, context);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final msgs = provider.messages(widget.chat.id);
    final myId = provider.currentUser?.id ?? '';
    final isGroup = widget.chat.type == ChatType.group;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: Row(children: [
          AvatarWidget(name: widget.chat.name, size: 36, isGroup: isGroup),
          const SizedBox(width: 12),
          Text(widget.chat.name, style: const TextStyle(color: Colors.white)),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            reverse: true, // Eng oxirgi xabarlar doim pastda turadi
            padding: const EdgeInsets.all(10),
            itemCount: msgs.length,
            itemBuilder: (_, i) {
              // reverse: true bo'lgani uchun teskari tartibda chiqaramiz
              final index = msgs.length - 1 - i;
              return MessageBubble(
                message: msgs[index],
                isMine: msgs[index].senderId == myId,
                showSenderName: isGroup && msgs[index].senderId != myId,
              );
            },
          ),
        ),
        _InputBar(
          controller: _textCtrl,
          focusNode: _focusNode,
          isTyping: _typing,
          onSend: _send,
          onPickImage: _pickImage,
        ),
      ]),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isTyping;
  final VoidCallback onSend;
  final VoidCallback onPickImage;

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
      color: AppTheme.background,
      padding: EdgeInsets.fromLTRB(8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.add, color: Colors.white70), onPressed: onPickImage),
        Expanded(
          child: TextField(
            focusNode: focusNode,
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Xabar yozing...',
              filled: true,
              fillColor: AppTheme.surfaceLight,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onSend,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
            child: Icon(isTyping ? Icons.send : Icons.mic, color: Colors.white),
          ),
        ),
      ]),
    );
  }
}