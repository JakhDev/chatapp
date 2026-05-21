import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/providers/ChatProvider.dart';
import 'package:chatapp/theme/AppTheme.dart';
import 'package:chatapp/widgets/AvatarWidget.dart';
import 'package:chatapp/screen/ChatScreen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(children: [
          const _Header(),
          const _SearchBar(),
          const Expanded(child: _ChatList()),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<ChatProvider>().currentUser;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(children: [

        GestureDetector(
          onTap: () => _showProfileDialog(context, user),
          child: Row(children: [
            AvatarWidget(name: user?.name ?? 'U', size: 46, isOnline: true),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                user?.name ?? '',
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
              Row(children: [
                Container(
                  width: 7, height: 7,
                  decoration: const BoxDecoration(
                      color: AppTheme.online, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                const Text('Onlayn',
                    style: TextStyle(color: AppTheme.online, fontSize: 11)),
              ]),
            ]),
          ]),
        ),

        const Spacer(),

        // Foydalanuvchilar
        IconButton(
          icon: const Icon(Icons.people_alt_outlined, color: AppTheme.primary),
          onPressed: () {
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

        // Logout
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppTheme.surface,
                title: const Text('Chiqish',
                    style: TextStyle(color: AppTheme.textPrimary)),
                content: const Text('Dasturdan chiqmoqchimisiz?',
                    style: TextStyle(color: AppTheme.textSecondary)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text("Yo'q")),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Ha',
                          style: TextStyle(color: Colors.redAccent))),
                ],
              ),
            );
            if (ok == true && context.mounted) {
              await context.read<ChatProvider>().logout();
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(
                    context, '/login', (r) => false);
              }
            }
          },
        ),
      ]),
    );
  }

  void _showProfileDialog(BuildContext context, dynamic user) {
    final sbUser = sb.Supabase.instance.client.auth.currentUser;
    final email  = sbUser?.email ?? '';
    final avatar = sbUser?.userMetadata?['avatar_url'] as String?;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primary, AppTheme.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft:  Radius.circular(28),
                    topRight: Radius.circular(28),
                  ),
                ),
                child: Column(children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [BoxShadow(
                        color: Colors.black.withAlpha(64),
                        blurRadius: 12, offset: const Offset(0, 4),
                      )],
                    ),
                    child: ClipOval(
                      child: avatar != null && avatar.isNotEmpty
                          ? Image.network(avatar, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _defaultAvatar(user?.name ?? ''))
                          : _defaultAvatar(user?.name ?? ''),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.name ?? 'Foydalanuvchi',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(51),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: Colors.greenAccent, size: 8),
                        SizedBox(width: 5),
                        Text('Onlayn',
                            style: TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  if (email.isNotEmpty)
                    _infoTile(
                      icon: Icons.email_outlined, label: 'Email',
                      value: email, color: AppTheme.primary,
                    ),
                  const SizedBox(height: 10),
                  _infoTile(
                    icon: Icons.fingerprint_rounded, label: 'ID',
                    value: sbUser?.id.substring(0, 8).toUpperCase() ?? '—',
                    color: AppTheme.accent,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.surfaceLight,
                        foregroundColor: AppTheme.textPrimary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Yopish',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _defaultAvatar(String name) {
    return Container(
      color: AppTheme.primaryDark,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
              color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String   label,
    required String   value,
    required Color    color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withAlpha(38),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 11)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Foydalanuvchilar ro'yxati ─────────────────────────────────────────────────
class _UserListSheet extends StatelessWidget {
  const _UserListSheet();

  // ✅ Bosib turish — o'chirish dialog
  void _showDeleteDialog(BuildContext context, User user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
          const SizedBox(width: 8),
          const Text("O'chirish",
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
        ]),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
            children: [
              const TextSpan(text: '"'),
              TextSpan(
                text: user.name,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: '" foydalanuvchini ro\'yxatdan o\'chirasizmi?'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Bekor qilish",
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<ChatProvider>().deleteUser(user.id);
            },
            child: const Text("O'chirish",
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = context.watch<ChatProvider>().allUsers;

    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75),
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        // Handle
        Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Row(children: [
            Text('Foydalanuvchilar',
                style: TextStyle(color: AppTheme.textPrimary,
                    fontSize: 20, fontWeight: FontWeight.w700)),
            Spacer(),
            // ✅ Bosib turish haqida maslahat
            Row(children: [
              Icon(Icons.touch_app_outlined, size: 14, color: AppTheme.textSecondary),
              SizedBox(width: 4),
              Text("Bosib turing — o'chirish",
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
            ]),
          ]),
        ),

        const SizedBox(height: 12),

        users.isEmpty
            ? const Expanded(
          child: Center(
            child: Text("Foydalanuvchilar yo'q",
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
        )
            : Expanded(
          child: ListView.builder(
            itemCount: users.length,
            itemBuilder: (ctx, i) {
              final u = users[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 4),
                leading: AvatarWidget(
                    name: u.name, size: 44, isOnline: u.isOnline),
                title: Text(u.name,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600)),
                subtitle: u.isOnline
                    ? const Text('Onlayn',
                    style: TextStyle(
                        color: AppTheme.online, fontSize: 11))
                    : null,
                // ✅ Chat ochish
                onTap: () async {
                  final chat =
                  await ctx.read<ChatProvider>().fetchOrCreateChat(u);
                  if (!ctx.mounted) return;
                  ctx.read<ChatProvider>().openChat(chat.id);
                  Navigator.pop(ctx);
                  Navigator.push(ctx, MaterialPageRoute(
                    builder: (_) => ChatScreen(chat: chat),
                  )).then((_) {
                    if (ctx.mounted) ctx.read<ChatProvider>().closeChat();
                  });
                },
                // ✅ Bosib turish — o'chirish
                onLongPress: () => _showDeleteDialog(context, u),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ── Qidiruv ───────────────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
    child: TextField(
      style: const TextStyle(color: AppTheme.textPrimary),
      onChanged: (v) => context.read<ChatProvider>().setSearchQuery(v),
      decoration: InputDecoration(
        hintText: 'Qidirish...',
        prefixIcon: const Icon(Icons.search,
            color: AppTheme.textSecondary, size: 20),
        filled: true, fillColor: AppTheme.surfaceLight,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    ),
  );
}

// ── Chat ro'yxati ─────────────────────────────────────────────────────────────
class _ChatList extends StatelessWidget {
  const _ChatList();

  @override
  Widget build(BuildContext context) {
    final chats = context.watch<ChatProvider>().chats;
    if (chats.isEmpty) {
      return const Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 60, color: AppTheme.textSecondary),
          SizedBox(height: 14),
          Text("Hali chatlar yo'q",
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
          SizedBox(height: 6),
          Text('👥 tugmasini bosib boshlang',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ],
      ));
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

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
          SizedBox(width: 8),
          Text("Chatni o'chirish",
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
        ]),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
            children: [
              const TextSpan(text: '"'),
              TextSpan(
                text: chat.name,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
              ),
              const TextSpan(
                  text: '" bilan bo\'lgan chat va barcha xabarlar o\'chiriladi.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Bekor qilish',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<ChatProvider>().deleteChat(chat.id);
            },
            child: const Text("O'chirish",
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '';
    final t   = dt.toLocal();
    final now = DateTime.now();
    final d   = now.difference(t);
    if (d.inMinutes < 1) return 'Hozir';
    final today = DateTime(now.year, now.month, now.day);
    final tDate = DateTime(t.year, t.month, t.day);
    if (tDate == today) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    if (tDate == today.subtract(const Duration(days: 1))) return 'Kecha';
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = chat.unreadCount > 0;

    return InkWell(
      onTap: () {
        context.read<ChatProvider>().openChat(chat.id);
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)))
            .then((_) {
          if (context.mounted) context.read<ChatProvider>().closeChat();
        });
      },
      // ✅ Bosib turish — chatni o'chirish
      onLongPress: () => _showDeleteDialog(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(children: [
          Stack(children: [
            AvatarWidget(name: chat.name, size: 52,
                isGroup: chat.type == ChatType.group,
                isOnline: chat.type != ChatType.group),
            if (chat.type != ChatType.group)
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
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(chat.name,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15),
                    overflow: TextOverflow.ellipsis)),
                Text(_fmt(chat.lastMessageTime),
                    style: TextStyle(
                        fontSize: 11,
                        color: hasUnread ? AppTheme.online : AppTheme.textSecondary,
                        fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: Text(chat.lastMessage ?? "Xabar yo'q",
                    style: TextStyle(
                      color: hasUnread
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis, maxLines: 1)),
                if (hasUnread)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                        color: AppTheme.online, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    child: Center(child: Text('${chat.unreadCount}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold))),
                  ),
              ]),
            ],
          )),
        ]),
      ),
    );
  }
}