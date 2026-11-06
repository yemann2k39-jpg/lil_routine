import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Central SQLite access for LilRoutine.
///
/// Local-first: everything the app knows lives in this file on the device.
class AppDatabase {
  AppDatabase._();

  static Database? _db;

  static const int schemaVersion = 3;

  /// Opens (and caches) the app database at the platform default location.
  static Future<Database> instance() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openAt(p.join(dir, 'lil_routine.db'));
    return _db!;
  }

  /// Opens (and migrates) a database at [path]. Also used by unit tests.
  static Future<Database> openAt(String path) {
    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 -> v2: drink quick-slots table.
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS drink_slots (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              ml INTEGER NOT NULL,
              position INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL DEFAULT 0
            )
          ''');
        }
        // v2 -> v3: extra food macros (fiber g, sugar g, sodium mg).
        if (oldVersion < 3) {
          for (final column in ['fiber', 'sugar', 'sodium']) {
            await db.execute(
                'ALTER TABLE entries ADD COLUMN $column REAL');
          }
          for (final column in ['fiber', 'sugar', 'sodium']) {
            await db.execute(
                'ALTER TABLE foods ADD COLUMN $column REAL NOT NULL DEFAULT 0');
          }
        }
      },
    );
  }

  /// Creates all v1 tables and indices. Kept public so tests can build
  /// in-memory databases with the exact same schema.
  static Future<void> createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        amount_ml INTEGER,
        name TEXT,
        meal_type TEXT,
        kcal REAL,
        protein REAL,
        carbs REAL,
        fat REAL,
        fiber REAL,
        sugar REAL,
        sodium REAL,
        portion REAL NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        date TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_entries_date ON entries(date)');
    await db.execute(
        'CREATE INDEX idx_entries_type_date ON entries(type, date)');

    await db.execute('''
      CREATE TABLE foods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        kcal REAL NOT NULL DEFAULT 0,
        protein REAL NOT NULL DEFAULT 0,
        carbs REAL NOT NULL DEFAULT 0,
        fat REAL NOT NULL DEFAULT 0,
        fiber REAL NOT NULL DEFAULT 0,
        sugar REAL NOT NULL DEFAULT 0,
        sodium REAL NOT NULL DEFAULT 0,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        times_logged INTEGER NOT NULL DEFAULT 0,
        last_used_at INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE habits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE habit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        habit_id INTEGER NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
        date TEXT NOT NULL,
        done INTEGER NOT NULL DEFAULT 0,
        UNIQUE(habit_id, date)
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE drink_slots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        ml INTEGER NOT NULL,
        position INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
