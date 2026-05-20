import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:chatapp/screen/HomeScreen.dart';
import 'package:chatapp/providers/AuthProvider.dart';
import 'package:chatapp/providers/ChatProvider.dart';
import 'package:chatapp/theme/AppTheme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  late final Animation<double> _fade =
  CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  late final Animation<Offset> _slide =
  Tween(begin: const Offset(0, .3), end: Offset.zero)
      .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  bool _showLogin   = false;
  bool _isNavigating = false;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();

    // Barcha platformalarda auth o'zgarishini tinglash
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.session != null && mounted) {
        _goHome();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authProvider = context.read<AuthProvider>();
      if (authProvider.isLoggedIn) {
        _goHome();
      } else {
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) setState(() => _showLogin = true);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _googleLogin() async {
    final authProvider = context.read<AuthProvider>();
    try {
      final success = await authProvider.signInWithGoogle();
      if (!mounted) return;
      if (kIsWeb) return; // Web da _authSub orqali navigate bo'ladi
      if (success) {
        _goHome();
      } else if (authProvider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(authProvider.error!), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Xatolik: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _goHome() {
    if (_isNavigating || !mounted) return;
    _isNavigating = true;

    // ✅ ASOSIY TUZATISH: ChatProvider ga login qilishni aytamiz
    final sbUser = Supabase.instance.client.auth.currentUser;
    if (sbUser != null) {
      final name = sbUser.userMetadata?['full_name'] as String? ??
          sbUser.userMetadata?['name']  as String? ??
          sbUser.email ??
          'Foydalanuvchi';
      // ChatProvider._me ni o'rnatamiz — bu bo'lmasa HomeScreen bo'sh ko'rinadi
      context.read<ChatProvider>().login(name);
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 88, height: 88,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [AppTheme.primary, AppTheme.accent]),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: const Icon(Icons.bolt_rounded,
                          size: 46, color: Colors.white),
                    ),
                    const SizedBox(height: 22),
                    const Text('FluxChat',
                        style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 52),
                    AnimatedOpacity(
                      opacity: _showLogin ? 1 : 0,
                      duration: const Duration(milliseconds: 500),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: _showLogin
                              ? (authProvider.isLoading ? null : _googleLogin)
                              : null,
                          icon: authProvider.isLoading
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Icon(Icons.g_mobiledata,
                              size: 28, color: AppTheme.primary),
                          label: Text(
                            authProvider.isLoading
                                ? 'Kirilmoqda...'
                                : 'Google bilan kirish',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.primary),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}