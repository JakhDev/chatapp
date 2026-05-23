📱 FluxChat

FluxChat — bu Flutter + Supabase + WebSocket asosida qurilgan real-time chat ilovasi. Ilova matn,
rasm, audio va video xabarlarni qo‘llab-quvvatlaydi, Google login, animatsion UI va Telegram
uslubidagi chat interfeysiga ega.


-----------------------------------------------------------------

✨ Asosiy imkoniyatlar
🔐 Google orqali autentifikatsiya (Supabase Auth)
💬 Real-time chat (WebSocket)
🖼 Rasm yuborish va preview
🎤 Audio yozish va ijro qilish
🎬 Video preview UI
🗑 Xabarni o‘chirilgan holatda ko‘rsatish
↩️ Reply (javob berish) funksiyasi
👤 User avatar generator (initials + color palette)
🌙 Dark theme (custom UI theme)
🔄 Auto reconnect WebSocket
📡 Online/offline status support (backendga bog‘liq)


---------------------------------------------------------------------


🏗 Texnologiyalar
Flutter
Provider (State Management)
Supabase (Auth + Backend)
WebSocket (Real-time messaging)
just_audio (audio player)
record (audio recording)
path_provider (file storage)
Dart async & streams



--------------------------------------------------------------------




lib/
├── main.dart
├── theme/
│    └── AppTheme.dart
├── screen/
│    ├── SplashScreen.dart
│    ├── HomeScreen.dart
├── providers/
│    ├── AuthProvider.dart
│    ├── ChatProvider.dart
├── services/
│    ├── WebSocketService.dart
│    ├── AudioService.dart
│    ├── ws_stub.dart
│    ├── path_provider_stub.dart
├── widgets/
│    ├── MessageBubble.dart
│    ├── AvatarWidget.dart
├── models/
│    ├── Chat.dart


---------------------------------------------------------------------