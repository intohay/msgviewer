import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'helper.dart';

class DatabaseHelper {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDb();
    return _database!;
  }

  initDb() async {
    String path = join(await getDatabasesPath(), 'app_data.db');
    return await openDatabase(path, version: 3, onCreate: (Database db, int version) async {
      await db.execute('''
        CREATE TABLE Messages (
          id INTEGER PRIMARY KEY,
          name TEXT,
          date DATETIME,
          text TEXT,
          filename TEXT,
          is_favorite BOOLEAN
        )
      ''');
      await db.execute('''
        CREATE TABLE Talks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT UNIQUE,
          icon_path TEXT,
          call_me TEXT
        )
      ''');
    }, onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 3) {
        await db.execute('''
          CREATE TABLE Talks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE,
            icon_path TEXT,
            call_me TEXT
          )
        ''');
      }
    });
  }


  Future<void> insertData(List<List<dynamic>> csvData) async {
    final db = await database;
    for (var row in csvData) {
      // print(row[0]);
      await db.insert(
        'Messages',
        {
          'id': row[0],
          'name': row[1],
          'date': formatDateTimeForDatabase(row[2]),
          'text': row[3],
          'filename': row[4],
          'is_favorite': row[5] == 'TRUE' ? 1 : 0  // SQLiteではBOOLEANを整数で扱う
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

  }


  Future<List<Map<String, dynamic>>> getMessages(String? name, int offset, int limit) async {
    final db = await database;
    return await db.query(
      'Messages',
      where: name != null ? 'name = ?' : null,
      whereArgs: name != null ? [name] : null,
      limit: limit,
      offset: offset,
      orderBy: 'id DESC'  // 最新のデータから取得する場合
    );
  }



  Future<List<Map<String, dynamic>>> getAllMessages() async {
    final db = await database;
    return await db.query(
      'Messages',
      orderBy: 'id DESC'
    );
  }


  Future<void> setIconPath(String name, String iconPath) async {
    final db = await database;
    await db.insert(
      'Talks',
      {'name': name, 'icon_path': iconPath},
      conflictAlgorithm: ConflictAlgorithm.replace, // 同じ `name` の場合は上書き
    );
  }

  // アイコンのパスを取得
  Future<String?> getIconPath(String name) async {
    final db = await database;
    final result = await db.query(
      'Talks',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return result.first['icon_path'] as String?;
    }
    return null;
  }

  Future<void> setCallMeName(String name, String callMeName) async {
    final db = await database;
    await db.insert(
      'Talks',
      {'name': name, 'call_me': callMeName},
      conflictAlgorithm: ConflictAlgorithm.replace, // 上書き保存
    );
  }

  Future<String?> getCallMeName(String name) async {
    final db = await database;
    final result = await db.query(
      'Talks',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return result.first['call_me'] as String?;
    }
    return null;
  }
  
}