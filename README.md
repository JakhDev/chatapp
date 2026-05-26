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


📱 FluxChat
FluxChat — это мобильное приложение для чата в реальном времени (real-time), разработанное на базе Flutter, Supabase и WebSocket. Приложение поддерживает отправку текстовых, фото-, аудио- и видеосообщений, авторизацию через Google, имеет анимированный пользовательский интерфейс (UI) и мессенджер-интерфейс в стиле Telegram.

✨ Основные возможности
🔐 Авторизация через Google (Supabase Auth)

💬 Чат в реальном времени (через WebSocket)

🖼 Отправка и предварительный просмотр изображений (Image Preview)

🎤 Запись и воспроизведение голосовых сообщений

🎬 UI предпросмотра видео

🗑 Отображение удаленных сообщений (индикатор удаленного сообщения)

↩️ Функция ответа на сообщения (Reply)

👤 Генератор аватаров пользователей (инициалы + цветовая палитра)

🌙 Темная тема (кастомный UI)

🔄 Автоматическое переподключение WebSocket (Auto reconnect)

📡 Поддержка онлайн/оффлайн статусов (зависит от бэкенда)

🏗 Технологический стек
Flutter

Provider (State Management)

Supabase (Auth + Backend)

WebSocket (Real-time messaging)

just_audio (Воспроизведение аудио)

record (Запись аудио)

path_provider (Локальное хранение файлов)

Dart async & streams

📁 Структура проекта
Plaintext
lib/
├── main.dart
├── theme/
│   └── AppTheme.dart
├── screen/
│   ├── SplashScreen.dart
│   └── HomeScreen.dart
├── providers/
│   ├── AuthProvider.dart
│   └── ChatProvider.dart
├── services/
│   ├── WebSocketService.dart
│   ├── AudioService.dart
│   ├── ws_stub.dart
│   └── path_provider_stub.dart
├── widgets/
│   ├── MessageBubble.dart
│   └── AvatarWidget.dart
├── models/
│   └── Chat.dart


------------------------------------------------------------------------


📱 FluxChat
FluxChat is a real-time chat application built with Flutter, Supabase, and WebSockets. The app supports text, image, audio, and video messaging, features Google Sign-In, and boasts an animated, Telegram-style user interface.

✨ Key Features
🔐 Google Authentication (Supabase Auth)

💬 Real-time Messaging (via WebSockets)

🖼 Image Sharing & Preview

🎤 Audio Recording & Playback

🎬 Video Preview UI

🗑 Deleted Message States (displays as "message deleted")

↩️ Message Reply functionality

👤 User Avatar Generator (initials + dynamic color palette)

🌙 Dark Theme (custom UI styling)

🔄 WebSocket Auto-Reconnect

📡 Online/Offline Status Support (backend-dependent)

🏗 Tech Stack
Flutter

Provider (State Management)

Supabase (Auth & Backend)

WebSocket (Real-time communication)

just_audio (Audio playback)

record (Audio recording)

path_provider (Local file system access)

Dart async & streams

📁 Project Structure
Plaintext
lib/
├── main.dart
├── theme/
│   └── AppTheme.dart
├── screen/
│   ├── SplashScreen.dart
│   └── HomeScreen.dart
├── providers/
│   ├── AuthProvider.dart
│   └── ChatProvider.dart
├── services/
│   ├── WebSocketService.dart
│   ├── AudioService.dart
│   ├── ws_stub.dart
│   └── path_provider_stub.dart
├── widgets/
│   ├── MessageBubble.dart
│   └── AvatarWidget.dart
├── models/
│   └── Chat.dart
