import 'package:flutter/material.dart';

import 'brand.dart';

/// Card do menu principal — estilo flat (Material 3), sem gradientes nos tiles.
class HomeMenuCard extends StatelessWidget {
  const HomeMenuCard({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.destaque = false,
    this.emDesenvolvimento = false,
    this.novo = false,
    this.badge,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool destaque;
  final bool emDesenvolvimento;
  final bool novo;
  final String? badge;

  static const _radius = 16.0;

  @override
  Widget build(BuildContext context) {
    final opacity = emDesenvolvimento ? 0.55 : 1.0;

    if (destaque) {
      return _PrimaryMenuCard(
        label: label,
        icon: icon,
        onTap: onTap,
        opacity: opacity,
        badge: badge,
        emDesenvolvimento: emDesenvolvimento,
      );
    }

    return Opacity(
      opacity: opacity,
      child: Material(
        color: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        borderRadius: BorderRadius.circular(_radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(_radius),
          splashColor: color.withValues(alpha: 0.08),
          highlightColor: color.withValues(alpha: 0.04),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F0F2847),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HomeMenuIconFlat(icon: icon, color: color),
                      const Spacer(),
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                ..._badges(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _badges() {
    if (novo) {
      return [const Positioned(top: 10, right: 10, child: _HomeMenuTag(text: 'Novo', color: Brand.green))];
    }
    if (badge != null) {
      return [Positioned(top: 10, right: 10, child: _HomeMenuTag(text: badge!, color: const Color(0xFFDC2626)))];
    }
    if (emDesenvolvimento) {
      return [
        Positioned(
          top: 10,
          right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFDBA74)),
            ),
            child: const Text(
              'Em breve',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF9A3412)),
            ),
          ),
        ),
      ];
    }
    return [];
  }
}

class _PrimaryMenuCard extends StatelessWidget {
  const _PrimaryMenuCard({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.opacity,
    this.badge,
    this.emDesenvolvimento = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final double opacity;
  final String? badge;
  final bool emDesenvolvimento;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E5A9E), Color(0xFF0F2847)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x400F2847),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: Colors.white, size: 24),
                      ),
                      const Spacer(),
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge != null)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _HomeMenuTag(text: badge!, color: const Color(0xFFDC2626)),
                  ),
                if (emDesenvolvimento)
                  const Positioned(
                    top: 10,
                    right: 10,
                    child: _HomeMenuTag(text: 'Em breve', color: Color(0xFFEA580C)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ícone plano em círculo suave — sem efeito 3D/glossy.
class HomeMenuIconFlat extends StatelessWidget {
  const HomeMenuIconFlat({super.key, required this.icon, required this.color, this.size = 44});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}

/// Mantido para compatibilidade — delega ao ícone flat.
class HomeMenuIcon3D extends StatelessWidget {
  const HomeMenuIcon3D({super.key, required this.icon, required this.color, this.size = 46});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return HomeMenuIconFlat(icon: icon, color: color, size: size);
  }
}

class _HomeMenuTag extends StatelessWidget {
  const _HomeMenuTag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}
