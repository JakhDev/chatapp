import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Google Cloud Console dan olingan Web Client ID
  static const _webClientId =
      '964176397631-chab4uo6skkcccq70q04fkgcfsqfcpuu.apps.googleusercontent.com';

  User?   _user;
  bool    _isLoading = false;
  String? _error;

  User?   get user       => _user;
  bool    get isLoading  => _isLoading;
  String? get error      => _error;
  bool    get isLoggedIn => _user != null;

  AuthProvider() {
    // Hozirgi sessiyani tekshirish
    _user = _supabase.auth.currentUser;

    // Auth o'zgarishlarini kuzatish
    _supabase.auth.onAuthStateChange.listen((data) {
      final previousUser = _user;
      _user = data.session?.user;

      // Faqat o'zgarsa notify qilish
      if (previousUser?.id != _user?.id) {
        notifyListeners();
      }
    });
  }

  Future<bool> signInWithGoogle() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (kIsWeb) {
        // ════════════════════════════
        // WEB — OAuth redirect usuli
        // ════════════════════════════
        await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: _getRedirectUrl(),
          queryParams: {
            'access_type': 'offline',
            'prompt': 'consent',
          },
        );
        // Web da redirect bo'ladi — bu yerga kelmaydi
        // main.dart da _getHome() session tekshiradi
        _isLoading = false;
        notifyListeners();
        return false;

      } else {
        // ════════════════════════════
        // ANDROID — google_sign_in usuli
        // ════════════════════════════
        final GoogleSignIn googleSignIn = GoogleSignIn(
          serverClientId: _webClientId,
          scopes: ['email', 'profile'],
        );

        // Avval tozalaymiz
        await googleSignIn.signOut();

        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          // Foydalanuvchi bekor qildi
          _isLoading = false;
          notifyListeners();
          return false;
        }

        final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

        final idToken     = googleAuth.idToken;
        final accessToken = googleAuth.accessToken;

        if (idToken == null) {
          throw Exception('ID Token null keldi');
        }

        // Supabase ga kirish
        final response = await _supabase.auth.signInWithIdToken(
          provider:    OAuthProvider.google,
          idToken:     idToken,
          accessToken: accessToken,
        );

        // User ni darhol yangilash
        _user = response.user;
        _isLoading = false;
        notifyListeners();
        return _user != null;
      }

    } catch (e) {
      _error = 'Google login xatosi: $e';
      debugPrint('AuthProvider ERROR: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Redirect URL — platformaga qarab
  String _getRedirectUrl() {
    if (kIsWeb) {
      // Web da hozirgi URL ni olamiz
      return Uri.base.origin;
    }
    // Android uchun deep link
    return 'io.supabase.chatapp://login-callback/';
  }

  Future<void> signOut() async {
    try {
      if (!kIsWeb) await GoogleSignIn().signOut();
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('SignOut error: $e');
    } finally {
      _user = null;
      notifyListeners();
    }
  }

  // Foydalanuvchi ismini olish
  String get userName =>
      _user?.userMetadata?['full_name'] as String? ??
          _user?.userMetadata?['name'] as String? ??
          _user?.email ??
          'User';

  // Foydalanuvchi rasmini olish
  String? get userAvatar =>
      _user?.userMetadata?['avatar_url'] as String?;
}