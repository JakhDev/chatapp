import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:chatapp/models/Chat.dart';

import 'package:chatapp/providers/ChatProvider.dart';

import 'package:chatapp/providers/AuthProvider.dart';

import 'package:chatapp/theme/AppTheme.dart';

import 'package:chatapp/widgets/AvatarWidget.dart';

import 'package:chatapp/screen/ChatScreen.dart';

import 'package:supabase_flutter/supabase_flutter.dart';



class HomeScreen extends StatelessWidget {

  const HomeScreen({super.key});



  @override

  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: AppTheme.background,

      body: SafeArea(

        child: Column(children: [

          const _Header(),

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

    final chatProvider = context.read<ChatProvider>();

    showModalBottomSheet(

      context: context,

      backgroundColor: AppTheme.surface,

      isScrollControlled: true,

      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),

      builder: (_) => ChangeNotifierProvider.value(

        value: chatProvider,

        child: const _NewChatSheet(),

      ),

    );

  }

}



class _Header extends StatelessWidget {

  const _Header();



  @override

  Widget build(BuildContext context) {

    final auth = context.watch<AuthProvider>();



    return Padding(

      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),

      child: Row(children: [

        AvatarWidget(name: auth.userName, size: 42, isOnline: true),

        const SizedBox(width: 12),

        Expanded(

          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            Text(auth.userName, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),

            Row(children: [

              Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppTheme.online, shape: BoxShape.circle)),

              const SizedBox(width: 5),

              const Text('Ulangan (Supabase)', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),

            ]),

          ]),

        ),

        IconButton(

          icon: const Icon(Icons.logout_rounded, color: AppTheme.textSecondary),

          onPressed: () async {

            final navigator = Navigator.of(context);

            await context.read<AuthProvider>().signOut();

            navigator.pushReplacementNamed('/splash');

          },

        ),

      ]),

    );

  }

}



class _SearchBar extends StatelessWidget {

  @override

  Widget build(BuildContext context) {

    return Padding(

      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),

      child: TextField(

        style: const TextStyle(color: AppTheme.textPrimary),

        onChanged: (value) {

// Qidiruv matni o'zgarganda provayderni filtrlash

          context.read<ChatProvider>().setSearchQuery(value);

        },

        decoration: InputDecoration(

          hintText: 'Qidirish...',

          prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary, size: 20),

          filled: true,

          fillColor: AppTheme.surfaceLight,

          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),

          contentPadding: const EdgeInsets.symmetric(vertical: 12),

        ),

      ),

    );

  }

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

          Text('Chatlar topilmadi', style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),

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



    return InkWell(

      onTap: () {

        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));

      },

      child: Padding(

        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),

        child: Row(children: [

          AvatarWidget(name: chat.name, size: 52, isGroup: isGroup, isOnline: !isGroup),

          const SizedBox(width: 14),

          Expanded(

            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              Text(chat.name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),

              const SizedBox(height: 4),

              Text(chat.lastMessage ?? 'Xabar yozish uchun bosing...', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),

            ]),

          ),

        ]),

      ),

    );

  }

}



class _NewChatSheet extends StatelessWidget {

  const _NewChatSheet();



  Future<List<Map<String, dynamic>>> _getUsersFromSupabase() async {

    final myId = Supabase.instance.client.auth.currentUser?.id;

    final response = await Supabase.instance.client.from('users').select();



    final list = List<Map<String, dynamic>>.from(response);

    if (myId != null) {

      list.removeWhere((element) => element['id'] == myId);

    }

    return list;

  }



  @override

  Widget build(BuildContext context) {

    return Padding(

      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),

      child: Column(

        mainAxisSize: MainAxisSize.min,

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          const Text('Yangi suhbat', style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),

          const SizedBox(height: 14),

          SizedBox(

            height: 300,

            child: FutureBuilder<List<Map<String, dynamic>>>(

              future: _getUsersFromSupabase(),

              builder: (context, snapshot) {

                if (snapshot.connectionState == ConnectionState.waiting) {

                  return const Center(child: CircularProgressIndicator(color: AppTheme.primary));

                }

                final users = snapshot.data ?? [];

                if (users.isEmpty) {

                  return const Center(child: Text('Boshqa foydalanuvchilar topilmadi.', style: TextStyle(color: AppTheme.textSecondary)));

                }



                return ListView.builder(

                  itemCount: users.length,

                  itemBuilder: (context, index) {

                    final u = users[index];

                    final String userId = u['id']?.toString() ?? '';

                    final String userName = u['name']?.toString() ?? 'User';



                    return ListTile(

                      contentPadding: EdgeInsets.zero,

                      leading: CircleAvatar(

                        backgroundColor: AppTheme.primary.withOpacity(0.1),

                        child: const Icon(Icons.person, color: AppTheme.primary),

                      ),

                      title: Text(userName, style: const TextStyle(color: AppTheme.textPrimary)),

                      subtitle: Text(u['isOnline'] == true ? 'Online' : 'Offline', style: const TextStyle(color: AppTheme.online, fontSize: 12)),

                      trailing: const Icon(Icons.chat_bubble_outline, color: AppTheme.primary),

                      onTap: () {

                        final myId = Supabase.instance.client.auth.currentUser?.id ?? '';



                        final chat = Chat(

                          id: userId,

                          name: userName,

                          type: ChatType.personal,

                          memberIds: [myId, userId],

                          messages: [],

                        );



                        context.read<ChatProvider>().addChatIfNotExist(chat);

                        Navigator.pop(context);

                        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));

                      },

                    );

                  },

                );

              },

            ),

          )

        ],

      ),

    );

  }

}