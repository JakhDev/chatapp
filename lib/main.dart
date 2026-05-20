import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chatapp/theme/AppTheme.dart';
import 'package:chatapp/services/WebSocketService.dart';
import 'package:chatapp/providers/AuthProvider.dart';
import 'package:chatapp/providers/ChatProvider.dart';
import 'package:chatapp/screen/SplashScreen.dart';
import 'package:chatapp/screen/HomeScreen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://lrkweduvjgmqerygvoaw.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imxya3dlZHV2amdtcWVyeWd2b2F3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNjUzMDgsImV4cCI6MjA5NDc0MTMwOH0.5nxPSEDvZJzFSl86lPVLxhoeXYtKQ50HRsmBzCb5H00',
  );

  runApp(const ChatApp());
}

class ChatApp extends StatefulWidget {
  const ChatApp({super.key});

  @override
  State<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WebSocketService()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProxyProvider<WebSocketService, ChatProvider>(
          create: (ctx) => ChatProvider(ctx.read<WebSocketService>()),
          update: (_, ws, prev) => prev ?? ChatProvider(ws),
        ),
      ],
      child: MaterialApp(
        title: 'FluxChat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: _getInitialScreen(),
      ),
    );
  }

  // Boshlang'ich ekranni aniqlash
  Widget _getInitialScreen() {
    final session = Supabase.instance.client.auth.currentSession;

    // Session bor bo'lsa (web redirect yoki avval kirgan)
    if (session != null) {
      return const HomeScreen();
    }

    return const SplashScreen();
  }
}