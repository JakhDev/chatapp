import 'package:flutter/material.dart';
import 'package:chatapp/theme/AppTheme.dart';

class AvatarWidget extends StatelessWidget {
  final String name;
  final double size;
  final bool   isOnline;
  final bool   isGroup;

  const AvatarWidget({
    super.key,
    required this.name,
    required this.size,
    this.isOnline = false,
    this.isGroup  = false,
  });

  static const _palette = [
    Color(0xFF6C63FF), Color(0xFF00D4AA), Color(0xFFFF6584),
    Color(0xFFFFB347), Color(0xFF4FC3F7), Color(0xFFAB47BC),
    Color(0xFF26A69A), Color(0xFFEF5350),
  ];

  Color get _bg => isGroup
      ? const Color(0xFF4A42D6)
      : _palette[name.isEmpty ? 0 : name.codeUnitAt(0) % _palette.length];

  String get _initials {
    final p = name.trim().split(' ');
    if (p.length >= 2) return '${p[0][0]}${p[1][0]}'.toUpperCase();
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [_bg, _bg.withOpacity(.7)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(color: _bg.withOpacity(.3),
            blurRadius: 8, offset: const Offset(0, 2)),
      ],
    ),
    child: Center(
      child: isGroup
          ? Icon(Icons.group, color: Colors.white, size: size * .48)
          : Text(_initials,
          style: TextStyle(color: Colors.white,
              fontWeight: FontWeight.w700, fontSize: size * .38)),
    ),
  );
}