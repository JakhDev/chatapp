import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const _webClientId =
      '964176397631-chab4uo6skkcccq70q04fkgcfsqfcpuu.apps.googleusercontent.com';

  User? _user;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;

  bool get isLoading => _isLoading;

  String? get error => _error;

  bool get isLoggedIn =>
      _supabase.auth.currentSession !=
      null; // To'g'ridan-to'g'ri sessiyadan tekshiramiz

  AuthProvider() {
    _user = _supabase.auth.currentUser;
    _supabase.auth.onAuthStateChange.listen((data) {
      _user = data.session?.user;
      notifyListeners();
    });
  }

  Future<bool> signInWithGoogle() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (kIsWeb) {
        await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: Uri.base.origin,
          queryParams: {'access_type': 'offline', 'prompt': 'consent'},
        );
        return false;
      } else {
        final GoogleSignIn googleSignIn = GoogleSignIn(
          serverClientId: _webClientId,
          scopes: ['email', 'profile'],
        );

        await googleSignIn.signOut();
        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

        if (googleUser == null) {
          _isLoading = false;
          notifyListeners();
          return false;
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        final idToken = googleAuth.idToken;
        final accessToken = googleAuth.accessToken;

        if (idToken == null) throw Exception('ID Token null keldi');

        final response = await _supabase.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: accessToken,
        );

        _user = response.user;
        _isLoading = false;
        notifyListeners();
        return _user != null;
      }
    } catch (e) {
      _error = 'Google login xatosi: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  String get userName =>
      _user?.userMetadata?['full_name'] as String? ??
      _user?.userMetadata?['name'] as String? ??
      _user?.email ??
      'Foydalanuvchi';

  String? get userAvatar => _user?.userMetadata?['avatar_url'] as String?;

  Future<void> signOut() async {
    if (!kIsWeb) await GoogleSignIn().signOut();
    await _supabase.auth.signOut();
    _user = null;
    notifyListeners();
  }
}
