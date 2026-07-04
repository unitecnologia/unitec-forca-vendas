import 'package:flutter/material.dart';

import 'brand.dart';

/// Card do menu — estilo “banco”: fundo branco sobre canvas cinza, ícone no canto.
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

  static const _radius = 12.0;

  @override
  Widget build(BuildContext context) {
    final opacity = emDesenvolvimento ? 0.5 : 1.0;

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
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(_radius),
          splashColor: Brand.blue.withValues(alpha: 0.06),
          highlightColor: Brand.blue.withValues(alpha: 0.03),
          child: Ink(
            decoration: Brand.surfaceCard(radius: _radius),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  top: 10,
                  right: 10,
                  child: Icon(
                    icon,
                    size: 28,
                    color: color.withValues(alpha: 0.82),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Brand.textPrimary,
                      height: 1.15,
                    ),
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
      return [const Positioned(top: 8, left: 8, child: _HomeMenuTag(text: 'Novo', color: Brand.green))];
    }
    if (badge != null) {
      return [Positioned(top: 8, left: 8, child: _HomeMenuTag(text: badge!, color: const Color(0xFFDC2626)))];
    }
    if (emDesenvolvimento) {
      return [
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(6),
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
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: Brand.cardShadow,
              border: const Border(
                left: BorderSide(color: Brand.blue, width: 4),
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 10,
                  right: 10,
                  child: Icon(icon, size: 30, color: Brand.blue.withValues(alpha: 0.85)),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Brand.textPrimary,
                      height: 1.15,
                    ),
                  ),
                ),
                if (badge != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _HomeMenuTag(text: badge!, color: const Color(0xFFDC2626)),
                  ),
                if (emDesenvolvimento)
                  const Positioned(
                    top: 8,
                    left: 8,
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

/// Ícone em quadrado suave (resumo / sync).
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
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
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
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}
