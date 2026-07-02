import 'package:flutter/material.dart';

import 'brand.dart';

/// Card do menu principal com ícone em estilo 3D e fundo menos “branco chapado”.
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

  @override
  Widget build(BuildContext context) {
    final opacity = emDesenvolvimento ? 0.62 : 1.0;
    final cardTop = Color.lerp(const Color(0xFFF8FAFC), color, destaque ? 0.14 : 0.09)!;
    final cardBottom = Color.lerp(const Color(0xFFEEF2F7), color, destaque ? 0.22 : 0.15)!;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cardTop, cardBottom],
            ),
            border: Border.all(
              color: color.withValues(alpha: destaque ? 0.35 : 0.2),
              width: destaque ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.28),
                blurRadius: destaque ? 16 : 12,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.85),
                blurRadius: 0,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Opacity(
            opacity: opacity,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HomeMenuIcon3D(icon: icon, color: color),
                      const Spacer(),
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: destaque ? FontWeight.w700 : FontWeight.w600,
                          color: const Color(0xFF1A237E).withValues(alpha: 0.92),
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
                if (novo)
                  const Positioned(top: 8, right: 8, child: _HomeMenuTag(text: 'Novo', color: Brand.green)),
                if (badge != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _HomeMenuTag(text: badge!, color: Colors.redAccent),
                  ),
                if (emDesenvolvimento)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withValues(alpha: 0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(Icons.construction_rounded, size: 14, color: Colors.orange.shade800),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeMenuIcon3D extends StatelessWidget {
  const HomeMenuIcon3D({super.key, required this.icon, required this.color, this.size = 46});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final light = Color.lerp(color, Colors.white, 0.42)!;
    final mid = color;
    final dark = Color.lerp(color, Colors.black, 0.18)!;
    final radius = size * 0.304;
    final iconSize = size * 0.52;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, mid, dark],
          stops: const [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: size * 0.22,
            offset: Offset(0, size * 0.11),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.35),
            blurRadius: 2,
            offset: const Offset(-1.5, -1.5),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: size * 0.15,
            left: size * 0.22,
            right: size * 0.22,
            child: Container(
              height: size * 0.17,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius * 0.45),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.45),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Icon(
            icon,
            color: Colors.white,
            size: iconSize,
            shadows: const [
              Shadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeMenuTag extends StatelessWidget {
  const _HomeMenuTag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color.lerp(color, Colors.white, 0.2)!, color],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
