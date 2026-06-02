import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'whisperback.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE schedules ADD COLUMN end_time TEXT');
          await db.execute(
            'ALTER TABLE schedules ADD COLUMN alarm_enabled INTEGER NOT NULL DEFAULT 1',
          );
          await db.execute(
            'ALTER TABLE schedules ADD COLUMN days_mask INTEGER NOT NULL DEFAULT 127',
          );
        }
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
          CREATE TABLE clips (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            file_path TEXT NOT NULL,
            duration_ms INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            source TEXT NOT NULL
          )
        ''');
    await db.execute('''
          CREATE TABLE playlists (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            shuffle_enabled INTEGER NOT NULL DEFAULT 0
          )
        ''');
    await db.execute('''
          CREATE TABLE playlist_clips (
            playlist_id TEXT NOT NULL,
            clip_id TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            PRIMARY KEY (playlist_id, clip_id),
            FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
            FOREIGN KEY (clip_id) REFERENCES clips(id) ON DELETE CASCADE
          )
        ''');
    await db.execute('''
          CREATE TABLE schedules (
            id TEXT PRIMARY KEY,
            playlist_id TEXT NOT NULL UNIQUE,
            start_time TEXT NOT NULL,
            end_time TEXT,
            interval_minutes INTEGER NOT NULL,
            shuffle_enabled INTEGER NOT NULL DEFAULT 0,
            alarm_enabled INTEGER NOT NULL DEFAULT 1,
            days_mask INTEGER NOT NULL DEFAULT 127,
            enabled INTEGER NOT NULL DEFAULT 1,
            FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
          )
        ''');
    await db.execute('''
          CREATE TABLE sleep_windows (
            id TEXT PRIMARY KEY,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            label TEXT NOT NULL DEFAULT 'Sleep',
            active INTEGER NOT NULL DEFAULT 0
          )
        ''');
    await db.execute('''
          CREATE TABLE prayer_settings (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            calculation_method TEXT NOT NULL DEFAULT 'Karachi',
            madhab TEXT NOT NULL DEFAULT 'Shafi',
            use_gps INTEGER NOT NULL DEFAULT 1,
            manual_city TEXT
          )
        ''');
    await db.execute('''
          CREATE TABLE app_state (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            is_active INTEGER NOT NULL DEFAULT 0,
            global_shuffle_enabled INTEGER NOT NULL DEFAULT 0
          )
        ''');
    await db.insert(
        'app_state', {'id': 1, 'is_active': 0, 'global_shuffle_enabled': 0});
    await db.insert('prayer_settings', {
      'id': 1,
      'calculation_method': 'Karachi',
      'madhab': 'Shafi',
      'use_gps': 1,
    });
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
