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
  final _picker = ImagePicker();
  bool _typing = false;
  int _oldMsgCount = 0;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(() => setState(() => _typing = _textCtrl.text.trim().isNotEmpty));
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom(isAnimated: false));
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _toBottom({bool isAnimated = true}) {
    if (!mounted || !_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    isAnimated
        ? _scrollCtrl.animateTo(max, duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
        : _scrollCtrl.jumpTo(max);
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

    // ChatProvider'ga 'path' emas, 'XFile' ni yuboring
    context.read<ChatProvider>().sendImage(widget.chat.id, pickedFile as XFile, widget.chat.name, context);
  }
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final msgs = provider.messages(widget.chat.id);
    final myId = provider.currentUser?.id ?? '';
    final isGroup = widget.chat.type == ChatType.group;

    if (msgs.length != _oldMsgCount) {
      _oldMsgCount = msgs.length;
      _toBottom(isAnimated: true);
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          AvatarWidget(name: widget.chat.name, size: 36, isGroup: isGroup),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.chat.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const Text("Onlayn", style: TextStyle(fontSize: 11, color: Colors.greenAccent)),
          ]),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: msgs.isEmpty
              ? const Center(child: Text("Hozircha xabarlar yo'q", style: TextStyle(color: Colors.grey)))
              : ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            itemCount: msgs.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: MessageBubble(
                message: msgs[i],
                isMine: msgs[i].senderId == myId,
                showSenderName: isGroup && msgs[i].senderId != myId,
              ),
            ),
          ),
        ),
        _InputBar(controller: _textCtrl, isTyping: _typing, onSend: _send, onPickImage: _pickImage),
      ]),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isTyping;
  final VoidCallback onSend;
  final VoidCallback onPickImage;

  const _InputBar({required this.controller, required this.isTyping, required this.onSend, required this.onPickImage});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      padding: EdgeInsets.fromLTRB(8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        IconButton(icon: const Icon(Icons.add, color: Colors.white70), onPressed: onPickImage),
        Expanded(
          child: TextField(
            controller: controller,
            maxLines: 5, minLines: 1,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Xabar yozing...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              filled: true,
              fillColor: AppTheme.surfaceLight,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onSend,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
            child: Icon(isTyping ? Icons.send : Icons.mic, color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }
}