import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/frog_completion_events.dart';

class FrogCompletionCelebrationHost extends StatefulWidget {
  final Widget child;

  const FrogCompletionCelebrationHost({super.key, required this.child});

  @override
  State<FrogCompletionCelebrationHost> createState() =>
      _FrogCompletionCelebrationHostState();
}

class _FrogCompletionCelebrationHostState
    extends State<FrogCompletionCelebrationHost> {
  FrogCompletionEvent? _event;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    FrogCompletionCelebrations.instance.notifier.addListener(_onCelebration);
  }

  @override
  void dispose() {
    FrogCompletionCelebrations.instance.notifier.removeListener(_onCelebration);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onCelebration() {
    final event = FrogCompletionCelebrations.instance.notifier.value;
    if (event == null || !mounted) return;

    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        media?.accessibleNavigation == true || media?.disableAnimations == true;
    setState(() => _event = event);
    _hideTimer?.cancel();
    _hideTimer = Timer(Duration(milliseconds: reduceMotion ? 1500 : 2600), () {
      if (mounted && _event == event) setState(() => _event = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        media?.accessibleNavigation == true || media?.disableAnimations == true;
    return Stack(
      children: [
        widget.child,
        if (event != null)
          Positioned.fill(
            child: IgnorePointer(
              child: _FrogCompletionCelebrationOverlay(
                key: ValueKey(event.seed),
                event: event,
                reduceMotion: reduceMotion,
              ),
            ),
          ),
      ],
    );
  }
}

class _FrogCompletionCelebrationOverlay extends StatefulWidget {
  final FrogCompletionEvent event;
  final bool reduceMotion;

  const _FrogCompletionCelebrationOverlay({
    super.key,
    required this.event,
    required this.reduceMotion,
  });

  @override
  State<_FrogCompletionCelebrationOverlay> createState() =>
      _FrogCompletionCelebrationOverlayState();
}

class _FrogCompletionCelebrationOverlayState
    extends State<_FrogCompletionCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2300),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reduceMotion) {
      return ColoredBox(
        color: Colors.black.withValues(alpha: 0.10),
        child: Center(child: _AchievementCard(event: widget.event)),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final p = _controller.value;
        final badgeIn = Curves.easeOutBack.transform((p / 0.24).clamp(0, 1));
        final badgeOut = p > 0.78
            ? Curves.easeIn.transform(((1 - p) / 0.22).clamp(0, 1))
            : 1.0;
        return CustomPaint(
          painter: _FrogFireworksPainter(progress: p, seed: widget.event.seed),
          child: Center(
            child: Opacity(
              opacity: badgeOut.toDouble(),
              child: Transform.scale(
                scale: 0.84 + badgeIn * 0.16,
                child: _AchievementCard(event: widget.event),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AchievementCard extends StatelessWidget {
  final FrogCompletionEvent event;

  const _AchievementCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? const Color(0xFF10251A)
        : const Color(0xFFF0FDF4);
    final borderColor = isDark
        ? AppColors.frog.withValues(alpha: 0.56)
        : AppColors.frog.withValues(alpha: 0.30);
    final primaryText = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final secondaryText = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    return Container(
      constraints: const BoxConstraints(maxWidth: 330),
      margin: const EdgeInsets.symmetric(horizontal: 28),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.frog.withValues(alpha: 0.32),
            blurRadius: 36,
            spreadRadius: 4,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF22C55E), Color(0xFFFACC15)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Frog hoàn thành!',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.frog,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Một việc quan trọng vừa được khép lại.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FrogFireworksPainter extends CustomPainter {
  final double progress;
  final int seed;

  const _FrogFireworksPainter({required this.progress, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed + 917);
    final backdropAlpha =
        math.sin(progress * math.pi).clamp(0.0, 1.0).toDouble() * 0.16;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: backdropAlpha),
    );

    _paintCenterGlow(canvas, size);
    _paintBursts(canvas, size, random);
    _paintConfetti(canvas, size, random);
  }

  void _paintCenterGlow(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.44);
    final pulse = Curves.easeOut.transform((progress / 0.42).clamp(0, 1));
    final fade = progress > 0.70
        ? ((1 - progress) / 0.30).clamp(0.0, 1.0)
        : 1.0;
    final radius = size.shortestSide * (0.12 + 0.16 * pulse);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.frog.withValues(alpha: 0.24 * fade),
            AppColors.streakGold.withValues(alpha: 0.12 * fade),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  void _paintBursts(Canvas canvas, Size size, math.Random random) {
    const colors = [
      AppColors.frog,
      AppColors.streakGold,
      AppColors.tagCyan,
      AppColors.tagPink,
      Color(0xFFFFFFFF),
    ];

    for (var burst = 0; burst < 7; burst++) {
      final delay = burst * 0.055;
      final local = ((progress - delay) / 0.72).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final center = Offset(
        size.width * (0.14 + random.nextDouble() * 0.72),
        size.height * (0.12 + random.nextDouble() * 0.50),
      );
      final eased = Curves.easeOutCubic.transform(local);
      final radius =
          size.shortestSide * (0.10 + random.nextDouble() * 0.18) * eased;
      final alpha = (1 - local).clamp(0.0, 1.0).toDouble();

      for (var i = 0; i < 28; i++) {
        final angle = math.pi * 2 * (i / 28) + random.nextDouble() * 0.12;
        final distance = radius * (0.72 + random.nextDouble() * 0.48);
        final direction = Offset(math.cos(angle), math.sin(angle));
        final start = center + direction * distance * 0.46;
        final end = center + direction * distance;
        final paint = Paint()
          ..color = colors[(i + burst) % colors.length].withValues(alpha: alpha)
          ..strokeWidth = 2.1 + random.nextDouble() * 1.6
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(start, end, paint);
      }
    }
  }

  void _paintConfetti(Canvas canvas, Size size, math.Random random) {
    const colors = [
      AppColors.frog,
      AppColors.streakGold,
      AppColors.tagCyan,
      AppColors.tagPink,
      AppColors.primaryDark,
      Colors.white,
    ];
    for (var i = 0; i < 120; i++) {
      final delay = random.nextDouble() * 0.32;
      final local = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final fall = Curves.easeIn.transform(local);
      final x =
          size.width * random.nextDouble() +
          math.sin((local * math.pi * 2) + i) * (18 + random.nextDouble() * 34);
      final y =
          -24 + size.height * (0.10 + 0.96 * fall) + random.nextDouble() * 36;
      final width = 5 + random.nextDouble() * 8;
      final height = 9 + random.nextDouble() * 16;
      final opacity = local > 0.76 ? ((1 - local) / 0.24).clamp(0.0, 1.0) : 1.0;
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: opacity);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(random.nextDouble() * math.pi + local * math.pi * 5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: width, height: height),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FrogFireworksPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.seed != seed;
  }
}
