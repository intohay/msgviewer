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
          filepath TEXT,
          thumb_filepath TEXT,
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
          'filepath': row[4],
          'thumb_filepath': row[5], // Added thumb_path in the insertData
          'is_favorite': row[6] == 'TRUE' ? 1 : 0  // Adjusted index for is_favorite
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    print('Data inserted successfully');
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

  /// (A) 最新から limit 件だけ取得 (id DESC)
  Future<List<Map<String, dynamic>>> getNewestMessages(String? name, int limit) async {
    final db = await database;
    return await db.query(
      'Messages',
      where: 'name = ?',
      whereArgs: [name],
      orderBy: 'id DESC',
      limit: limit,
    );
  }

  /// (B) 指定した id より古いメッセージを limit 件 (id DESC)
  Future<List<Map<String, dynamic>>> getOlderMessages(String? name, int olderThanId, int limit) async {
    final db = await database;
    return await db.query(
      'Messages',
      where: 'name = ? AND id < ?',
      whereArgs: [name, olderThanId],
      orderBy: 'id DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getNewerMessages(String? name, int currentMaxId, int limit) async {
    final db = await database;
    return await db.query(
      'Messages',
      where: 'name = ? AND id > ?',
      whereArgs: [name, currentMaxId],
      orderBy: 'id DESC', // 新しい順
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getMessagesSinceDate(String? name, DateTime date) async {
    final db = await database;
    // 例: date以上の投稿だけ
    return await db.rawQuery('''
      SELECT * FROM Messages
      WHERE name = ?
        AND date >= ?
      ORDER BY id DESC
    ''', [name, date.toIso8601String()]);
  }


  Future<List<Map<String, dynamic>>> getAllMessages() async {
    final db = await database;
    return await db.query(
      'Messages',
      orderBy: 'id DESC'
    );
  }

  Future<List<Map<String, dynamic>>> getOlderMessagesById(String? name, int olderThanId, int limit) async {
    final db = await database;
    // id < olderThanId の投稿を id DESC でlimit件
    return await db.query(
      'Messages',
      where: 'name = ? AND id < ?',
      whereArgs: [name, olderThanId],
      orderBy: 'id DESC',
      limit: limit,
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

  Future<void> updateFavoriteStatus(int messageId, bool isFavorite) async {
    final db = await database;
    await db.update(
      'Messages',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<List<Map<String, dynamic>>> getFavoriteMessages(String name, int offset, int limit) async {
    final db = await database;
    return await db.query(
      'Messages',
      where: 'name = ? AND is_favorite = 1',
      whereArgs: [name],
      orderBy: 'id DESC',
      limit: limit,
      offset: offset,
    );
  }


    // database_helper.dart (抜粋)
  Future<List<Map<String, dynamic>>> getImageMessages(String name) async {
    final db = await database;
    return await db.query(
      'Messages',
      where: '''
        name = ? 
        AND (
          filepath LIKE '%.jpg' 
          OR filepath LIKE '%.png'
        )
      ''',
      whereArgs: [name],
      orderBy: 'date ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getVideoMessages(String name) async {
    final db = await database;
    return await db.query(
      'Messages',
      where: '''
        name = ? 
        AND (
          (filepath LIKE '%.mp4' AND filepath NOT LIKE '%\\_3\\_%.mp4' ESCAPE '\\')
        OR filepath LIKE '%\\_2\\_%.mp4' ESCAPE '\\'
        )
      ''',
      whereArgs: [name],
      orderBy: 'date ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAudioMessages(String name) async {
    final db = await database;
    return await db.query(
      'Messages',
      where: '''
        name = ? 
        AND (
          filepath LIKE '%.m4a'
          OR filepath LIKE '%\\_3\\_%.mp4' ESCAPE '\\'
        )
      ''',
      whereArgs: [name],
      orderBy: 'date ASC',
    );
  }

  Future<Map<String, dynamic>?> getClosestMessageToDate(String? name, DateTime date) async {
    final db = await database;
    
    // SQLiteの日時比較で「date」カラムは DATETIME になっているため、
    // strftime('%s', date) でUNIX秒に変換し、選択日との絶対差が小さい順に並べて先頭を取る
    final dateString = date.toIso8601String(); // "2025-03-17T00:00:00.000" など
    final results = await db.rawQuery('''
      SELECT * FROM Messages
      WHERE name = ?
      ORDER BY ABS(strftime('%s', date) - strftime('%s', ?))
      LIMIT 1
    ''', [name, dateString]);

    if (results.isNotEmpty) {
      return results.first;
    }
    return null; // 見つからない場合
  }

  Future<List<Map<String, dynamic>>> getMessagesAroundId(String? name, int centerId, int limit) async {
    final db = await database;
    // centerIdより新しい(=idが大きい)メッセージを limit/2 件
    final half = (limit / 2).ceil();

    // 新しい方(=idがcenterId以上)を昇順で取得(最終的に結合時に並び替え直す)
    final newer = await db.rawQuery('''
      SELECT * FROM Messages
      WHERE name = ? AND id >= ?
      ORDER BY id ASC
      LIMIT ?
    ''', [name, centerId, half]);

    // 古い方(=idがcenterIdより小さい)を降順で取得
    final older = await db.rawQuery('''
      SELECT * FROM Messages
      WHERE name = ? AND id < ?
      ORDER BY id DESC
      LIMIT ?
    ''', [name, centerId, half]);

    // olderは降順取得なので反転して結合し、その後全体を id DESC (新→古)に並べ替える
    final combined = [
      ...older.reversed, 
      ...newer,
    ];
    // id DESC でソート (新しいIDが先頭になる)
    combined.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    return combined;
  }


  // DatabaseHelper.dart に追記
  Future<List<Map<String, dynamic>>> searchMessagesByText(String? name, String queryText) async {
    final db = await database;

    // name(トーク相手)が一致していて、textカラムに検索文字列を含むメッセージを取得
    // 大文字小文字を区別しない検索をしたい場合は、COLLATE などを利用する
    // ここでは簡単に '%$queryText%' として部分一致検索しています
    final result = await db.query(
      'messages',
      where: 'name = ? AND text LIKE ?',
      whereArgs: [name, '%$queryText%'],
      orderBy: 'id DESC', // 新しい順
    );

    return result;
  }

  Future<void> deleteTalk(String talkName) async {
    final db = await database;
    // 1. 対象のトークのメッセージを取得
    final messagesToDelete = await db.query(
      'Messages',
      where: 'name = ?',
      whereArgs: [talkName],
    );
    
    // 2. 各メッセージに紐づくファイルを削除
    for (final message in messagesToDelete) {
      final filePath = message['filepath'] as String?;
      final thumbFilePath = message['thumb_filepath'] as String?;
      
      // 通常ファイルの削除
      if (filePath != null && filePath.isNotEmpty) {
        final file = File(filePath);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (e) {
            print('ファイル削除エラー: $e');
          }
        }
      }
      
      // サムネイルファイルの削除
      if (thumbFilePath != null && thumbFilePath.isNotEmpty) {
        final thumbFile = File(thumbFilePath);
        if (await thumbFile.exists()) {
          try {
            await thumbFile.delete();
          } catch (e) {
            print('サムネイル削除エラー: $e');
          }
        }
      }
    }
    
    // 3. Messages テーブルからトークのメッセージを削除
    await db.delete(
      'Messages',
      where: 'name = ?',
      whereArgs: [talkName],
    );
    
    // 4. Talks テーブルからトークの設定（アイコンや呼ばれたい名前）を削除
    await db.delete(
      'Talks',
      where: 'name = ?',
      whereArgs: [talkName],
    );
    
    print('トーク "$talkName" の削除が完了しました。');
  }

}