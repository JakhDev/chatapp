import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chatapp/models/AppSettings.dart';
import 'package:chatapp/theme/AppTheme.dart';
import 'package:chatapp/services/WebSocketService.dart';
import 'package:chatapp/providers/AuthProvider.dart';
import 'package:chatapp/providers/ChatProvider.dart';
import 'package:chatapp/screen/SplashScreen.dart';
import 'package:chatapp/screen/HomeScreen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await Supabase.initialize(
    url:     'https://lrkweduvjgmqerygvoaw.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imxya3dlZHV2amdtcWVyeWd2b2F3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNjUzMDgsImV4cCI6MjA5NDc0MTMwOH0.5nxPSEDvZJzFSl86lPVLxhoeXYtKQ50HRsmBzCb5H00',
  );

  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppSettings()),  // ← yangi
        ChangeNotifierProvider(create: (_) => WebSocketService()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProxyProvider<WebSocketService, ChatProvider>(
          create:  (ctx) => ChatProvider(ctx.read<WebSocketService>()),
          update:  (_, ws, prev) => prev ?? ChatProvider(ws),
        ),
      ],
      child: Consumer<AppSettings>(
        builder: (_, settings, __) => MaterialApp(
          title:                     'FluxChat',
          debugShowCheckedModeBanner: false,
          theme:                     AppTheme.lightTheme,
          darkTheme:                 AppTheme.darkTheme,
          themeMode:                 settings.flutterThemeMode,
          initialRoute: '/',
          routes: {
            '/':      (_) => const _AppEntry(),
            '/login': (_) => const SplashScreen(),
            '/home':  (_) => const HomeScreen(),
          },
        ),
      ),
    );
  }
}

class _AppEntry extends StatefulWidget {
  const _AppEntry();
  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null && mounted) {
        final u    = session.user;
        final name = u.userMetadata?['full_name'] as String? ??
            u.userMetadata?['name'] as String? ??
            u.email ?? 'Foydalanuvchi';
        context.read<ChatProvider>().login(name);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    return session != null ? const HomeScreen() : const SplashScreen();
  }
}