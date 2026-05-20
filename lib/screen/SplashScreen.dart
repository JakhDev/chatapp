import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:chatapp/screen/HomeScreen.dart';
import 'package:chatapp/providers/AuthProvider.dart';
import 'package:chatapp/theme/AppTheme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween(begin: const Offset(0, .3), end: Offset.zero)
      .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  bool _showLogin = false;

  @override
  void initState() {
    super.initState();

    // Ilova ochilishi bilan sessiyani tekshirish
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authProvider = context.read<AuthProvider>();

      if (authProvider.isLoggedIn) {
        // Agar foydalanuvchi allaqachon kirgan bo'lsa, to'g'ridan-to'g'ri Home oynasiga o'tadi
        _goHome();
      } else {
        // Kirmagan bo'lsa, splash animatsiyasidan keyin login tugmasini ko'rsatadi
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) setState(() => _showLogin = true);
      }
    });

    if (kIsWeb) {
      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (data.session != null && mounted) _goHome();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _googleLogin() async {
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.signInWithGoogle();

    if (!mounted) return;
    if (kIsWeb) return;

    if (success) {
      _goHome();
    } else if (authProvider.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authProvider.error!), backgroundColor: Colors.red),
      );
    }
  }

  void _goHome() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
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
                        gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.accent]),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: const Icon(Icons.bolt_rounded, size: 46, color: Colors.white),
                    ),
                    const SizedBox(height: 22),
                    const Text('FluxChat', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: AppTheme.textPrimary)),
                    const SizedBox(height: 52),
                    AnimatedOpacity(
                      opacity: _showLogin ? 1 : 0,
                      duration: const Duration(milliseconds: 500),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity, height: 52,
                            child: OutlinedButton.icon(
                              onPressed: _showLogin ? (authProvider.isLoading ? null : _googleLogin) : null,
                              icon: authProvider.isLoading
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.g_mobiledata, size: 28, color: AppTheme.primary),
                              label: Text(authProvider.isLoading ? 'Kirilmoqda...' : 'Google bilan kirish',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppTheme.primary),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                            ),
                          ),
                        ],
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