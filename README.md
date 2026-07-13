# Puk Huk 🏒

Real-time multiplayer digital shuffleboard, built with Flutter + Flame/Forge2D
physics and a Firebase backend (Firestore + RTDB) modeled on the WSW player-hub
architecture.

## Folder Structure

```
puk_huk/
├── lib/
│   ├── main.dart                          # App entry, Firebase init, orientation lock
│   │
│   ├── core/
│   │   ├── router/
│   │   │   └── app_router.dart            # go_router config, auth-gated redirects
│   │   ├── theme/
│   │   │   └── puk_huk_theme.dart         # Colors, typography, component themes
│   │   └── providers/
│   │       └── auth_provider.dart         # Firebase Auth + current-player stream
│   │
│   ├── data/
│   │   └── models/
│   │       ├── player_model.dart          # PlayerModel, LeaderboardEntry (freezed)
│   │       ├── match_model.dart           # MatchModel, QueueEntry (freezed)
│   │       └── game_session_model.dart    # GameSessionModel, PuckState, PlayerTurnStats
│   │
│   ├── services/                          # Backend integration layer
│   │   ├── elo_service.dart               # Pure ELO math (no I/O — easily unit-testable)
│   │   ├── matchmaking_service.dart        # Queue, pairing transaction, match resolution
│   │   ├── realtime_sync_service.dart      # RTDB game-state sync (20Hz puck updates)
│   │   ├── player_repository.dart          # Firestore CRUD for /users
│   │   └── leaderboard_service.dart        # Global/nearby leaderboard queries
│   │
│   └── features/
│       ├── auth/screens/login_screen.dart
│       │
│       ├── lobby/screens/lobby_screen.dart            # Hub: quick match, tournaments, leaderboard preview
│       │
│       ├── matchmaking/screens/matchmaking_screen.dart # Queue search UI, ELO tolerance display
│       │
│       ├── game/
│       │   ├── engine/
│       │   │   ├── puk_huk_game.dart       # Forge2D world, drag-to-launch gesture
│       │   │   ├── puck_component.dart     # Physics body + speed/rotation visual feedback
│       │   │   └── board_boundary_component.dart # Rails, scoring-zone geometry
│       │   ├── hud/
│       │   │   └── game_hud_widget.dart    # Full HUD overlay (score, turn pts, speed, distance)
│       │   ├── providers/
│       │   │   └── game_providers.dart     # Session stream + TurnStatsController
│       │   └── screens/
│       │       └── game_screen.dart        # Hosts GameWidget + HUD + exit/forfeit dialog
│       │
│       ├── profile/screens/profile_screen.dart        # ELO, tier, PBs, match history
│       │
│       └── achievements/
│           ├── providers/achievements_provider.dart   # Static catalogue + unlocked-set stream
│           └── screens/achievements_screen.dart       # Grid UI
│
├── firestore.rules                        # Security rules (owner-write, public-read patterns)
├── database.rules.json                    # RTDB rules (participant-only game session access)
├── docs/
│   └── FIRESTORE_SCHEMA.md                # Full schema reference + ELO/matchmaking algorithm docs
└── pubspec.yaml
```

## Architecture Highlights

**State management** — Riverpod throughout, with code-generated providers
(`@riverpod` annotations) for type-safe DI. `go_router` handles navigation
with an auth-state redirect guard, mirroring WSW's session-gated routing.

**Physics** — Flame + `flame_forge2d` (Box2D) chosen over raw Flame collision
detection because shuffleboard needs realistic deceleration (`linearDamping`),
bounce (`restitution` off rails/other pucks), and continuous collision
detection at high puck speeds. `PuckComponent` renders a real-time motion-blur
trail scaled to velocity and a rotating spoke marking driven by actual
Box2D angular velocity — not a cosmetic shortcut.

**Real-time sync** — RTDB for the live game loop (puck positions throttled to
20Hz to control bandwidth/cost), Firestore for everything durable. See
`docs/FIRESTORE_SCHEMA.md` for the full rationale and schema.

**Matchmaking** — ELO-bracket queue with expanding tolerance (±150 → ±500
over time) and an atomic Firestore transaction for pairing that prevents
double-matching race conditions.

**HUD** — `GameHudWidget` is a pure overlay driven by a `StreamProvider`
watching `/game_sessions/{id}` in RTDB; it tracks per-turn points, pucks
remaining, highest/lowest speed, and highest/lowest distance for both
players simultaneously, with score-pop and turn-indicator animations via
`flutter_animate`.

## Setup

1. **Install dependencies**
   ```bash
   flutter pub get
   ```

2. **Generate freezed/riverpod code** (required before first run — all
   `*.freezed.dart`, `*.g.dart` part files are generated, not checked in):
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

3. **Configure Firebase**
   ```bash
   flutterfire configure
   ```
   This generates `lib/firebase_options.dart`. Uncomment the
   `Firebase.initializeApp(...)` line in `main.dart` once it exists.

4. **Deploy security rules**
   ```bash
   firebase deploy --only firestore:rules,database
   ```

5. **Run**
   ```bash
   flutter run
   ```

## Known TODOs / Hardening for Production

- `firestore.rules` currently allows broad `isSignedIn()` writes on ELO/score
  fields for development speed — move `MatchmakingService.resolveMatch()`
  into a Cloud Function and lock client writes to those fields before launch.
- `GameScreen._handleThrowComplete` has a placeholder `pointsScored = 0` —
  wire it to `BoardBoundaryComponent.zoneForPosition()` using the settled
  puck's final `body.position.x`.
- Add a scheduled Cloud Function to purge stale `/matchmaking_queue` entries
  (app killed mid-search leaves orphaned docs).
- `LeaderboardService.getPlayerRank()` is O(N) via a count query; fine at
  moderate scale, but consider a maintained rank-counter for very large
  player bases.
