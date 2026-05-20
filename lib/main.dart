import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chatapp/theme/AppTheme.dart';
import 'package:chatapp/services/WebSocketService.dart';
import 'package:chatapp/providers/AuthProvider.dart';
import 'package:chatapp/providers/ChatProvider.dart';
import 'package:chatapp/screen/SplashScreen.dart';
import 'package:chatapp/screen/HomeScreen.dart';

Future<void> main() async {
  // Flutter vidjetlari bog'lanishini ta'minlash
  WidgetsFlutterBinding.ensureInitialized();

  // Supabase-ni ishga tushirish (Sizning loyihangiz ma'lumotlari)
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
        // WebSocket xizmatini ro'yxatdan o'tkazish
        ChangeNotifierProvider(create: (_) => WebSocketService()),

        // Autentifikatsiya provayderi
        ChangeNotifierProvider(create: (_) => AuthProvider()),

        // ChatProvider WebSocketService-ga bog'liq bo'lgani uchun ProxyProvider ishlatildi
        ChangeNotifierProxyProvider<WebSocketService, ChatProvider>(
          create: (ctx) => ChatProvider(ctx.read<WebSocketService>()),
          update: (_, ws, prev) => prev ?? ChatProvider(ws),
        ),
      ],
      child: MaterialApp(
        title: 'FluxChat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,

        // Ilova birinchi ochilgandagi tekshirish ekrani
        home: _getInitialScreen(),

        // Ilovadagi barcha asosiy sahifalar marshrutlari (Routes)
        // Bu orqali HomeScreen-da Navigator.pushNamedAndRemoveUntil(context, '/login', ...) ishlata olasiz
        routes: {
          '/login': (context) => const SplashScreen(),
          '/home': (context) => const HomeScreen(),
          '/splash': (context) => const SplashScreen(),
        },
      ),
    );
  }

  // Foydalanuvchi avval kirgan yoki kirmaganligini aniqlash funksiyasi
  Widget _getInitialScreen() {
    final session = Supabase.instance.client.auth.currentSession;

    // Agar Supabase-da faol sessiya (session) mavjud bo'lsa, to'g'ri Asosiy sahifaga o'tadi
    if (session != null) {
      return const HomeScreen();
    }

    // Agar foydalanuvchi birinchi marta kirayotgan bo'lsa yoki logaut qilgan bo'lsa, Splash ko'rsatiladi
    return const SplashScreen();
  }
}