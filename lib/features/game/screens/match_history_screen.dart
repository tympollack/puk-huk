import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/puk_huk_theme.dart';
import '../../../services/match_history_service.dart';
import 'game_screen.dart';

class MatchHistoryScreen extends ConsumerWidget {
  const MatchHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(matchHistoryProvider);

    return Scaffold(
      backgroundColor: PukHukTheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'MATCH HISTORY',
          style: GoogleFonts.orbitron(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: PukHukTheme.primary,
            letterSpacing: 2,
          ),
        ),
        iconTheme: IconThemeData(color: PukHukTheme.primary),
      ),
      body: historyAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text(
                'NO MATCHES FOUND',
                style: GoogleFonts.orbitron(
                  color: PukHukTheme.textSecondary,
                  fontSize: 16,
                  letterSpacing: 2,
                ),
              ),
            );
          }

          final activeGames = items.where((i) => !i.isCompleted).toList();
          final completedGames = items.where((i) => i.isCompleted).toList();

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              if (activeGames.isNotEmpty) ...[
                _SectionHeader(title: 'ACTIVE GAMES'),
                const SizedBox(height: 8),
                ...activeGames.map((item) => _MatchCard(item: item)),
                const SizedBox(height: 24),
              ],
              if (completedGames.isNotEmpty) ...[
                _SectionHeader(title: 'COMPLETED GAMES'),
                const SizedBox(height: 8),
                ...completedGames.map((item) => _MatchCard(item: item)),
              ],
            ],
          );
        },
        loading: () => Center(child: CircularProgressIndicator(color: PukHukTheme.primary)),
        error: (e, st) => Center(
          child: Text(
            'ERROR LOADING HISTORY',
            style: GoogleFonts.orbitron(color: Colors.red),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.orbitron(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: PukHukTheme.textSecondary,
        letterSpacing: 2,
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final MatchHistoryItem item;
  const _MatchCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final scores = item.state.scores;
    // We don't have localPlayerId here easily without authProvider, but we know opponent is populated.
    final opponentScore = scores[item.opponent.uid] ?? 0;
    // My score is the other one
    final myScore = scores.entries.firstWhere((e) => e.key != item.opponent.uid, orElse: () => const MapEntry('', 0)).value;

    final isWinner = myScore > opponentScore;
    final isDraw = myScore == opponentScore;
    final statusText = item.isCompleted 
        ? (isWinner ? 'VICTORY' : (isDraw ? 'DRAW' : 'DEFEAT')) 
        : (item.isMyTurn ? 'YOUR TURN' : 'OPPONENT TURN');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Color(0xFF161A22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isCompleted 
              ? (isWinner ? PukHukTheme.primary.withValues(alpha: 0.5) : Colors.red.withValues(alpha: 0.5))
              : (item.isMyTurn ? PukHukTheme.primary : Colors.white12),
          width: item.isMyTurn ? 2 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: PukHukTheme.primary,
          child: Text(
            (item.opponent.displayName).substring(0, 1).toUpperCase(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
        title: Text(
          item.opponent.displayName.toUpperCase(),
          style: GoogleFonts.orbitron(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            statusText,
            style: GoogleFonts.orbitron(
              fontSize: 12,
              color: item.isCompleted 
                  ? (isWinner ? PukHukTheme.primary : Colors.red) 
                  : (item.isMyTurn ? PukHukTheme.primary : PukHukTheme.textSecondary),
            ),
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$myScore - $opponentScore',
              style: GoogleFonts.orbitron(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        onTap: () {
          if (!item.isCompleted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => GameScreen(sessionId: item.sessionId)),
            );
          } else {
            // Future: Show final match summary screen. For now just do nothing.
          }
        },
      ),
    );
  }
}
