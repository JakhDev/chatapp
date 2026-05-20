import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:chatapp/screen/HomeScreen.dart';
import 'package:chatapp/providers/ChatProvider.dart';
import 'package:chatapp/providers/AuthProvider.dart';
import 'package:chatapp/theme/AppTheme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {

  late final AnimationController _ctrl =
  AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  late final Animation<double> _fade =
  CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

  late final Animation<Offset> _slide =
  Tween(begin: const Offset(0, .3), end: Offset.zero)
      .animate(CurvedAnimation(
      parent: _ctrl, curve: Curves.easeOutCubic));

  final _nameCtrl  = TextEditingController();
  bool  _showLogin = false;

  @override
  void initState() {
    super.initState();

    // 1.8 soniyadan keyin login formani ko'rsatish
    Future.delayed(
      const Duration(milliseconds: 1800),
          () { if (mounted) setState(() => _showLogin = true); },
    );

    // Web da auth o'zgarishini kuzatish
    if (kIsWeb) {
      _listenAuthChanges();
    }
  }

  // Web da redirect dan qaytganda avtomatik o'tish
  void _listenAuthChanges() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.session != null && mounted) {
        final user = data.session!.user;
        final name = user.userMetadata?['full_name'] as String? ??
            user.userMetadata?['name'] as String? ??
            user.email ??
            'User';

        context.read<ChatProvider>().login(name);
        _goHome();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  // Oddiy ism bilan kirish
  void _login() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    context.read<ChatProvider>().login(name);
    _goHome();
  }

  // Google bilan kirish
  Future<void> _googleLogin() async {
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.signInWithGoogle();

    if (!mounted) return;

    if (kIsWeb) {
      // Web da redirect bo'ladi — _listenAuthChanges handle qiladi
      return;
    }

    // Android da
    if (success) {
      context.read<ChatProvider>().login(authProvider.userName);
      _goHome();
    } else if (authProvider.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.error!),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _goHome() {
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

                    // ── Logo ──
                    Container(
                      width: 88, height: 88,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primary, AppTheme.accent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [BoxShadow(
                          color: AppTheme.primary.withOpacity(.4),
                          blurRadius: 28, spreadRadius: 4,
                        )],
                      ),
                      child: const Icon(
                          Icons.bolt_rounded, size: 46, color: Colors.white),
                    ),
                    const SizedBox(height: 22),

                    // ── App nomi ──
                    const Text(
                      'FluxChat',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textPrimary,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Tezkor · Xavfsiz · Real-vaqt',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(height: 52),

                    // ── Login form ──
                    AnimatedOpacity(
                      opacity: _showLogin ? 1 : 0,
                      duration: const Duration(milliseconds: 500),
                      child: Column(
                        children: [

                          // Ism kiritish
                          TextField(
                            controller: _nameCtrl,
                            style: const TextStyle(
                                color: AppTheme.textPrimary),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _login(),
                            decoration: const InputDecoration(
                              hintText: 'Ismingizni kiriting',
                              prefixIcon: Icon(
                                  Icons.person_outline,
                                  color: AppTheme.primary),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Kirish tugmasi
                          SizedBox(
                            width: double.infinity, height: 52,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppTheme.primary, AppTheme.accent],
                                ),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [BoxShadow(
                                  color: AppTheme.primary.withOpacity(.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                )],
                              ),
                              child: ElevatedButton(
                                onPressed: _showLogin ? _login : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24)),
                                ),
                                child: const Text(
                                  'Kirish',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Ajratuvchi
                          const Row(children: [
                            Expanded(child: Divider(
                                color: AppTheme.surfaceLight)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('yoki',
                                  style: TextStyle(
                                      color: AppTheme.textSecondary)),
                            ),
                            Expanded(child: Divider(
                                color: AppTheme.surfaceLight)),
                          ]),
                          const SizedBox(height: 12),

                          // Google bilan kirish
                          SizedBox(
                            width: double.infinity, height: 52,
                            child: OutlinedButton.icon(
                              onPressed: _showLogin
                                  ? (authProvider.isLoading
                                  ? null : _googleLogin)
                                  : null,
                              icon: authProvider.isLoading
                                  ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.primary,
                                ),
                              )
                                  : const Icon(
                                Icons.g_mobiledata,
                                size: 28,
                                color: AppTheme.primary,
                              ),
                              label: Text(
                                authProvider.isLoading
                                    ? 'Kirilmoqda...'
                                    : 'Google bilan kirish',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: AppTheme.primary),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Loading
                    if (!_showLogin) ...[
                      const SizedBox(height: 8),
                      const CircularProgressIndicator(
                          color: AppTheme.primary, strokeWidth: 2),
                    ],
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