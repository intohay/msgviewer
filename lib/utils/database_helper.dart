import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDb();
    return _database!;
  }

  initDb() async {
    String path = join(await getDatabasesPath(), 'app_data.db');
    return await openDatabase(path, version: 1, onCreate: (Database db, int version) async {
      await db.execute('''
        CREATE TABLE Messages (
          id INTEGER PRIMARY KEY,
          name TEXT,
          date TEXT,
          text TEXT,
          filename TEXT,
          is_favorite BOOLEAN
        )
      ''');
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
          'date': row[2],
          'text': row[3],
          'filename': row[4],
          'is_favorite': row[5] == 'TRUE' ? 1 : 0  // SQLiteではBOOLEANを整数で扱う
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

  }


  Future<List<Map<String, dynamic>>> getMessages(int offset, int limit) async {
    final db = await database;
    return await db.query(
      'Messages',
      limit: limit,
      offset: offset,
      orderBy: 'id DESC'  // 最新のデータから取得する場合
    );
  }
}