import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/puk_huk_theme.dart';
import '../../../data/models/player_model.dart';
import '../../../services/leaderboard_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LobbyScreen — central hub: find matches, see active tournaments,
// quick stats summary, nav to Profile/Achievements.
// Layout mirrors War: Second Wind's hub-and-card structure.
// ─────────────────────────────────────────────────────────────────────────────
class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(currentPlayerProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('LOBBY'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push(Routes.profile),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Player summary card ─────────────────────────────────────
            _PlayerSummaryCard(player: player),
            const SizedBox(height: 20),

            // ── Quick actions ────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _ActionTile(
                    icon: Icons.bolt,
                    label: 'QUICK MATCH',
                    color: PukHukTheme.primary,
                    onTap: () => context.push(Routes.matchmaking),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionTile(
                    icon: Icons.emoji_events_outlined,
                    label: 'ACHIEVEMENTS',
                    color: PukHukTheme.eloGold,
                    onTap: () => context.push(Routes.achievements),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Active tournaments section ──────────────────────────────
            Text('ACTIVE TOURNAMENTS', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            const _TournamentListPlaceholder(),

            const SizedBox(height: 24),
            Text('GLOBAL LEADERBOARD', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            const _LeaderboardPreview(),
          ],
        ),
      ),
    );
  }
}

class _PlayerSummaryCard extends StatelessWidget {
  final PlayerModel? player;
  const _PlayerSummaryCard({required this.player});

  @override
  Widget build(BuildContext context) {
    final elo = player?.elo ?? 1000;
    final tier = player?.tier ?? 'bronze';
    final wins = player?.wins ?? 0;
    final losses = player?.losses ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: PukHukTheme.tierColors[tier] ?? PukHukTheme.primary,
              child: Text(
                (player?.displayName ?? 'P').substring(0, 1).toUpperCase(),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player?.displayName ?? 'Player',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.shield, size: 14, color: PukHukTheme.tierColors[tier]),
                      const SizedBox(width: 4),
                      Text(
                        tier.toUpperCase(),
                        style: GoogleFonts.orbitron(
                          fontSize: 11,
                          color: PukHukTheme.tierColors[tier],
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('$wins W - $losses L',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$elo',
                  style: GoogleFonts.orbitron(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: PukHukTheme.eloGold,
                  ),
                ),
                Text('ELO', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.orbitron(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TournamentListPlaceholder extends StatelessWidget {
  const _TournamentListPlaceholder();

  @override
  Widget build(BuildContext context) {
    // TODO: wire to /tournaments collection stream once implemented
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No active tournaments. Check back soon!',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _LeaderboardPreview extends ConsumerWidget {
  const _LeaderboardPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streamAsync = ref.watch(globalLeaderboardProvider);

    return Card(
      child: streamAsync.when(
        data: (entries) {
          if (entries.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No ranked players yet.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          }
          final top5 = entries.take(5).toList();
          return Column(
            children: top5
                .map((e) => ListTile(
                      leading: Text(
                        '#${e.rank}',
                        style: GoogleFonts.orbitron(
                          fontWeight: FontWeight.bold,
                          color: e.rank <= 3 ? PukHukTheme.eloGold : PukHukTheme.textSecondary,
                        ),
                      ),
                      title: Text(e.displayName),
                      trailing: Text(
                        '${e.elo} ELO',
                        style: GoogleFonts.orbitron(
                          color: PukHukTheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ))
                .toList(),
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(20),
          child: Text('Error loading leaderboard: $e'),
        ),
      ),
    );
  }
}
