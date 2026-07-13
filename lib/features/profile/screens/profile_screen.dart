import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/puk_huk_theme.dart';
import '../../../services/player_repository.dart';

import '../../../data/models/player_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ProfileScreen — player stats, ELO, tier badge, personal bests,
// and scrollable match history list.
// ─────────────────────────────────────────────────────────────────────────────
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerAsync = ref.watch(currentPlayerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PROFILE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: playerAsync.when(
        data: (player) {
          if (player == null) {
            return const Center(child: Text('No profile found'));
          }
          return _ProfileBody(player: player);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  final PlayerModel player;
  const _ProfileBody({required this.player});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(playerRepositoryProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Header: avatar + ELO + tier ─────────────────────────────────
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor:
                    PukHukTheme.tierColors[player.tier] ?? PukHukTheme.primary,
                child: Text(
                  player.displayName.substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Text(player.displayName, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                player.tier.toUpperCase(),
                style: GoogleFonts.orbitron(
                  fontSize: 12,
                  color: PukHukTheme.tierColors[player.tier],
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── ELO + record stat row ─────────────────────────────────────────
        Row(
          children: [
            Expanded(child: _StatBox(label: 'ELO', value: '${player.elo}', color: PukHukTheme.eloGold)),
            const SizedBox(width: 10),
            Expanded(child: _StatBox(label: 'WINS', value: '${player.wins}', color: PukHukTheme.success)),
            const SizedBox(width: 10),
            Expanded(child: _StatBox(label: 'LOSSES', value: '${player.losses}', color: PukHukTheme.danger)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatBox(
                label: 'BEST SPEED',
                value: '${player.highestPuckSpeed.toStringAsFixed(1)} m/s',
                color: PukHukTheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatBox(
                label: 'BEST DISTANCE',
                value: '${player.longestPuckDistance.toStringAsFixed(2)} m',
                color: PukHukTheme.secondary,
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),
        Text('MATCH HISTORY', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),

        StreamBuilder<List<Map<String, dynamic>>>(
          stream: repo.watchMatchHistory(player.uid),
          builder: (context, snapshot) {
            final matches = snapshot.data ?? [];
            if (matches.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('No matches played yet.',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              );
            }
            return Column(
              children: matches
                  .map((m) => _MatchHistoryTile(match: m, uid: player.uid))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatBox({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(value, style: GoogleFonts.orbitron(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _MatchHistoryTile extends StatelessWidget {
  final Map<String, dynamic> match;
  final String uid;
  const _MatchHistoryTile({required this.match, required this.uid});

  @override
  Widget build(BuildContext context) {
    final isPlayer1 = match['player1_id'] == uid;
    final won = match['winner_id'] == uid;
    final eloChange = isPlayer1 ? match['player1_elo_change'] : match['player2_elo_change'];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          won ? Icons.arrow_upward : Icons.arrow_downward,
          color: won ? PukHukTheme.success : PukHukTheme.danger,
        ),
        title: Text(won ? 'Victory' : 'Defeat'),
        subtitle: Text(
          '${match['player1_score_final']} - ${match['player2_score_final']}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Text(
          '${(eloChange ?? 0) >= 0 ? '+' : ''}$eloChange',
          style: GoogleFonts.orbitron(
            color: (eloChange ?? 0) >= 0 ? PukHukTheme.success : PukHukTheme.danger,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
