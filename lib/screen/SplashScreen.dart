import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chatapp/screen/HomeScreen.dart';
import 'package:chatapp/providers/ChatProvider.dart';
import 'package:chatapp/theme/AppTheme.dart';


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {

  late final AnimationController _ctrl =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  late final Animation<double>  _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  late final Animation<Offset>  _slide = Tween(begin: const Offset(0, .3), end: Offset.zero)
      .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  final _nameCtrl  = TextEditingController();
  bool  _showLogin = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800),
            () { if (mounted) setState(() => _showLogin = true); });
  }

  @override
  void dispose() { _ctrl.dispose(); _nameCtrl.dispose(); super.dispose(); }

  void _login() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    context.read<ChatProvider>().login(name);
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
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
                    // Logo
                    Container(
                      width: 88, height: 88,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primary, AppTheme.accent],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [BoxShadow(
                          color: AppTheme.primary.withOpacity(.4),
                          blurRadius: 28, spreadRadius: 4,
                        )],
                      ),
                      child: const Icon(Icons.bolt_rounded, size: 46, color: Colors.white),
                    ),
                    const SizedBox(height: 22),
                    const Text('FluxChat',
                        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900,
                            color: AppTheme.textPrimary, letterSpacing: 1)),
                    const SizedBox(height: 6),
                    const Text('Tezkor · Xavfsiz · Real-vaqt',
                        style: TextStyle(fontSize: 14, color: AppTheme.textSecondary,
                            letterSpacing: .5)),
                    const SizedBox(height: 52),

                    // Login form
                    AnimatedOpacity(
                      opacity: _showLogin ? 1 : 0,
                      duration: const Duration(milliseconds: 500),
                      child: Column(children: [
                        TextField(
                          controller: _nameCtrl,
                          style: const TextStyle(color: AppTheme.textPrimary),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _login(),
                          decoration: const InputDecoration(
                            hintText: 'Ismingizni kiriting',
                            prefixIcon: Icon(Icons.person_outline, color: AppTheme.primary),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity, height: 52,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                  colors: [AppTheme.primary, AppTheme.accent]),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [BoxShadow(
                                color: AppTheme.primary.withOpacity(.35),
                                blurRadius: 16, offset: const Offset(0, 6),
                              )],
                            ),
                            child: ElevatedButton(
                              onPressed: _showLogin ? _login : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor:     Colors.transparent,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24)),
                              ),
                              child: const Text('Kirish',
                                  style: TextStyle(fontSize: 16,
                                      fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                          ),
                        ),
                      ]),
                    ),

                    if (!_showLogin) ...[
                      const SizedBox(height: 8),
                      const CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
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