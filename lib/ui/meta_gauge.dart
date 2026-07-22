import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'brand.dart';

/// Formato compacto da meta (igual ERP: 20000 → 20.000).
String metaCompact(num value) {
  final v = value.round();
  final neg = v < 0;
  final s = v.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${neg ? '-' : ''}${buf.toString()}';
}

Color metaToneColor(double percent) {
  if (percent < 20) return const Color(0xFFEF4444);
  if (percent < 40) return const Color(0xFFF97316);
  if (percent < 60) return const Color(0xFFEAB308);
  if (percent < 80) return const Color(0xFF84CC16);
  return const Color(0xFF16A34A);
}

/// Relógio semicircular de meta (mesmo desenho do dashboard ERP).
class MetaGaugeCard extends StatelessWidget {
  const MetaGaugeCard({
    super.key,
    required this.meta,
    required this.realizado,
    required this.percentual,
    this.nome,
  });

  final double meta;
  final double realizado;
  final double percentual;
  final String? nome;

  String get _primeiroNome {
    final n = (nome ?? '').trim();
    if (n.isEmpty) return '';
    return n.split(RegExp(r'\s+')).first.toUpperCase();
  }

  String get _pctLabel {
    final p = percentual;
    final s = p.toStringAsFixed(1).replaceAll('.', ',');
    return '$s%';
  }

  @override
  Widget build(BuildContext context) {
    final tone = metaToneColor(percentual);
    final nome = _primeiroNome;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Meta do mês',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Brand.textPrimary,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _stat('META', metaCompact(meta))),
              Expanded(child: _stat('REAL', metaCompact(realizado), alignEnd: true)),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 132,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _MetaGaugePainter(percent: percentual, tone: tone),
                  ),
                ),
                Positioned(
                  bottom: 28,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: tone,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: tone.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      _pctLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (nome.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              nome,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: Brand.blue,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.black.withValues(alpha: 0.4),
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}

class _MetaGaugePainter extends CustomPainter {
  _MetaGaugePainter({required this.percent, required this.tone});

  final double percent;
  final Color tone;

  static const _zones = <(double, double, Color)>[
    (0.0, 0.2, Color(0xFFEF4444)),
    (0.2, 0.4, Color(0xFFF97316)),
    (0.4, 0.6, Color(0xFFEAB308)),
    (0.6, 0.8, Color(0xFF84CC16)),
    (0.8, 1.0, Color(0xFF16A34A)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final approxR = size.width * 0.36;
    final approxTrack = math.max(8.0, approxR * 0.2);
    final hubPad = (approxTrack / 2) + 6;
    final cy = math.max(hubPad, size.height - hubPad);
    final radius = math.min(approxR, math.max(16.0, cy - 6 - (approxTrack / 2)));
    final trackWidth = math.max(8.0, radius * 0.2);
    const start = math.pi;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = trackWidth + 3
      ..strokeCap = StrokeCap.butt
      ..color = const Color(0xFFD6DEE9);

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      start,
      math.pi,
      false,
      trackPaint,
    );

    for (final zone in _zones) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackWidth
        ..strokeCap = StrokeCap.butt
        ..color = zone.$3;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        start + (math.pi * zone.$1),
        math.pi * (zone.$2 - zone.$1),
        false,
        paint,
      );
    }

    final angle = _needleAngle(percent);
    final needleLength = radius * 0.72;
    _drawArrowNeedle(canvas, Offset(cx, cy), angle, needleLength, tone);
  }

  double _needleAngle(double pct) {
    const start = math.pi;
    const span = math.pi;
    final capped = math.max(0.0, pct);
    if (capped <= 100) {
      return start + (span * (capped / 100));
    }
    final over = math.min(0.1, ((capped - 100) / 100) * 0.35);
    return start + span + (span * over);
  }

  void _drawArrowNeedle(Canvas canvas, Offset center, double angle, double length, Color color) {
    final tip = Offset(
      center.dx + math.cos(angle) * length,
      center.dy + math.sin(angle) * length,
    );
    final head = math.max(7.0, length * 0.18);
    final shaft = math.max(2.2, length * 0.055);
    const headAngle = math.pi / 7;

    final shaftPaint = Paint()
      ..color = color
      ..strokeWidth = shaft
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final shaftEnd = Offset(
      tip.dx - math.cos(angle) * (head * 0.55),
      tip.dy - math.sin(angle) * (head * 0.55),
    );
    canvas.drawLine(center, shaftEnd, shaftPaint);

    final headPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - head * math.cos(angle - headAngle),
        tip.dy - head * math.sin(angle - headAngle),
      )
      ..lineTo(
        tip.dx - head * math.cos(angle + headAngle),
        tip.dy - head * math.sin(angle + headAngle),
      )
      ..close();
    canvas.drawPath(headPath, Paint()..color = color);

    final hub = math.max(3.5, length * 0.09);
    canvas.drawCircle(center, hub, Paint()..color = color);
    canvas.drawCircle(center, hub * 0.42, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _MetaGaugePainter oldDelegate) =>
      oldDelegate.percent != percent || oldDelegate.tone != tone;
}
