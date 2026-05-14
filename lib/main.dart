import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chatapp/theme/AppTheme.dart';
import 'package:chatapp/services/WebSocketService.dart';
import 'package:chatapp/providers/ChatProvider.dart';
import 'package:chatapp/screen/SplashScreen.dart';

void main() {
  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WebSocketService()),
        ChangeNotifierProxyProvider<WebSocketService, ChatProvider>(
          create: (ctx) => ChatProvider(ctx.read<WebSocketService>()),
          update: (_, ws, prev) => prev ?? ChatProvider(ws),
        ),
      ],
      child: MaterialApp(
        title: 'FluxChat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const SplashScreen(),
      ),
    );
  }
}