import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/puk_huk_theme.dart';
import '../providers/achievements_provider.dart';

const Map<String, IconData> _iconMap = {
  'emoji_events': Icons.emoji_events,
  'whatshot': Icons.whatshot,
  'speed': Icons.speed,
  'gps_fixed': Icons.gps_fixed,
  'military_tech': Icons.military_tech,
  'workspace_premium': Icons.workspace_premium,
  'diamond': Icons.diamond,
  'social_distance': Icons.social_distance,
};

// ─────────────────────────────────────────────────────────────────────────────
// AchievementsScreen — grid of unlockable milestones.
// ─────────────────────────────────────────────────────────────────────────────
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(unlockedAchievementIdsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('ACHIEVEMENTS')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.95,
        ),
        itemCount: kAchievementCatalogue.length,
        itemBuilder: (context, i) {
          final a = kAchievementCatalogue[i];
          final isUnlocked = unlocked.contains(a.id);
          return _AchievementCard(achievement: a, isUnlocked: isUnlocked);
        },
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  final Achievement achievement;
  final bool isUnlocked;

  const _AchievementCard({required this.achievement, required this.isUnlocked});

  @override
  Widget build(BuildContext context) {
    final color = isUnlocked ? PukHukTheme.eloGold : PukHukTheme.textSecondary;

    return Card(
      color: isUnlocked ? PukHukTheme.cardBg : PukHukTheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.12),
                border: Border.all(color: color.withOpacity(0.4)),
              ),
              child: Icon(
                _iconMap[achievement.iconName] ?? Icons.star,
                color: color,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              achievement.title,
              textAlign: TextAlign.center,
              style: GoogleFonts.orbitron(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isUnlocked ? PukHukTheme.textPrimary : PukHukTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              achievement.description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (!isUnlocked) ...[
              const SizedBox(height: 8),
              Icon(Icons.lock_outline, size: 14, color: PukHukTheme.textSecondary),
            ],
          ],
        ),
      ),
    );
  }
}
