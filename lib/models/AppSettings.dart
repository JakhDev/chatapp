import 'package:flutter/material.dart';

enum AppLanguage { uz, ru, en }
enum AppThemeMode { system, light, dark }

class AppSettings extends ChangeNotifier {
  AppLanguage  _language  = AppLanguage.uz;
  AppThemeMode _themeMode = AppThemeMode.dark;

  AppLanguage  get language  => _language;
  AppThemeMode get themeMode => _themeMode;

  ThemeMode get flutterThemeMode => switch (_themeMode) {
    AppThemeMode.light  => ThemeMode.light,
    AppThemeMode.dark   => ThemeMode.dark,
    AppThemeMode.system => ThemeMode.system,
  };

  void setLanguage(AppLanguage lang) {
    _language = lang;
    notifyListeners();
  }

  void setThemeMode(AppThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  // ── Barcha matnlar ────────────────────────────────────────────────────────
  String get chats         => _t(uz: 'Chatlar',       ru: 'Чаты',         en: 'Chats');
  String get contacts      => _t(uz: 'Kontaktlar',    ru: 'Контакты',     en: 'Contacts');
  String get settings      => _t(uz: 'Sozlamalar',    ru: 'Настройки',    en: 'Settings');
  String get profile       => _t(uz: 'Profil',        ru: 'Профиль',      en: 'Profile');
  String get online        => _t(uz: 'Onlayn',        ru: 'В сети',       en: 'Online');
  String get offline       => _t(uz: 'Oflayn',        ru: 'Не в сети',    en: 'Offline');
  String get justNow       => _t(uz: 'Hozirgina',     ru: 'Только что',   en: 'Just now');
  String get search        => _t(uz: 'Qidirish...',   ru: 'Поиск...',     en: 'Search...');
  String get typeMessage   => _t(uz: 'Xabar yozing...', ru: 'Написать сообщение...', en: 'Type a message...');
  String get editMessage   => _t(uz: 'Xabarni tahrirlash', ru: 'Редактировать', en: 'Edit message');
  String get deleteMsg     => _t(uz: "O'chirish",     ru: 'Удалить',      en: 'Delete');
  String get cancel        => _t(uz: 'Bekor qilish',  ru: 'Отмена',       en: 'Cancel');
  String get save          => _t(uz: 'Saqlash',       ru: 'Сохранить',    en: 'Save');
  String get noChats       => _t(uz: "Hali chatlar yo'q", ru: 'Нет чатов', en: 'No chats yet');
  String get noContacts    => _t(uz: "Foydalanuvchilar yo'q", ru: 'Нет пользователей', en: 'No users');
  String get logout        => _t(uz: 'Chiqish',       ru: 'Выйти',        en: 'Logout');
  String get logoutConfirm => _t(uz: 'Dasturdan chiqmoqchimisiz?', ru: 'Выйти из аккаунта?', en: 'Logout from account?');
  String get yes           => _t(uz: 'Ha',            ru: 'Да',           en: 'Yes');
  String get no            => _t(uz: "Yo'q",          ru: 'Нет',          en: 'No');
  String get clearChat     => _t(uz: 'Chat tozalash', ru: 'Очистить чат', en: 'Clear chat');
  String get clearConfirm  => _t(uz: "Barcha xabarlar o'chiriladi.", ru: 'Все сообщения будут удалены.', en: 'All messages will be deleted.');
  String get copied        => _t(uz: 'Nusxa olindi',  ru: 'Скопировано',  en: 'Copied');
  String get recording     => _t(uz: 'Yozilmoqda...', ru: 'Запись...',    en: 'Recording...');
  String get today         => _t(uz: 'Bugun',         ru: 'Сегодня',      en: 'Today');
  String get yesterday     => _t(uz: 'Kecha',         ru: 'Вчера',        en: 'Yesterday');
  String get now           => _t(uz: 'Hozir',         ru: 'Сейчас',       en: 'Now');
  String get searchChats   => _t(uz: 'Chatlarni qidirish...', ru: 'Поиск чатов...', en: 'Search chats...');
  String get searchContacts=> _t(uz: 'Kontaktlarni qidirish...', ru: 'Поиск контактов...', en: 'Search contacts...');
  String get deleteChat    => _t(uz: "Chatni o'chirish", ru: 'Удалить чат', en: 'Delete chat');
  String get deleteUser    => _t(uz: "O'chirish",     ru: 'Удалить',      en: 'Delete');
  String get refresh       => _t(uz: 'Yangilash',     ru: 'Обновить',     en: 'Refresh');
  String get noMessages    => _t(uz: "Hali xabarlar yo'q", ru: 'Нет сообщений', en: 'No messages yet');
  String get sendFirst     => _t(uz: 'Birinchi xabarni yuboring 👋', ru: 'Отправьте первое сообщение 👋', en: 'Send the first message 👋');
  String get more          => _t(uz: 'Batafsil',      ru: 'Ещё',          en: 'More');
  String get member        => _t(uz: "a'zo",          ru: 'участник',     en: 'member');

  // Settings
  String get account        => _t(uz: 'HISOB',          ru: 'АККАУНТ',      en: 'ACCOUNT');
  String get notifications  => _t(uz: 'Bildirishnomalar', ru: 'Уведомления', en: 'Notifications');
  String get appearance     => _t(uz: "KO'RINISH",      ru: 'ВНЕШНИЙ ВИД',  en: 'APPEARANCE');
  String get theme          => _t(uz: 'Mavzu',           ru: 'Тема',         en: 'Theme');
  String get darkMode       => _t(uz: "Qorong'u rejim",  ru: 'Тёмная тема',  en: 'Dark mode');
  String get lightMode      => _t(uz: "Yorug' rejim",    ru: 'Светлая тема', en: 'Light mode');
  String get systemMode     => _t(uz: 'Tizim',           ru: 'Системная',    en: 'System');
  String get twoStep        => _t(uz: 'Ikki bosqichli tekshiruv', ru: 'Двухфакторная аутентификация', en: 'Two-step verification');
  String get off            => _t(uz: "O'chiq",          ru: 'Выкл',         en: 'Off');
  String get appNotifications => _t(uz: 'Ilova bildirishnomalariy', ru: 'Уведомления приложения', en: 'App notifications');

  // Vaqt
  String minutesAgo(int n) => _t(uz: '$n daqiqa oldin', ru: '$n мин. назад', en: '${n}m ago');
  String hoursAgo(int n)   => _t(uz: '$n soat oldin',   ru: '$n ч. назад',   en: '${n}h ago');
  String daysAgo(int n)    => _t(uz: '$n kun oldin',     ru: '$n дн. назад',  en: '${n}d ago');

  String deletedCount(int n) => _t(
    uz: '$n ta xabarni o\'chirish',
    ru: 'Удалить $n сообщений',
    en: 'Delete $n messages',
  );
  String deletedForAll(int n) => _t(
    uz: '$n ta xabar barcha uchun o\'chiriladi.',
    ru: '$n сообщений будут удалены для всех.',
    en: '$n messages will be deleted for all.',
  );

  String _t({required String uz, required String ru, required String en}) {
    switch (_language) {
      case AppLanguage.uz: return uz;
      case AppLanguage.ru: return ru;
      case AppLanguage.en: return en;
    }
  }
}