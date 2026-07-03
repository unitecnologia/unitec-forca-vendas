import 'package:flutter/material.dart';

import 'brand.dart';

/// Card do menu principal com ícone em estilo 3D e cantos bem arredondados.
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

  static const _radius = 22.0;

  @override
  Widget build(BuildContext context) {
    final opacity = emDesenvolvimento ? 0.62 : 1.0;
    final cardTop = Color.lerp(const Color(0xFFF7FAFC), color, destaque ? 0.16 : 0.11)!;
    final cardBottom = Color.lerp(const Color(0xFFE8EEF4), color, destaque ? 0.24 : 0.17)!;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: destaque ? 0.22 : 0.14),
            blurRadius: destaque ? 14 : 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: color.withValues(alpha: 0.14),
            highlightColor: color.withValues(alpha: 0.07),
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cardTop, cardBottom],
                ),
                border: Border.all(
                  color: color.withValues(alpha: destaque ? 0.32 : 0.18),
                  width: destaque ? 1.3 : 1,
                ),
              ),
              child: Opacity(
                opacity: opacity,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
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
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.construction_rounded, size: 14, color: Colors.orange.shade800),
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
    final radius = size * 0.32;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [light, mid, dark],
            stops: const [0.0, 0.55, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: size * 0.16,
              offset: Offset(0, size * 0.08),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              top: size * 0.14,
              left: size * 0.18,
              right: size * 0.18,
              child: Container(
                height: size * 0.16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.42),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Icon(
              icon,
              color: Colors.white,
              size: size * 0.5,
              shadows: const [
                Shadow(color: Color(0x55000000), blurRadius: 3, offset: Offset(0, 1.5)),
              ],
            ),
          ],
        ),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.lerp(color, Colors.white, 0.2)!, color],
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
