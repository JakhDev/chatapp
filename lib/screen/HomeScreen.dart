import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/providers/ChatProvider.dart';
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
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = context.watch<ChatProvider>().currentUser;

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
                decoration: const BoxDecoration(
                  color: AppTheme.online,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                'Onlayn',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ]),
          ]),
        ),

        // 👥 RO'YXATDAN O'TGAN USERLARNI KO'RISH TUGMASI
        IconButton(
          icon: const Icon(Icons.people_alt_outlined, color: AppTheme.primary),
          onPressed: () {
            // Oynani ochishdan oldin barcha userlarni bazadan yuklaymistan
            context.read<ChatProvider>().loadAllUsers();

            showModalBottomSheet(
              context: context,
              backgroundColor: AppTheme.surface,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              builder: (_) => ChangeNotifierProvider.value(
                value: context.read<ChatProvider>(),
                child: const _UserListSheet(),
              ),
            );
          },
        ),

        // 🚪 CHIQISH (LOGOUT) TUGMASI
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppTheme.surface,
                title: const Text("Chiqish", style: TextStyle(color: AppTheme.textPrimary)),
                content: const Text("Dasturdan chiqmoqchimisiz?", style: TextStyle(color: AppTheme.textSecondary)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text("Yo'q"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text("Ha", style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            );

            if (confirm == true && context.mounted) {
              await context.read<ChatProvider>().logout();
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
              }
            }
          },
        ),
      ]),
    );
  }
}

// 📋 RO'YXATDAN O'TGAN FOYDALANUVCHILAR OYNASI (BOTTOM SHEET)
class _UserListSheet extends StatelessWidget {
  const _UserListSheet();

  @override
  Widget build(BuildContext context) {
    final users = context.watch<ChatProvider>().allUsers;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75, // Ekranning 75% qismi
      ),
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Barcha foydalanuvchilar',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          if (users.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Foydalanuvchilar topilmadi', style: TextStyle(color: AppTheme.textSecondary)),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final u = users[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                    leading: AvatarWidget(name: u.name, size: 44, isOnline: false),
                    title: Text(u.name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                    onTap: () {
                      // Bosganda u bilan yangi shaxsiy chat yaratish yoki borini ochish
                      final chat = context.read<ChatProvider>().newPersonal(u);
                      Navigator.pop(context); // Oynani yopish
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
    child: TextField(
      style: const TextStyle(color: AppTheme.textPrimary),
      onChanged: (val) => context.read<ChatProvider>().setSearchQuery(val),
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
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 20),
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