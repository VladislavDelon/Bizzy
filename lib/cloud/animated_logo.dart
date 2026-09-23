import 'package:flutter/material.dart';

/// Анимированный логотип с масштабом, поворотом, появлением
/// и золотым свечением. Общий виджет — используется на мобильном
/// экране выбора роли и на веб-странице входа.
class AnimatedLogo extends StatelessWidget {
  const AnimatedLogo({super.key, required this.animation, this.size = 220});

  final Animation<double> animation;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
      ),
    );
    final opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    final rotation = Tween<double>(begin: -0.15, end: 0.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack),
      ),
    );
    final glow = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Transform.rotate(
          angle: rotation.value,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.amber.withValues(alpha: 0.5 * glow.value),
                  blurRadius: 70 * glow.value,
                  spreadRadius: 25 * glow.value,
                ),
              ],
            ),
            child: Opacity(
              opacity: opacity.value,
              child: Transform.scale(scale: scale.value, child: child),
            ),
          ),
        );
      },
      child: Image.asset(
        'assets/icons/logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.calendar_month,
          size: size * 0.8,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
