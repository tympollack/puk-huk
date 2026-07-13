import 'dart:math' as math;

// ─────────────────────────────────────────────────────────────────────────────
// EloService — mirrors WSW rating algorithm.
//
// K-factor scales by experience to stabilize ratings:
//   • New players (< 30 games)  → K=40   fast calibration
//   • Established (30-100)      → K=20   standard drift
//   • Elite (>100 + ELO >2000)  → K=10   slow change at the top
//
// Expected score formula: E = 1 / (1 + 10^((oppElo - myElo) / 400))
// ─────────────────────────────────────────────────────────────────────────────
class EloService {
  // ── K-Factor constants ────────────────────────────────────────────────────
  static const int kNew = 40;
  static const int kEstablished = 20;
  static const int kElite = 10;

  // ── ELO floor/ceiling ─────────────────────────────────────────────────────
  static const int kMinElo = 100;
  static const int kMaxElo = 9999;

  /// Calculate both players' new ratings after a completed match.
  static EloResult calculateMatch({
    required int winnerElo,
    required int loserElo,
    required int winnerGamesPlayed,
    required int loserGamesPlayed,
  }) {
    final winnerK = _kFactor(winnerGamesPlayed, winnerElo);
    final loserK = _kFactor(loserGamesPlayed, loserElo);

    final expectedWinner = _expectedScore(winnerElo, loserElo);
    final expectedLoser = _expectedScore(loserElo, winnerElo);

    // Outcome: win = 1.0, loss = 0.0
    final winnerDelta = (winnerK * (1.0 - expectedWinner)).round();
    final loserDelta = (loserK * (0.0 - expectedLoser)).round();

    return EloResult(
      winnerNewElo: (winnerElo + winnerDelta).clamp(kMinElo, kMaxElo),
      loserNewElo: (loserElo + loserDelta).clamp(kMinElo, kMaxElo),
      winnerEloChange: winnerDelta,
      loserEloChange: loserDelta,
    );
  }

  /// Compatibility score for matchmaking pair quality (0.0–1.0).
  /// 1.0 = perfect mirror, decays exponentially with ELO gap.
  static double matchCompatibility(int elo1, int elo2) {
    final diff = (elo1 - elo2).abs().toDouble();
    return math.exp(-diff / 200.0);
  }

  /// Whether two players fall within acceptable ELO range.
  static bool isWithinRange(int elo1, int elo2, {int tolerance = 150}) =>
      (elo1 - elo2).abs() <= tolerance;

  /// ELO win probability for display purposes.
  static double winProbability(int myElo, int opponentElo) =>
      _expectedScore(myElo, opponentElo);

  // ── Private helpers ───────────────────────────────────────────────────────
  static double _expectedScore(int playerElo, int opponentElo) =>
      1.0 / (1.0 + math.pow(10, (opponentElo - playerElo) / 400.0));

  static int _kFactor(int gamesPlayed, int elo) {
    if (gamesPlayed < 30) return kNew;
    if (elo > 2000 && gamesPlayed > 100) return kElite;
    return kEstablished;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Result container
// ─────────────────────────────────────────────────────────────────────────────
class EloResult {
  final int winnerNewElo;
  final int loserNewElo;
  final int winnerEloChange;  // always positive
  final int loserEloChange;   // always negative

  const EloResult({
    required this.winnerNewElo,
    required this.loserNewElo,
    required this.winnerEloChange,
    required this.loserEloChange,
  });

  @override
  String toString() =>
      'EloResult(winner: +$winnerEloChange → $winnerNewElo, '
      'loser: $loserEloChange → $loserNewElo)';
}
