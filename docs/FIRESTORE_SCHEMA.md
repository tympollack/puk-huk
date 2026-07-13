# Puk Huk — Database Schema & Architecture

This mirrors the WSW player-hub pattern: **Firestore** for durable, queryable
data (profiles, match history, leaderboards, matchmaking queue) and
**Firebase Realtime Database (RTDB)** for the live, high-frequency game state
that needs sub-50ms round-trip latency.

## Why two databases?

| Concern                     | Firestore                          | RTDB                              |
|------------------------------|-------------------------------------|------------------------------------|
| Avg write→listener latency   | ~100–300ms                          | ~20–50ms                           |
| Query model                  | Rich (where/orderBy/composite idx)  | Path-based, shallow                |
| Best for                     | Profiles, matches, leaderboards     | Puck positions, live turn stats    |
| Offline support               | Good                                 | Good (delta sync built for games)  |

Game-session writes (puck x/y/velocity at 20Hz) would needlessly burn
Firestore's per-document-write pricing and add latency. RTDB's flat,
high-throughput model is purpose-built for this.

---

## Firestore Collections

### `/users/{uid}`  — Player Hub (mirrors WSW)
```
uid               string
displayName       string
email             string
avatarUrl         string?
elo               number   (default 1000)
tier              string   (bronze | silver | gold | diamond)
wins              number
losses            number
totalGames        number
winStreak         number
bestWinStreak     number
highestPuckSpeed  number   (m/s, all-time PB)
longestPuckDistance number (m, all-time PB)
totalPucksThrown  number
achievements      string[] (unlocked achievement IDs)
isOnline          boolean
createdAt         timestamp
lastSeen          timestamp
```

### `/matches/{matchId}` — Persistent match record
```
matchId             string
player1Id           string
player2Id           string
player1EloAtTime    number   (snapshot at creation, for fair ELO calc)
player2EloAtTime    number
status              string   (scheduled | active | completed | cancelled)
winnerId            string?
sessionId           string   (FK → RTDB /game_sessions/{sessionId})
player1EloChange    number
player2EloChange    number
player1ScoreFinal   number
player2ScoreFinal   number
scheduledAt          timestamp
startedAt           timestamp
completedAt         timestamp
```
Indexes needed: composite on `(player1Id, status, completedAt desc)` and
`(player2Id, status, completedAt desc)` for match-history queries, or use
the `Filter.or()` approach in `PlayerRepository.watchMatchHistory` with a
single composite index on `(status, completedAt desc)`.

### `/matchmaking_queue/{uid}` — Active search pool
```
playerId      string
elo           number
gamesPlayed   number
status        string  (searching | matched | timeout)
matchId       string?
joinedAt      timestamp
```
Ephemeral — documents are deleted on cancel/match/timeout. Consider a
scheduled Cloud Function to purge stale entries (e.g., app killed mid-search).

### `/leaderboards/global/players/{uid}` — Denormalized rankings
```
uid           string
displayName   string
elo           number
wins          number
tier          string
avatarUrl     string?
updatedAt     timestamp
```
Denormalized copy of relevant `/users` fields, written transactionally by
`MatchmakingService.resolveMatch()` alongside the user document update.
This avoids expensive full-collection aggregation when rendering the
leaderboard UI — read cost stays O(limit), not O(all users).

Composite index required: `elo desc` (single-field, auto-indexed) plus a
range index on `elo` for the "nearby rank" query in `LeaderboardService`.

### `/tournaments/{tournamentId}` — (scaffold for future bracket play)
```
tournamentId   string
name           string
status         string (upcoming | active | completed)
participantIds string[]
bracket        map     (round → [matchId, matchId, ...])
startTime      timestamp
```

---

## Realtime Database (RTDB) — Live Game State

### `/game_sessions/{sessionId}`
```
sessionId            string
player1Id            string
player2Id            string
status               string  (waiting | active | paused | completed | abandoned)
currentRound         number
currentTurnPlayerId  string
winnerId             string?

scores/
  {playerId}: number               // cumulative score, atomic ServerValue.increment

pucks/
  {puckId}/
    id            string
    ownerId       string
    x, y          number            // metres, board-local coords
    velocityX     number
    velocityY     number
    speed         number            // current |v|, m/s
    distance      number            // cumulative path length this throw
    isScored      boolean
    scoringZone   number            // 0 = none, 1-4 = zone, -1 = hanger
    updatedAt     ServerValue.TIMESTAMP

turn_stats/
  {playerId}/
    playerId          string
    turnPoints        number
    pucksRemaining    number  (0-4)
    highestSpeed      number
    lowestSpeed       number
    highestDistance   number
    lowestDistance    number

presence/
  {playerId}/
    online    boolean
    lastSeen  ServerValue.TIMESTAMP
```

**Why this shape?** Flat per-puck and per-player nodes let each client
subscribe only to what it needs (`.child('pucks').child(puckId)` for
opponent-puck interpolation) without re-parsing the entire session blob
on every tick — critical for the 20Hz physics sync loop.

`presence/{playerId}` uses RTDB's native `onDisconnect()` hook to mark a
player offline automatically if their connection drops mid-match, which
Firestore cannot do without a Cloud Function + heartbeat pattern.

---

## ELO Algorithm (mirrors WSW rating system)

Standard logistic ELO with adaptive K-factor:

```
E_winner = 1 / (1 + 10^((loserElo - winnerElo) / 400))
ΔWinner  = K * (1 - E_winner)
ΔLoser   = K * (0 - E_loser)
```

K-factor scales by experience:
- New players (<30 games): **K=40** — fast calibration
- Established (30–100 games): **K=20**
- Elite (>100 games AND >2000 ELO): **K=10** — stable top-of-ladder

Tier thresholds: Bronze (0+), Silver (1200+), Gold (1500+), Diamond (1800+).

## Matchmaking Algorithm

1. Player joins `/matchmaking_queue/{uid}` with current ELO.
2. Client listens for other `status: searching` entries within
   `±150 ELO` (expanding `+50` every 15s, capped at `±500`).
3. Best candidate chosen via compatibility score
   `exp(-|eloDiff| / 200)` (closer ELO = higher score).
4. Pairing executes inside a **Firestore transaction** that re-verifies
   the opponent is still `searching` before locking both records —
   this prevents the classic double-match race condition.
5. On success, both clients receive a `sessionId` and navigate to
   `GameScreen`, which calls `RealtimeSyncService.initSession()`.
