import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/providers/ChatProvider.dart';
import 'package:chatapp/services/WebSocketService.dart';
import 'package:chatapp/theme/AppTheme.dart';
import 'package:chatapp/widgets/AvatarWidget.dart';
import 'package:chatapp/screen/ChatScreen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(children: [
          _Header(),
          _SearchBar(),
          const Expanded(child: _ChatList()),
        ]),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primary,
        onPressed: () => _showNewChatSheet(context),
        child: const Icon(Icons.edit_outlined, color: Colors.white),
      ),
    );
  }

  void _showNewChatSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<ChatProvider>(),
        child: _NewChatSheet(),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user     = context.watch<ChatProvider>().currentUser;
    final wsStatus = context.watch<WebSocketService>().status;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(children: [
        AvatarWidget(name: user?.name ?? 'U', size: 42, isOnline: true),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user?.name ?? '',
                style: const TextStyle(color: AppTheme.textPrimary,
                    fontSize: 17, fontWeight: FontWeight.w700)),
            Row(children: [
              Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  color: wsStatus == WsStatus.connected
                      ? AppTheme.online : AppTheme.offline,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                wsStatus == WsStatus.connected ? 'Ulangan' : 'Ulanmoqda...',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ]),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: AppTheme.textSecondary),
          onPressed: () {},
        ),
      ]),
    );
  }
}

class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
    child: TextField(
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        hintText: 'Qidirish...',
        prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary, size: 20),
        filled: true,
        fillColor: AppTheme.surfaceLight,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    ),
  );
}

class _ChatList extends StatelessWidget {
  const _ChatList();

  @override
  Widget build(BuildContext context) {
    final chats = context.watch<ChatProvider>().chats;
    if (chats.isEmpty) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.chat_bubble_outline, size: 60, color: AppTheme.textSecondary),
          SizedBox(height: 14),
          Text('Hali chatlar yo\'q',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
          SizedBox(height: 6),
          Text('+ tugmasini bosib boshlang',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 80),
      itemCount: chats.length,
      itemBuilder: (_, i) => _ChatTile(chat: chats[i]),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final Chat chat;
  const _ChatTile({required this.chat});

  @override
  Widget build(BuildContext context) {
    final isGroup = chat.type == ChatType.group;
    final time    = _fmt(chat.lastMessageTime);

    return InkWell(
      onTap: () {
        context.read<ChatProvider>().openChat(chat.id);
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(children: [
          Stack(children: [
            AvatarWidget(name: chat.name, size: 52, isGroup: isGroup, isOnline: !isGroup),
            if (!isGroup)
              Positioned(
                bottom: 2, right: 2,
                child: Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    color: AppTheme.online, shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.background, width: 2),
                  ),
                ),
              ),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(chat.name,
                      style: const TextStyle(color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600, fontSize: 15),
                      overflow: TextOverflow.ellipsis),
                ),
                Text(time,
                    style: TextStyle(
                      fontSize: 12,
                      color: chat.unreadCount > 0
                          ? AppTheme.primary : AppTheme.textSecondary,
                    )),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Text(chat.lastMessage ?? 'Xabar yo\'q',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      overflow: TextOverflow.ellipsis, maxLines: 1),
                ),
                if (chat.unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text('${chat.unreadCount}',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '';
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'Hozir';
    if (d.inHours   < 1) return '${d.inMinutes}d';
    if (d.inDays    < 1) return '${d.inHours}s';
    return '${d.inDays}k';
  }
}

class _NewChatSheet extends StatelessWidget {
  final _nameCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Yangi chat',
                style: TextStyle(color: AppTheme.textPrimary,
                    fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Ism yoki guruh nomi',
                prefixIcon: Icon(Icons.person_add_outlined, color: AppTheme.primary),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _Btn(
                icon: Icons.person_outline, label: 'Shaxsiy',
                onTap: () {
                  final name = _nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  final fakeUser = User(
                      id: 'u_${DateTime.now().millisecondsSinceEpoch}', name: name);
                  final chat = context.read<ChatProvider>().newPersonal(fakeUser);
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
                },
              )),
              const SizedBox(width: 12),
              Expanded(child: _Btn(
                icon: Icons.group_outlined, label: 'Guruh', accent: true,
                onTap: () {
                  final name = _nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  final chat = context.read<ChatProvider>().newGroup(name, []);
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
                },
              )),
            ]),
          ]),
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final VoidCallback onTap;
  final bool accent;
  const _Btn({required this.icon, required this.label,
    required this.onTap, this.accent = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: accent
            ? AppTheme.accent.withOpacity(.12) : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: accent ? AppTheme.accent : AppTheme.primary, width: 1.5),
      ),
      child: Column(children: [
        Icon(icon, color: accent ? AppTheme.accent : AppTheme.primary),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                color: accent ? AppTheme.accent : AppTheme.primary,
                fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}