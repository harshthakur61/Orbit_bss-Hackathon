import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/crew_presence_constants.dart';
import '../../../core/theme.dart';
import '../../../providers/crew_presence_providers.dart';

/// Prominent status pill indicating crew availability (Available, Busy, Offline).
class CrewStatusPill extends ConsumerWidget {
  final VoidCallback? onTap;

  const CrewStatusPill({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(currentCrewPresenceStatusProvider);
    Color bg;
    Color fg;
    Color dot;

    switch (status) {
      case CrewPresenceStatus.available:
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF1E9E5A);
        dot = const Color(0xFF1E9E5A);
        break;
      case CrewPresenceStatus.busy:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        dot = const Color(0xFFD97706);
        break;
      case CrewPresenceStatus.offline:
        bg = const Color(0xFFFFEBEE);
        fg = AppColors.danger;
        dot = AppColors.danger;
        break;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: fg.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              status.label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
