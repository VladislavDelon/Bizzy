import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Сезон года по текущему месяцу — определяет анимацию
/// фона сайта: снег, лепестки, пыльца или листопад.
enum Season { winter, spring, summer, autumn }

Season seasonOf(DateTime date) => switch (date.month) {
  12 || 1 || 2 => Season.winter,
  >= 3 && <= 5 => Season.spring,
  >= 6 && <= 8 => Season.summer,
  _ => Season.autumn,
};

/// Анимированный сезонный фон для веб-версии на широких
/// экранах: сезонный градиент + падающие/парящие частицы.
/// Ставится позади контента — внутренние Scaffold в режиме
/// «Полный сайт» прозрачные, чтобы фон просвечивал.
class SeasonalBackdrop extends StatefulWidget {
  const SeasonalBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<SeasonalBackdrop> createState() => _SeasonalBackdropState();
}

class _SeasonalBackdropState extends State<SeasonalBackdrop>
    with SingleTickerProviderStateMixin {
  // Один цикл анимации — 12 секунд; позиции частиц считаются
  // по t∈0..1 и зацикливаются по модулю — шва нет.
  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _SeasonPainter(
                season: seasonOf(DateTime.now()),
                dark: dark,
                ticker: _ticker,
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Рисует сезонный градиент и слой частиц.
class _SeasonPainter extends CustomPainter {
  _SeasonPainter({
    required this.season,
    required this.dark,
    required this.ticker,
  }) : super(repaint: ticker);

  final Season season;
  final bool dark;
  final AnimationController ticker;

  double get t => ticker.value;

  /// Детерминированный «рандом» по индексу частицы.
  static double _hash(int i, int k) {
    final v = math.sin(i * 12.9898 + k * 78.233) * 43758.5453;
    return v - v.floorToDouble();
  }

  List<Color> get _bg => switch ((season, dark)) {
    (Season.winter, true) => [const Color(0xFF0D1526), const Color(0xFF04070D)],
    (Season.winter, false) => [
      const Color(0xFFEAF2FB),
      const Color(0xFFFDFEFF),
    ],
    (Season.spring, true) => [const Color(0xFF0F1D14), const Color(0xFF050B07)],
    (Season.spring, false) => [
      const Color(0xFFE8F5E9),
      const Color(0xFFF3FBF4),
    ],
    (Season.summer, true) => [const Color(0xFF1E1A08), const Color(0xFF0B0903)],
    (Season.summer, false) => [
      const Color(0xFFFFF9E0),
      const Color(0xFFFFF4D6),
    ],
    (Season.autumn, true) => [const Color(0xFF231507), const Color(0xFF0D0803)],
    _ => [const Color(0xFFFFF3E0), const Color(0xFFFFE8CC)],
  };

  static const _leafColors = [
    Color(0xFFE65100),
    Color(0xFFFFB300),
    Color(0xFFD84315),
    Color(0xFFF9A825),
  ];
  static const _petalColors = [
    Color(0xFFF8BBD0),
    Color(0xFFF48FB1),
    Color(0xFFFCE4EC),
  ];

  void _particle(
    Canvas canvas,
    Size size,
    int i, {
    required double minSpeed,
    required double maxSpeed,
    required double swayAmp,
    required bool falls,
  }) {
    final h = _hash(i, 0) * size.width;
    final speed = minSpeed + _hash(i, 1) * (maxSpeed - minSpeed);
    var y = (_hash(i, 2) + (falls ? t : -t) * speed) % 1.15;
    y = (y - 0.075) * size.height;
    final phase = _hash(i, 3) * math.pi * 2;
    final sway =
        math.sin(t * math.pi * 2 * (0.5 + _hash(i, 4)) + phase) * swayAmp;
    final x = (h + sway) % size.width;
    final offset = Offset(x < 0 ? x + size.width : x, y);

    switch (season) {
      case Season.winter:
        final r = 1.4 + _hash(i, 5) * 2.8;
        final alpha = 0.30 + _hash(i, 6) * 0.45;
        canvas.drawCircle(
          offset,
          r,
          Paint()
            ..color = (dark ? Colors.white : const Color(0xFF90A4AE))
                .withValues(alpha: alpha),
        );
      case Season.summer:
        // Пыльца/светлячки: тёплые мягкие точки, парят вверх.
        final r = 1.8 + _hash(i, 5) * 3.4;
        final alpha = 0.18 + _hash(i, 6) * 0.35;
        canvas.drawCircle(
          offset,
          r * 2.6,
          Paint()
            ..color = const Color(0xFFFFE082).withValues(alpha: alpha * 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawCircle(
          offset,
          r,
          Paint()..color = const Color(0xFFFFE082).withValues(alpha: alpha),
        );
      case Season.spring:
        final s = 4.0 + _hash(i, 5) * 5.5;
        final alpha = 0.45 + _hash(i, 6) * 0.4;
        final angle = phase + t * math.pi * 2 * (_hash(i, 7) - 0.5);
        canvas.save();
        canvas.translate(offset.dx, offset.dy);
        canvas.rotate(angle);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: s * 1.6, height: s),
          Paint()
            ..color = _petalColors[(i % _petalColors.length)].withValues(
              alpha: alpha,
            ),
        );
        canvas.restore();
      case Season.autumn:
        final s = 5.0 + _hash(i, 5) * 8.0;
        final alpha = 0.4 + _hash(i, 6) * 0.45;
        final angle = phase + t * math.pi * 2 * (0.4 + _hash(i, 7));
        canvas.save();
        canvas.translate(offset.dx, offset.dy);
        canvas.rotate(angle);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: s, height: s * 0.62),
          Paint()
            ..color = _leafColors[(i % _leafColors.length)].withValues(
              alpha: alpha,
            ),
        );
        canvas.restore();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Сезонный градиент.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _bg,
        ).createShader(Offset.zero & size),
    );

    const count = 55;
    switch (season) {
      case Season.winter:
        for (var i = 0; i < count; i++) {
          _particle(
            canvas,
            size,
            i,
            minSpeed: 0.18,
            maxSpeed: 0.42,
            swayAmp: 26,
            falls: true,
          );
        }
      case Season.spring:
        for (var i = 0; i < count; i++) {
          _particle(
            canvas,
            size,
            i,
            minSpeed: 0.22,
            maxSpeed: 0.5,
            swayAmp: 60,
            falls: true,
          );
        }
      case Season.summer:
        for (var i = 0; i < count; i++) {
          _particle(
            canvas,
            size,
            i,
            minSpeed: 0.10,
            maxSpeed: 0.26,
            swayAmp: 44,
            falls: false,
          );
        }
      case Season.autumn:
        for (var i = 0; i < count; i++) {
          _particle(
            canvas,
            size,
            i,
            minSpeed: 0.28,
            maxSpeed: 0.6,
            swayAmp: 55,
            falls: true,
          );
        }
    }

    // Лёгкая вуаль поверх частиц — текст и карточки читаются.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = (dark ? Colors.black : Colors.white).withValues(
          alpha: dark ? 0.35 : 0.30,
        ),
    );
  }

  @override
  bool shouldRepaint(_SeasonPainter oldDelegate) => true;
}
