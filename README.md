# LilRoutine

A cozy, local-first water / calorie / habit tracker for Android — pixel-art UI, one unified SQLite log, deterministic coaching insights, and an optional bring-your-own-key Gemini AI layer.

Every insight is computed **on-device** from your own log. There are no accounts, no backend, and no analytics. AI is an opt-in layer you bring a key to — the app is fully functional with zero AI configuration.

[![Tests](https://github.com/yemann2k39-jpg/lil_routine/actions/workflows/test.yml/badge.svg)](https://github.com/yemann2k39-jpg/lil_routine/actions/workflows/test.yml)

## Features

- **Quick water logging** — tap a cup, the ring and mascot react instantly; undo and per-drink delete for mistakes
- **Full macro meal log** — protein, carbs, fat, fiber, sugar, sodium, with portion scaling and edit-after-log
- **Learned food library** — log "ramen" once, relog it in two taps with every macro remembered
- **AI food logging (BYO key)** — a photo or a short description becomes a pre-filled estimate that you review before anything saves
- **Deterministic insight engine** — timing, streak and macro-contrast rules, including cross-domain advice (a salty day suggests extra water). Plain arithmetic — never hallucinated
- **Weekly AI coach recap** — once every 7 days, Gemini turns the week's *aggregate numbers* into tips; it never sees individual food names
- **Forgiving streak economy** — 3 hearts per calendar week; today never costs a heart because it isn't finished
- **Pixel mascot (Lil Drop)** — mood follows an exact, hour-aware pace model
- **Swipeable dashboards** — 7-day water bars, kcal bars and macro-split bars with grams in-segment
- **Water reminders** — exact alarms plus battery-optimization handling, so they survive OEM battery managers

## Tech stack

| Layer | Choice |
|---|---|
| App | Flutter (Dart), Material + custom pixel widget set |
| Data | sqflite (SQLite), versioned schema with tested on-device migrations |
| Secure storage | flutter_secure_storage (Android Keystore-backed) |
| AI | Gemini REST API called directly over `http` — no SDK |
| Reminders | flutter_local_notifications + a platform channel for battery-optimization checks |
| Testing | flutter_test, sqflite_common_ffi (real in-memory SQLite), MockClient |

## How it works

The main pieces, kept deliberately simple — the full implementation lives in this repo:

- **One SQLite file** is the system of record. A unified `entries` table holds both water drinks and food meals; `foods`, `drink_slots`, `habits`, `habit_logs` and a key-value `settings` table sit alongside it
- **Repositories** wrap every query; screens load data and hand plain numbers to pure-UI views, which makes dashboards renderable in widget tests with fixture data and no database
- **The insight engine** is a pure function: a week of entries in, prioritized coaching cards out — no I/O, no AI
- **The AI provider** makes exactly two calls (food estimate, weekly recap) straight to Gemini's REST endpoint, locked behind a gate until a key exists
- **The reminder service** re-applies the stored schedule on every launch and checks Android's exact-alarm and battery-optimization realities

## Getting started

```bash
flutter pub get
flutter run                # debug build on a connected device
flutter test               # 119 tests
flutter analyze            # clean
flutter build apk --debug  # build/app/outputs/flutter-apk/app-debug.apk
```

Requires a recent stable Flutter SDK. The app targets Android.

### Optional: enable AI features

1. Get a free Gemini API key from [Google AI Studio](https://aistudio.google.com/)
2. In the app: **Settings**, AI section — paste the key, tap Save and Test

The key is stored in Android Keystore-backed secure storage — never in the database, never in the APK, never logged. Without a key every AI surface simply stays hidden.

### Privacy

- All tracking data lives in a single SQLite file on the phone
- The weekly recap prompt contains aggregate numbers only (kcal, macros, sodium, sugar, water ml) — never food names
- No accounts, no backend, no telemetry

## Testing

119 tests, all green, analyzer clean:

- **Pure logic** — insight rules, mascot mood machine, streak/hearts engine, JSON parsers
- **Repositories & migrations** — real in-memory SQLite via `sqflite_common_ffi`, including rebuilding a genuine v2 database file and asserting the v1 to v3 migration path via `PRAGMA table_info`
- **AI provider** — MockClient tests for clean answers, markdown fences, bad keys, rate limits, blocked responses and non-JSON output
- **Widgets** — full dashboards pumped from fixtures, including a `PageView` fling to reach the lazily-built macro chart

## Project structure

```
lib/
  core/
    ai/          # AiProvider, GeminiProvider, key store, AI gate
    data/        # repositories (entries, foods, slots, habits, settings)
    db/          # database singleton + schema migrations
    insights/    # insight engine + weekly coach recap flow
    notifications/
    theme/       # palette, typography, pixel widgets
  features/
    food/        # log sheets, meal detail, meals history
    home/        # two-tab shell
    insights/    # insight cards
    mascot/      # mood machine + animations
    settings/
    water/       # water history + streak/hearts engine
    debug/       # debug-only screens (removed before release)
test/            # 119 tests mirroring the layers above
.tickets/        # local ticket board (LIL-1..22) — dev process artifact
```

## Status & roadmap

Done so far is tracked on a local ticket board (`.tickets/`, tickets LIL-1 through LIL-22). In progress / planned:

- Data export & backup (CSV + JSON snapshot)
- Settings completion — editable goals, profile name, glass size
- Habits UI on the existing schema
- AI food swaps & ask-the-coach chat (reusing the estimate-parse-confirm pipeline)
- Release prep — signed APK, debug-screen removal
