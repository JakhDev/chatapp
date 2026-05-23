import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/providers/ChatProvider.dart';
import 'package:chatapp/theme/AppTheme.dart';
import 'package:chatapp/widgets/AvatarWidget.dart';
import 'package:chatapp/screen/ChatScreen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _searchVisible = false;
  final TextEditingController _searchController = TextEditingController();
  late AnimationController _searchAnimController;
  late Animation<double> _searchFade;
  late Animation<Offset> _searchSlide;

  @override
  void initState() {
    super.initState();
    // Contacts sahifasi uchun darhol foydalanuvchilarni yuklash
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadAllUsers();
    });

    _searchAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _searchFade = CurvedAnimation(
      parent: _searchAnimController,
      curve: Curves.easeOut,
    );
    _searchSlide = Tween<Offset>(
      begin: const Offset(0, -0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _searchAnimController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchAnimController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() => _searchVisible = !_searchVisible);
    if (_searchVisible) {
      _searchAnimController.forward();
    } else {
      _searchAnimController.reverse();
      _searchController.clear();
      context.read<ChatProvider>().setSearchQuery('');
    }
  }

  bool get _showSearchBar => _selectedIndex == 0 || _selectedIndex == 1;

  String get _appBarTitle {
    switch (_selectedIndex) {
      case 0:  return 'Chatlar';
      case 1:  return 'Kontaktlar';
      case 2:  return 'Sozlamalar';
      case 3:  return 'Profil';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Barcha ekranlar uchun bir xil fon rangi
    const bgColor = AppTheme.background;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,   // ← toolbar = background rangi
        elevation: 0,
        scrolledUnderElevation: 0,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            _appBarTitle,
            key: ValueKey(_selectedIndex),
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        actions: [
          if (_showSearchBar)
            IconButton(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  _searchVisible ? Icons.close_rounded : Icons.search_rounded,
                  key: ValueKey(_searchVisible),
                  color: AppTheme.textSecondary,
                  size: 24,
                ),
              ),
              onPressed: _toggleSearch,
            ),
          const SizedBox(width: 8),
        ],
      ),

      body: SafeArea(
        child: Column(
          children: [
            // ── ANIMATED SEARCH BAR ──────────────────────────────────────
            if (_showSearchBar)
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: _searchVisible
                    ? SlideTransition(
                  position: _searchSlide,
                  child: FadeTransition(
                    opacity: _searchFade,
                    child: Container(
                      color: bgColor,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        onChanged: (v) {
                          context.read<ChatProvider>().setSearchQuery(v);
                          setState(() {});
                        },
                        decoration: InputDecoration(
                          hintText: _selectedIndex == 0
                              ? 'Chatlarni qidirish...'
                              : 'Kontaktlarni qidirish...',
                          hintStyle: const TextStyle(color: AppTheme.textSecondary),
                          prefixIcon: const Icon(Icons.search_rounded,
                              color: AppTheme.textSecondary),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                            icon: const Icon(Icons.close,
                                color: AppTheme.textSecondary, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              context.read<ChatProvider>().setSearchQuery('');
                              setState(() {});
                            },
                          )
                              : null,
                          filled: true,
                          fillColor: AppTheme.surfaceLight,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                )
                    : const SizedBox.shrink(),
              ),

            // ── SCREENS ──────────────────────────────────────────────────
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.03, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_selectedIndex),
                  child: _buildScreen(),
                ),
              ),
            ),
          ],
        ),
      ),

      // ── ANIMATED BOTTOM NAV ──────────────────────────────────────────────
      bottomNavigationBar: _AnimatedBottomNav(
        selectedIndex: _selectedIndex,
        onTap: (index) {
          if (index == _selectedIndex) return;
          // Contacts tab bosilganda foydalanuvchilarni yangilash
          if (index == 1) {
            context.read<ChatProvider>().loadAllUsers();
          }
          if (_searchVisible) {
            setState(() => _searchVisible = false);
            _searchAnimController.reverse();
            _searchController.clear();
            context.read<ChatProvider>().setSearchQuery('');
          }
          setState(() => _selectedIndex = index);
        },
        unreadCount: context
            .watch<ChatProvider>()
            .chats
            .fold(0, (sum, c) => sum + c.unreadCount),
      ),
    );
  }

  Widget _buildScreen() {
    switch (_selectedIndex) {
      case 0:  return const _ChatsScreen();
      case 1:  return const _ContactsScreen();
      case 2:  return const _SettingsScreen();
      case 3:  return const _ProfileScreen();
      default: return const SizedBox();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ANIMATED BOTTOM NAV  (bir xil background rangi)
// ═══════════════════════════════════════════════════════════════════════════════
class _AnimatedBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final int unreadCount;

  const _AnimatedBottomNav({
    required this.selectedIndex,
    required this.onTap,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _NavItem(icon: Icons.chat_bubble_rounded,    label: 'Chatlar'),
      _NavItem(icon: Icons.people_alt_rounded,     label: 'Kontaktlar'),
      _NavItem(icon: Icons.settings_rounded,       label: 'Sozlamalar'),
      _NavItem(icon: Icons.account_circle_rounded, label: 'Profil'),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.background,   // ← bottomnav = background rangi
        border: Border(
          top: BorderSide(color: AppTheme.surfaceLight, width: 0.5),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: List.generate(items.length, (i) {
              final selected = i == selectedIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primary.withOpacity(0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              items[i].icon,
                              color: selected
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary,
                              size: 24,
                            ),
                            // Unread badge
                            if (i == 0 && unreadCount > 0)
                              Positioned(
                                top: -8,
                                right: -12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    unreadCount > 99 ? '99+' : '$unreadCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          color: selected
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                          fontSize: 11,
                          fontWeight:
                          selected ? FontWeight.w700 : FontWeight.normal,
                        ),
                        child: Text(items[i].label),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CHATS SCREEN
// ═══════════════════════════════════════════════════════════════════════════════
class _ChatsScreen extends StatelessWidget {
  const _ChatsScreen();

  void _showDeleteDialog(BuildContext context, Chat chat) {
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

  // O'zbekiston vaqti (UTC+5) formatlash
  String _fmt(DateTime? dt) {
    if (dt == null) return '';
    // UTC+5 ga o'tkazish
    final t   = dt.toUtc().add(const Duration(hours: 5));
    final now = DateTime.now().toUtc().add(const Duration(hours: 5));
    final d   = now.difference(t);
    if (d.inMinutes < 1) return 'Hozir';
    final today = DateTime(now.year, now.month, now.day);
    final tDate = DateTime(t.year,   t.month,   t.day);
    if (tDate == today)
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (tDate == today.subtract(const Duration(days: 1))) return 'Kecha';
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Faqat xabar almashilgan chatlar
    final chats = context
        .watch<ChatProvider>()
        .chats
        .where((c) => c.lastMessage != null || c.lastMessageTime != null)
        .toList();

    if (chats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: const Icon(Icons.chat_bubble_outline,
                  size: 64, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            const Text("Hali chatlar yo'q",
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
            const SizedBox(height: 6),
            const Text('Contacts dan foydalanuvchi tanlang',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 20),
      itemCount: chats.length,
      itemBuilder: (_, i) {
        final chat      = chats[i];
        final hasUnread = chat.unreadCount > 0;

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 200 + i * 40),
          curve: Curves.easeOutCubic,
          builder: (_, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(
                offset: Offset(0, 20 * (1 - v)), child: child),
          ),
          child: InkWell(
            onTap: () {
              context.read<ChatProvider>().openChat(chat.id);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)))
                  .then((_) {
                if (context.mounted) context.read<ChatProvider>().closeChat();
              });
            },
            onLongPress: () => _showDeleteDialog(context, chat),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: Row(children: [
                Stack(children: [
                  AvatarWidget(
                      name: chat.name,
                      size: 52,
                      isGroup: chat.type == ChatType.group,
                      isOnline: chat.type != ChatType.group),
                  if (chat.type != ChatType.group)
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppTheme.online,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppTheme.background, width: 2),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(chat.name,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15),
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text(_fmt(chat.lastMessageTime),
                            style: TextStyle(
                                fontSize: 11,
                                color: hasUnread
                                    ? AppTheme.online
                                    : AppTheme.textSecondary,
                                fontWeight: hasUnread
                                    ? FontWeight.w600
                                    : FontWeight.normal)),
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        Expanded(
                          child: Text(chat.lastMessage ?? "Xabar yo'q",
                              style: TextStyle(
                                color: hasUnread
                                    ? AppTheme.textPrimary
                                    : AppTheme.textSecondary,
                                fontSize: 13,
                                fontWeight: hasUnread
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1),
                        ),
                        if (hasUnread)
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                                color: AppTheme.online,
                                shape: BoxShape.circle),
                            constraints: const BoxConstraints(
                                minWidth: 20, minHeight: 20),
                            child: Center(
                              child: Text('${chat.unreadCount}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                      ]),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CONTACTS SCREEN  — bazadagi BARCHA foydalanuvchilar
// ═══════════════════════════════════════════════════════════════════════════════
class _ContactsScreen extends StatefulWidget {
  const _ContactsScreen();

  @override
  State<_ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<_ContactsScreen> {
  @override
  void initState() {
    super.initState();
    // Sahifa ochilganda yangilash
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ChatProvider>().loadAllUsers();
    });
  }

  void _showDeleteDialog(BuildContext context, User user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.delete_outline_rounded,
              color: Colors.redAccent, size: 22),
          SizedBox(width: 8),
          Text("O'chirish",
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
        ]),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
            children: [
              const TextSpan(text: '"'),
              TextSpan(
                text: user.name,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
              ),
              const TextSpan(
                  text: '" foydalanuvchini ro\'yxatdan o\'chirasizmi?'),
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
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final myId     = sb.Supabase.instance.client.auth.currentUser?.id ?? '';
    // O'zini ro'yxatdan chiqarib, barchani ko'rsatish
    final users    = provider.allUsers.where((u) => u.id != myId).toList();

    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: const Icon(Icons.people_outline,
                  size: 64, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            const Text("Foydalanuvchilar yo'q",
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => context.read<ChatProvider>().loadAllUsers(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Yangilash'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: users.length,
      itemBuilder: (ctx, i) {
        final u = users[i];
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 200 + i * 40),
          curve: Curves.easeOutCubic,
          builder: (_, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(
                offset: Offset(0, 16 * (1 - v)), child: child),
          ),
          child: ListTile(
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading:
            AvatarWidget(name: u.name, size: 44, isOnline: u.isOnline),
            title: Text(u.name,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600)),
            subtitle: u.isOnline
                ? const Text('Onlayn',
                style: TextStyle(color: AppTheme.online, fontSize: 11))
                : null,
            onTap: () async {
              final chat =
              await ctx.read<ChatProvider>().fetchOrCreateChat(u);
              if (!ctx.mounted) return;
              ctx.read<ChatProvider>().openChat(chat.id);
              Navigator.push(
                ctx,
                MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)),
              ).then((_) {
                if (ctx.mounted) ctx.read<ChatProvider>().closeChat();
              });
            },
            onLongPress: () => _showDeleteDialog(context, u),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SETTINGS SCREEN
// ═══════════════════════════════════════════════════════════════════════════════
class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text('HISOB',
              style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
        ),
        ListTile(
          leading: const Icon(Icons.lock_rounded, color: AppTheme.primary),
          title: const Text('Ikki bosqichli tekshiruv',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          subtitle: const Text("O'chiq",
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          onTap: () {},
        ),
        ListTile(
          leading: const Icon(Icons.language, color: AppTheme.primary),
          title: const Text('Tillar',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          subtitle: const Text('Uzbek',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          onTap: () {},
        ),
        ListTile(
          leading: const Icon(Icons.visibility_off_rounded,
              color: AppTheme.primary),
          title: const Text('Oxirgi faollik',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          subtitle: const Text('Barcha',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          onTap: () {},
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text('Bildirishnomalar',
              style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_rounded,
              color: AppTheme.primary),
          title: const Text('Ilova bildirishnomalari',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          trailing: Switch(
              value: false, onChanged: (v) {}, activeColor: AppTheme.primary),
          onTap: () {},
        ),
        ListTile(
          leading: const Icon(Icons.dark_mode, color: AppTheme.primary),
          title: const Text("Qorong'u rejim",
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          trailing: Switch(
              value: true, onChanged: (v) {}, activeColor: AppTheme.primary),
          onTap: () {},
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PROFILE SCREEN
// ═══════════════════════════════════════════════════════════════════════════════
class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen();

  @override
  Widget build(BuildContext context) {
    final user   = context.watch<ChatProvider>().currentUser;
    final sbUser = sb.Supabase.instance.client.auth.currentUser;
    final email  = sbUser?.email ?? '';
    final avatar = sbUser?.userMetadata?['avatar_url'] as String?;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 30),
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutBack,
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(80),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primary, width: 2),
              ),
              child: avatar != null && avatar.isNotEmpty
                  ? ClipOval(
                  child: Image.network(avatar,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _defaultAvatar(user?.name ?? '')))
                  : _defaultAvatar(user?.name ?? ''),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(user?.name ?? 'User',
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 4),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(30),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: Colors.greenAccent, size: 8),
                SizedBox(width: 5),
                Text('Onlayn',
                    style: TextStyle(color: AppTheme.online, fontSize: 12)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 30),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (email.isNotEmpty) ...[
                  _infoTile(
                      icon: Icons.email_outlined,
                      label: 'Email',
                      value: email,
                      color: AppTheme.primary),
                  const SizedBox(height: 12),
                ],
                _infoTile(
                    icon: Icons.fingerprint_rounded,
                    label: 'ID',
                    value:
                    sbUser?.id.substring(0, 8).toUpperCase() ?? '—',
                    color: AppTheme.primary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.redAccent),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
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
            child: const Text('Chiqish',
                style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _defaultAvatar(String name) => Container(
    color: AppTheme.primaryDark,
    child: Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold),
      ),
    ),
  );

  Widget _infoTile({
    required IconData icon,
    required String   label,
    required String   value,
    required Color    color,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: AppTheme.surfaceLight,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withAlpha(38),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ]),
      ),
    ]),
  );
}