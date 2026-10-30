# PlaybookAI

Design a football play, run it against any defense, watch all 22 players move, and get the QB's progression explained read by read.

## Run it

```bash
flutter pub get
flutter run -d chrome        # or an iPad/Android simulator, or -d macos
```

Without Firebase configured, the app runs in **on-device mode**: plays are saved locally and seeded with starter concepts (Four Verts, Smash, Mesh, Flood, Slant-Flat, Y-Cross, PA Post-Dig, Inside Zone, Power).

## Features

- **Designer**: formation presets, drag players, a route-tree palette or freehand custom routes (tap to add points, drag the handles), run concepts, QB drop, read order, flip, undo/redo.
- **Defense**: 4 fronts × 8 coverages (0, 1, 2, Tampa 2, 3, 4, 6, 2-Man) × blitzes. The defense auto-aligns to the formation's strength and #1/#2/#3 receivers. Defenders can be dragged pre-snap.
- **Simulator**: a deterministic 20 Hz engine covering routes, man/zone coverage with reaction lag, pass pro and run blocking, a QB that reads the progression, ball flight, catch resolution, YAC and pursuit. Supports play/pause, scrubbing, 0.25–2× speed, a new rep (seed), trails, zone shading and a QB-eyes line.
- **Explanations**: the pre-snap read (shell, leverage, box count, protection), a timestamped progression (why each read was covered or open, naming the defender and his assignment), a verdict and coverage-beater tips. Tapping a step jumps the field to that moment.
- **Test vs all coverages**: 25 reps against each coverage, showing yards, success, completion, read-1 rate, INT and sack rates.
- **Coach AI** (optional): a Claude-written coaching breakdown through the `explainPlay` Cloud Function.

## Enable cloud accounts and Coach AI

1. `firebase login`, then create or choose a project and enable **Email/Password** auth and **Firestore**.
2. `dart pub global activate flutterfire_cli && flutterfire configure`. This replaces `lib/firebase_options.dart`.
3. `firebase deploy --only firestore:rules`
4. `firebase functions:secrets:set ANTHROPIC_API_KEY`, then `cd functions && npm install && npm run deploy`. Coach AI uses `claude-opus-5-5`, is limited to 50 requests per user per day, and requires sign-in.

Plays live at `users/{uid}/plays/{playId}` and are readable and writable only by their owner (see `firestore.rules`).

## Develop

```bash
flutter test                           # engine, explainer, designer and screen tests
dart run tool/sim_report.dart 30       # each starter play vs each coverage
dart run tool/sim_trace.dart Smash cover2 1 h,d_fs   # frame trace of one rep
```

Layout: `lib/models` (play, defense, formations, route tree), `lib/sim` (defense auto-alignment, engine, coverage matrix), `lib/explain` (rules-based explanations), `lib/features` (screens), `lib/data` (local/Firestore repositories, Coach AI client), `functions/` (Claude proxy).
