import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chatapp/models/Chat.dart';
import 'package:chatapp/providers/ChatProvider.dart';
import 'package:chatapp/theme/AppTheme.dart';
import 'package:chatapp/widgets/AvatarWidget.dart';
import 'package:chatapp/screen/ChatScreen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/AppSettings.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int  _selectedIndex = 0;
  bool _searchVisible = false;
  final TextEditingController _searchController = TextEditingController();
  late AnimationController _searchAnimCtrl;
  late Animation<double> _searchFade;
  late Animation<Offset>  _searchSlide;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadAllUsers();
    });

    _searchAnimCtrl = AnimationController(
      vsync   : this,
      duration: const Duration(milliseconds: 280),
    );
    _searchFade  = CurvedAnimation(parent: _searchAnimCtrl, curve: Curves.easeOut);
    _searchSlide = Tween<Offset>(begin: const Offset(0, -0.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _searchAnimCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchAnimCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() => _searchVisible = !_searchVisible);
    if (_searchVisible) {
      _searchAnimCtrl.forward();
    } else {
      _searchAnimCtrl.reverse();
      _searchController.clear();
      context.read<ChatProvider>().setSearchQuery('');
    }
  }

  bool get _showSearchBar => _selectedIndex == 0 || _selectedIndex == 1;

  String _appBarTitle(AppSettings s) {
    switch (_selectedIndex) {
      case 0:  return s.chats;
      case 1:  return s.contacts;
      case 2:  return s.settings;
      case 3:  return s.profile;
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsContext.of(context);
    final s = context.watch<AppSettings>();

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor       : c.background,
        elevation             : 0,
        scrolledUnderElevation: 0,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            _appBarTitle(s),
            key  : ValueKey(_selectedIndex),
            style: TextStyle(
              color     : c.textPrimary,
              fontSize  : 22,
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
                  key  : ValueKey(_searchVisible),
                  color: c.textSecondary,
                  size : 24,
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
            // ── Search bar ──────────────────────────────────────────────
            if (_showSearchBar)
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve   : Curves.easeOutCubic,
                child   : _searchVisible
                    ? SlideTransition(
                  position: _searchSlide,
                  child: FadeTransition(
                    opacity: _searchFade,
                    child: Container(
                      color  : c.background,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: TextField(
                        controller: _searchController,
                        autofocus : true,
                        style: TextStyle(color: c.textPrimary),
                        onChanged: (v) {
                          context.read<ChatProvider>().setSearchQuery(v);
                          setState(() {});
                        },
                        decoration: InputDecoration(
                          hintText: _selectedIndex == 0
                              ? s.searchChats
                              : s.searchContacts,
                          hintStyle: TextStyle(color: c.textSecondary),
                          prefixIcon: Icon(Icons.search_rounded, color: c.textSecondary),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                            icon    : Icon(Icons.close, color: c.textSecondary, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              context.read<ChatProvider>().setSearchQuery('');
                              setState(() {});
                            },
                          )
                              : null,
                          filled     : true,
                          fillColor  : c.surfaceLight,
                          border     : OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide  : BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                    : const SizedBox.shrink(),
              ),

            // ── Screens ─────────────────────────────────────────────────
            Expanded(
              child: AnimatedSwitcher(
                duration       : const Duration(milliseconds: 220),
                switchInCurve  : Curves.easeOutCubic,
                switchOutCurve : Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.03, 0),
                      end  : Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key  : ValueKey(_selectedIndex),
                  child: _buildScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _AnimatedBottomNav(
        selectedIndex: _selectedIndex,
        onTap: (index) {
          if (index == _selectedIndex) return;
          if (index == 1) context.read<ChatProvider>().loadAllUsers();
          if (_searchVisible) {
            setState(() => _searchVisible = false);
            _searchAnimCtrl.reverse();
            _searchController.clear();
            context.read<ChatProvider>().setSearchQuery('');
          }
          setState(() => _selectedIndex = index);
        },
        unreadCount: context.watch<ChatProvider>().chats.fold(
          0, (sum, c) => sum + c.unreadCount,
        ),
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
//  ANIMATED BOTTOM NAV
// ═══════════════════════════════════════════════════════════════════════════════
class _AnimatedBottomNav extends StatelessWidget {
  final int             selectedIndex;
  final ValueChanged<int> onTap;
  final int             unreadCount;

  const _AnimatedBottomNav({
    required this.selectedIndex,
    required this.onTap,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    final c     = AppColorsContext.of(context);
    final s     = context.watch<AppSettings>();
    final items = [
      _NavItem(icon: Icons.chat_bubble_rounded,     label: s.chats),
      _NavItem(icon: Icons.people_alt_rounded,      label: s.contacts),
      _NavItem(icon: Icons.settings_rounded,        label: s.settings),
      _NavItem(icon: Icons.account_circle_rounded,  label: s.profile),
    ];

    return Container(
      decoration: BoxDecoration(
        color : c.background,
        border: Border(top: BorderSide(color: c.surfaceLight, width: 0.5)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: List.generate(items.length, (i) {
              final selected = i == selectedIndex;
              return Expanded(
                child: GestureDetector(
                  onTap   : () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration : const Duration(milliseconds: 250),
                        curve    : Curves.easeOutCubic,
                        padding  : const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary.withOpacity(0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              items[i].icon,
                              color: selected ? AppColors.primary : c.textSecondary,
                              size : 24,
                            ),
                            if (i == 0 && unreadCount > 0)
                              Positioned(
                                top  : -8,
                                right: -12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color       : AppColors.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    unreadCount > 99 ? '99+' : '$unreadCount',
                                    style: const TextStyle(
                                      color     : Colors.white,
                                      fontSize  : 10,
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
                          color     : selected ? AppColors.primary : c.textSecondary,
                          fontSize  : 11,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
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
  final String   label;
  const _NavItem({required this.icon, required this.label});
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CHATS SCREEN
// ═══════════════════════════════════════════════════════════════════════════════
class _ChatsScreen extends StatelessWidget {
  const _ChatsScreen();

  void _showDeleteDialog(BuildContext context, Chat chat) {
    final c = AppColorsContext.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
            const SizedBox(width: 8),
            Text("Chatni o'chirish",
                style: TextStyle(color: c.textPrimary, fontSize: 17)),
          ],
        ),
        content: RichText(
          text: TextSpan(
            style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.5),
            children: [
              const TextSpan(text: '"'),
              TextSpan(text: chat.name,
                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700)),
              const TextSpan(text: '" bilan bo\'lgan chat va barcha xabarlar o\'chiriladi.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Bekor qilish', style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<ChatProvider>().deleteChat(chat.id);
            },
            child: const Text("O'chirish",
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '';
    final t   = dt;
    final now = DateTime.now().toUtc().add(const Duration(hours: 5));
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
    final c        = AppColorsContext.of(context);
    final provider = context.watch<ChatProvider>();
    final chats    = provider.chats
        .where((ch) => ch.lastMessage != null || ch.lastMessageTime != null)
        .toList();

    if (chats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween   : Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 600),
              curve   : Curves.elasticOut,
              builder : (_, v, child) => Transform.scale(scale: v, child: child),
              child   : Icon(Icons.chat_bubble_outline, size: 64, color: c.textSecondary),
            ),
            const SizedBox(height: 14),
            Text("Hali chatlar yo'q",
                style: TextStyle(color: c.textSecondary, fontSize: 15)),
            const SizedBox(height: 6),
            Text('Contacts dan foydalanuvchi tanlang',
                style: TextStyle(color: c.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding    : const EdgeInsets.only(top: 4, bottom: 20),
      itemCount  : chats.length,
      itemBuilder: (_, i) {
        final chat     = chats[i];
        final hasUnread= chat.unreadCount > 0;
        final isGroup  = chat.type == ChatType.group;
        final myId     = provider.currentUser?.id ?? '';
        final otherId  = otherIdFromChatId(chat.id, myId) ?? '';
        final isOnline = provider.isUserOnline(otherId);

        return TweenAnimationBuilder<double>(
          tween   : Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 200 + i * 40),
          curve   : Curves.easeOutCubic,
          builder : (_, v, child) => Opacity(
            opacity : v,
            child   : Transform.translate(offset: Offset(0, 20 * (1 - v)), child: child),
          ),
          child: InkWell(
            onTap: () {
              context.read<ChatProvider>().openChat(chat.id);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)),
              ).then((_) {
                if (context.mounted) context.read<ChatProvider>().closeChat();
              });
            },
            onLongPress: () => _showDeleteDialog(context, chat),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: Row(
                children: [
                  Stack(
                    children: [
                      AvatarWidget(
                        name    : chat.name,
                        size    : 52,
                        isGroup : isGroup,
                        isOnline: !isGroup && isOnline,
                      ),
                      if (!isGroup && isOnline)
                        Positioned(
                          bottom: 2,
                          right : 2,
                          child : Container(
                            width : 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color : AppColors.online,
                              shape : BoxShape.circle,
                              border: Border.all(color: c.background, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                chat.name,
                                style: TextStyle(
                                  color     : c.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize  : 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              _fmt(chat.lastMessageTime),
                              style: TextStyle(
                                fontSize  : 11,
                                color     : hasUnread ? AppColors.online : c.textSecondary,
                                fontWeight: hasUnread ? FontWeight.w600  : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                chat.lastMessage ?? "Xabar yo'q",
                                style: TextStyle(
                                  color     : hasUnread ? c.textPrimary : c.textSecondary,
                                  fontSize  : 13,
                                  fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            if (hasUnread)
                              Container(
                                padding    : const EdgeInsets.all(6),
                                decoration : const BoxDecoration(
                                  color: AppColors.online,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                child: Center(
                                  child: Text(
                                    '${chat.unreadCount}',
                                    style: const TextStyle(
                                      color     : Colors.white,
                                      fontSize  : 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CONTACTS SCREEN
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ChatProvider>().loadAllUsers();
    });
  }

  void _showDeleteDialog(BuildContext context, User user) {
    final c = AppColorsContext.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
            const SizedBox(width: 8),
            Text("O'chirish", style: TextStyle(color: c.textPrimary, fontSize: 17)),
          ],
        ),
        content: RichText(
          text: TextSpan(
            style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.5),
            children: [
              const TextSpan(text: '"'),
              TextSpan(text: user.name,
                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700)),
              const TextSpan(text: '" foydalanuvchini ro\'yxatdan o\'chirasizmi?'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Bekor qilish", style: TextStyle(color: c.textSecondary)),
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
    final c        = AppColorsContext.of(context);
    final provider = context.watch<ChatProvider>();
    final myId     = sb.Supabase.instance.client.auth.currentUser?.id ?? '';
    final users    = provider.allUsers.where((u) => u.id != myId).toList();

    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween   : Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 600),
              curve   : Curves.elasticOut,
              builder : (_, v, child) => Transform.scale(scale: v, child: child),
              child   : Icon(Icons.people_outline, size: 64, color: c.textSecondary),
            ),
            const SizedBox(height: 14),
            Text("Foydalanuvchilar yo'q",
                style: TextStyle(color: c.textSecondary, fontSize: 15)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => context.read<ChatProvider>().loadAllUsers(),
              icon : const Icon(Icons.refresh_rounded),
              label: const Text('Yangilash'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding    : const EdgeInsets.symmetric(vertical: 4),
      itemCount  : users.length,
      itemBuilder: (ctx, i) {
        final u        = users[i];
        final isOnline = context.watch<ChatProvider>().isUserOnline(u.id);

        return TweenAnimationBuilder<double>(
          tween   : Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 200 + i * 40),
          curve   : Curves.easeOutCubic,
          builder : (_, v, child) => Opacity(
            opacity: v,
            child  : Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: Stack(
              children: [
                AvatarWidget(name: u.name, size: 44, isOnline: isOnline),
                if (isOnline)
                  Positioned(
                    bottom: 0,
                    right : 0,
                    child : Container(
                      width : 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color : AppColors.online,
                        shape : BoxShape.circle,
                        border: Border.all(color: c.background, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(u.name,
                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
            subtitle: isOnline
                ? const Text('Onlayn',
                style: TextStyle(color: AppColors.online, fontSize: 11))
                : null,
            onTap: () async {
              final chat = await ctx.read<ChatProvider>().fetchOrCreateChat(u);
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
    final s = context.watch<AppSettings>();
    final c = AppColorsContext.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      children: [
        _sectionTitle(s.appearance, c),

        _SettingsTile(
          icon    : Icons.brightness_6_rounded,
          title   : s.theme,
          subtitle: _themeLabel(s),
          onTap   : () => _showThemeDialog(context, s),
        ),

        _SettingsTile(
          icon    : Icons.language_rounded,
          title   : _langLabel(s),
          subtitle: _langLabel(s),
          onTap   : () => _showLanguageDialog(context, s),
        ),

        const SizedBox(height: 20),
      ],
    );
  }

  String _themeLabel(AppSettings s) {
    switch (s.themeMode) {
      case AppThemeMode.dark:   return s.darkMode;
      case AppThemeMode.light:  return s.lightMode;
      case AppThemeMode.system: return s.systemMode;
    }
  }

  String _langLabel(AppSettings s) {
    switch (s.language) {
      case AppLanguage.uz: return "O'zbek";
      case AppLanguage.ru: return 'Русский';
      case AppLanguage.en: return 'English';
    }
  }

  Widget _sectionTitle(String t, ThemeColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
    child: Text(t, style: const TextStyle(
      color: AppColors.primary, fontSize: 12,
      fontWeight: FontWeight.w700, letterSpacing: 0.8,
    )),
  );

  void _showThemeDialog(BuildContext ctx, AppSettings s) {
    final c = AppColorsContext.of(ctx);
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(s.theme, style: TextStyle(color: c.textPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _RadioTile(
            label   : s.darkMode,
            icon    : Icons.dark_mode_rounded,
            selected: s.themeMode == AppThemeMode.dark,
            onTap   : () { s.setThemeMode(AppThemeMode.dark);   Navigator.pop(ctx); },
          ),
          _RadioTile(
            label   : s.lightMode,
            icon    : Icons.light_mode_rounded,
            selected: s.themeMode == AppThemeMode.light,
            onTap   : () { s.setThemeMode(AppThemeMode.light);  Navigator.pop(ctx); },
          ),
          _RadioTile(
            label   : s.systemMode,
            icon    : Icons.phone_android_rounded,
            selected: s.themeMode == AppThemeMode.system,
            onTap   : () { s.setThemeMode(AppThemeMode.system); Navigator.pop(ctx); },
          ),
        ]),
      ),
    );
  }

  void _showLanguageDialog(BuildContext ctx, AppSettings s) {
    final c = AppColorsContext.of(ctx);
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_langLabel(s), style: TextStyle(color: c.textPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _RadioTile(
            label   : "O'zbek",
            icon    : Icons.language_rounded,
            selected: s.language == AppLanguage.uz,
            onTap   : () { s.setLanguage(AppLanguage.uz); Navigator.pop(ctx); },
          ),
          _RadioTile(
            label   : 'Русский',
            icon    : Icons.language,
            selected: s.language == AppLanguage.ru,
            onTap   : () { s.setLanguage(AppLanguage.ru); Navigator.pop(ctx); },
          ),
          _RadioTile(
            label   : 'English',
            icon    : Icons.language_rounded,
            selected: s.language == AppLanguage.en,
            onTap   : () { s.setLanguage(AppLanguage.en); Navigator.pop(ctx); },
          ),
        ]),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData     icon;
  final String       title;
  final String       subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorsContext.of(context);
    return ListTile(
      onTap  : onTap,
      leading: Container(
        width : 36, height: 36,
        decoration: BoxDecoration(
          color       : AppColors.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title   : Text(title,
          style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: TextStyle(color: c.textSecondary, fontSize: 13)),
      trailing: onTap != null
          ? Icon(Icons.chevron_right, color: c.textSecondary, size: 20)
          : null,
    );
  }
}

class _RadioTile extends StatelessWidget {
  final String       label;
  final IconData     icon;
  final bool         selected;
  final VoidCallback onTap;

  const _RadioTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorsContext.of(context);
    return ListTile(
      onTap  : onTap,
      leading: Icon(icon,
          color: selected ? AppColors.primary : c.textSecondary, size: 22),
      title: Text(label, style: TextStyle(
        color     : selected ? AppColors.primary : c.textPrimary,
        fontWeight: selected ? FontWeight.w700  : FontWeight.normal,
      )),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
          : null,
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
    final c      = AppColorsContext.of(context);
    final user   = context.watch<ChatProvider>().currentUser;
    final sbUser = sb.Supabase.instance.client.auth.currentUser;
    final email  = sbUser?.email ?? '';
    final avatar = sbUser?.userMetadata?['avatar_url'] as String?;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 30),
      children: [
        TweenAnimationBuilder<double>(
          tween   : Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 500),
          curve   : Curves.easeOutBack,
          builder : (_, v, child) => Transform.scale(scale: v, child: child),
          child: Center(
            child: Container(
              width : 100, height: 100,
              decoration: BoxDecoration(
                color : AppColors.primary.withAlpha(80),
                shape : BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: avatar != null && avatar.isNotEmpty
                  ? ClipOval(
                child: Image.network(
                  avatar,
                  fit         : BoxFit.cover,
                  errorBuilder: (_, __, ___) => _defaultAvatar(user?.name ?? '', c),
                ),
              )
                  : _defaultAvatar(user?.name ?? '', c),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            user?.name ?? 'User',
            style: TextStyle(color: c.textPrimary, fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Container(
            padding   : const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color       : AppColors.primary.withAlpha(30),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: Colors.greenAccent, size: 8),
                SizedBox(width: 5),
                Text('Onlayn', style: TextStyle(color: AppColors.online, fontSize: 12)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 30),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color       : c.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (email.isNotEmpty) ...[
                  _infoTile(
                    icon : Icons.email_outlined,
                    label: 'Email',
                    value: email,
                    color: AppColors.primary,
                    c    : c,
                  ),
                  const SizedBox(height: 12),
                ],
                _infoTile(
                  icon : Icons.fingerprint_rounded,
                  label: 'ID',
                  value: sbUser?.id.substring(0, 8).toUpperCase() ?? '—',
                  color: AppColors.primary,
                  c    : c,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              side  : const BorderSide(color: Colors.redAccent),
              shape : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () async {
              final c = AppColorsContext.of(context);
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: c.surface,
                  title  : Text('Chiqish', style: TextStyle(color: c.textPrimary)),
                  content: Text('Dasturdan chiqmoqchimisiz?',
                      style: TextStyle(color: c.textSecondary)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text("Yo'q", style: TextStyle(color: c.textSecondary)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Ha', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await context.read<ChatProvider>().logout();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
                }
              }
            },
            child: const Text('Chiqish',
                style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _defaultAvatar(String name, ThemeColors c) => Container(
    color: AppColors.primaryDark,
    child: Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
      ),
    ),
  );

  Widget _infoTile({
    required IconData      icon,
    required String        label,
    required String        value,
    required Color         color,
    required ThemeColors   c,
  }) => Container(
    padding   : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color       : c.surfaceLight,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Container(
          width : 36, height: 36,
          decoration: BoxDecoration(
            color       : color.withAlpha(38),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: c.textSecondary, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                    color     : c.textPrimary,
                    fontSize  : 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    ),
  );
}