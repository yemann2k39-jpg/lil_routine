# LilRoutine — Agent Handoff

*Written at end of a working session. Read this fully before doing anything.*

## What this project is

**LilRoutine** — a minimalist Flutter app (Android only for now) for water intake,
calorie tracking, and drinking/eating-specific habits. Cozy pixel-art aesthetic:
warm cream/peach/blue palette, Silkscreen pixel font + Varela Round body font,
chunky bordered cards with hard offset shadows. NOT too cute, no thick outlines.

- Project root: `C:\KuromiLab\lil_routine`
- Package/org: `com.lilroutine.lil_routine`
- User's name: **Niko** (hardcoded `kUserName` until Settings ticket)
- User tests on a physical Android phone, device id **`R5CX42XCSKA`**
- User communicates briefly. "done"/"continue"/"ok" after a verification
  checklist = acceptance. User explicitly invites clarifying questions
  ("Ask me if you don't understand anything") — the `ask_user_question` tool
  has worked well for design decisions.

## Critical workflow rules

1. **Ticket-driven.** 13 tickets LIL-1..LIL-13 in
   `C:\KuromiLab\lil_routine\.tickets\tickets.db`. Sequential: each ticket is
   verified on the phone by Niko before the next starts. Ticket CLI:
   ```
   node C:\KuromiLab\ai-development-ticket-workflow\dist\cli\cli.js --root C:\KuromiLab\lil_routine status|link|comment <KEY> ... --json
   ```
   `done` status requires `--evidence`. New user-requested work can be folded
   into the current ticket's scope (record it with a `comment`) — that's what
   we did for the whole water-UI restructure inside LIL-5.
2. **Build/install loop** (all commands need `workdir C:\KuromiLab\lil_routine`,
   and `$env:FLUTTER_SUPPRESS_ANALYTICS='true'` on flutter commands):
   ```
   flutter analyze
   flutter test
   flutter build apk --debug
   adb install -r build\app\outputs\flutter-apk\app-debug.apk
   adb shell am force-stop com.lilroutine.lil_routine
   adb shell monkey -p com.lilroutine.lil_routine -c android.intent.category.LAUNCHER 1
   ```
   Session policy is `danger-full-access` and **approval prompts are disabled**
   — run commands plain, never pass `sandbox_permissions`.
3. **Never claim install success from a stale APK.** Build failures previously
   masked as "installed" — verify build success before installing. The phone
   sometimes disconnects (`adb: no devices/emulators found`) — then tell Niko
   to plug in and wait for "phone connected".
4. **No git commits** unless Niko explicitly asks. None have been made yet.
5. **Mascot art is Niko's own PNG** (`assets/images/mascot.png`, from their
   waterdroplet.png). Moods = motion only, NEVER redraw the art.

## Current state (as of this handoff)

- **LIL-5 is IN-REVIEW** (not closed). Scope: manual food logging + recents/
  favorites, but it absorbed two large user-requested UI passes:
  1. App split into two pages (water / meals) with pixel bottom nav
     (`PixelNavBar` + `IndexedStack`).
  2. Water page fully restructured (details below).
  Multiple progress comments are recorded on the ticket. **First task of the
  new session: ask Niko to verify the water page on the phone, and on
  acceptance close LIL-5 with evidence, then start LIL-6.**
- Tickets LIL-1..4 done. Remaining: LIL-6 Open Food Facts lookup, LIL-7 habit
  engine, LIL-8 habit history grid, LIL-9 AI gating + BYO Gemini key, LIL-10 AI
  food logging, LIL-11 settings completion + reminders (**goal management and
  user-name setting live here**), LIL-12 cozy pixel polish (**per-slot cup
  designs land here**), LIL-13 release prep.

## Water page — what it looks like now (top to bottom)

1. **Greeting**, left-aligned: "Good morning/afternoon/evening, Niko"
   (`greetingFor(DateTime.now())` in models.dart).
2. **Ring block, vertically centered** (`Flexible` + `Center` +
   `SingleChildScrollView` inside so tiny screens scroll instead of overflow):
   - `WaterRing(totalMl, goalMl, centerChild: PixelMascot(size: 104))` —
     Lil Drop sits INSIDE the ring, mood happy at goal.
   - Stats below the ring (NOT inside it): big pixel `%` (26pt), then
     `X / 3000 ml` (17pt cozy, cocoa), then `X ml to go` (13pt, cocoaSoft),
     or `Daily goal reached!` when complete.
3. **Cup quick-slots near the bottom** (pinned by the Flexible layout above):
   - Fixed-size squares (never stretch with fewer cups): slot width =
     `rowMaxWidth / 4 - 8`, height `width / 0.85`, row centered.
   - Each square: `PixelCup` art (¾ full, water from row 3) + capitalized
     slot name + ml. **Tap = log that ml. Hold = remove (confirm dialog).**
   - `+ Add cup / New drink` square (paper/outline, NOT blue) while
     `slots.length < 4`; opens `_AddDrinkDialog` (name + ml, validation).
     Per-slot cup designs deferred to LIL-12.
4. `Hold to remove` hint (plus `· + adds a cup` only when under limit).
5. **`Undo last` chip** — paper background, cocoaSoft border, cocoa text,
   replay icon, shadow; greyed outline when nothing to undo.

All UI copy is Capitalized (Glass, Add cup, Undo last, Cancel, Remove...).
Niko said lowercase looks unprofessional — keep this style everywhere.

## Data layer / architecture

- Local-first SQLite via `sqflite`, repositories pattern, schema **v2**.
  `drink_slots` table added in v2 (id, name, ml, position, created_at);
  `onUpgrade` uses `CREATE TABLE IF NOT EXISTS` when `oldVersion < 2`.
  Niko's device migrated from v1 with data intact.
- `DrinkSlotRepository` (maxSlots = 4, `ensureDefault()` seeds one 250ml
  'glass' — called on every load).
- **Water goal pinned at 3000 ml** (`kPinnedWaterGoalMl` in home_screen.dart,
  `SettingsRepository.defaultWaterGoalMl` = 3000 now). `_reload()` overwrites
  any other stored value with a "until LIL-11" comment. Goal editing UI was
  REMOVED (`_WaterGoalDialog` deleted; no add-glass button; no goal chip).
- Key files: `lib/features/home/home_screen.dart` (shell + both page views +
  slot squares + dialogs), `lib/features/water/water_ring.dart` (centerChild),
  `lib/core/widgets/pixel_cup.dart`, `pixel_mascot.dart`, `pixel_nav_bar.dart`,
  `pixel_widgets.dart`, `lib/core/data/*` (repos + models with `greetingFor`,
  `DrinkSlot`), `lib/core/db/app_database.dart`, `lib/core/theme/*`.
- Meals page: `CalorieRing`, LOG FOOD → `LogFoodSheet` (favorites/recents
  chips + form with portion multiplier), today's meals list with delete.

## Tests (26, all passing)

- `test/widget_test.dart` — water page (greeting/ring/stats/slots/capitalized
  labels/'X ml to go'), slot limit hides Add cup, goal reached, history view,
  meals page, calorie ring, food form, guessMealType.
  Water page tests pump `WaterPageView` DIRECTLY in a Scaffold body (it needs
  bounded height — `Expanded`-style internals; wrapping in a bare
  SingleChildScrollView crashes).
- `test/repositories_test.dart` — 17 repo tests incl. DrinkSlot
  (ensureDefault/add/remove). Test DB pattern: `databaseFactory.openDatabase(
  inMemoryDatabasePath, options: OpenDatabaseOptions(version:
  AppDatabase.schemaVersion, onConfigure: PRAGMA foreign_keys ON,
  onCreate: AppDatabase.createSchema))`.

## Gotchas learned the hard way

- `Row(crossAxisAlignment: stretch)` inside unbounded height (scroll view) =
  layout crash. `Expanded` inside `IntrinsicHeight` inside a scroll view = also
  unsupported. Current water layout avoids both.
- Paren-matching during multi-step Flutter widget edits went wrong twice —
  after structural edits, read the region back before building.
- PowerShell: avoid arithmetic inside `@()` array literals.
- PNG processing (mascot): GDI+ drops alpha unless rebuilt on a fresh
  `Format32bppArgb` canvas.
- Test expectations must match real computed values — verify against app
  data, not hand math (earlier 63% duplicate-text and 2700/385 bugs).

## Next steps

1. Niko verifies current water page polish on phone (bigger %, ml-to-go line,
   base-color Add cup/Undo last, capitalized labels, fuller cup).
2. On "ok/continue": close LIL-5 with evidence (tests 26/26, on-device pass),
   move LIL-6 to in-progress, implement Open Food Facts lookup, repeat loop.
3. Ask before doing anything about AI tickets whether Niko has picked a Gemini
   key approach yet (BYO key, gated behind LIL-9).
