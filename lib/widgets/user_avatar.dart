import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../theme/app_colors.dart';
import 'pressable.dart';

/// Avatar tròn chữ cái đầu của người dùng hiện tại. Khi có [onTap], vùng chạm
/// luôn ≥ 44px dù avatar nhỏ hơn.
class UserAvatar extends StatelessWidget {
  final double size;
  final VoidCallback? onTap;

  const UserAvatar({super.key, this.size = 32, this.onTap});

  String get _initial {
    final user = AuthRepository.instance.cachedUser;
    final source = (user?.displayName ?? user?.email ?? 'U').trim();
    return (source.isEmpty ? 'U' : source[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6366F1), AppColors.accentFill],
        ),
      ),
      child: Text(
        _initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );

    if (onTap == null) return avatar;
    return Pressable(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Center(child: avatar),
        ),
      ),
    );
  }
}
