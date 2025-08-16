import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Documents ディレクトリのパスを取得（キャッシュなし - 毎回取得）
  Future<String> getDocumentsPath() async {
    // キャッシュを使わず、毎回新しくパスを取得
    final docsPath = (await getApplicationDocumentsDirectory()).path;
    debugPrint('Documents path: $docsPath');
    return docsPath;
  }

  // 絶対パスから相対パスに変換（保存時に使用）
  Future<String?> toRelativePath(String? absolutePath) async {
    if (absolutePath == null || absolutePath.isEmpty) return null;
    final docsPath = await getDocumentsPath();
    if (absolutePath.startsWith(docsPath)) {
      return absolutePath.substring(docsPath.length + 1); // +1 for the separator
    }
    return absolutePath; // 既に相対パスの場合はそのまま返す
  }

  // 相対パスから絶対パスに変換（読み込み時に使用）
  Future<String?> toAbsolutePath(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return null;
    
    final docsPath = await getDocumentsPath();
    
    // 既に正しい絶対パスの場合はそのまま返す
    if (relativePath.startsWith(docsPath)) {
      return relativePath;
    }
    
    // 古い絶対パス（別のDocumentsパス）の場合は、相対部分だけ取り出して新しいパスに結合
    if (relativePath.startsWith('/')) {
      // 古い絶対パスから相対パス部分を抽出
      final parts = relativePath.split('/Documents/');
      if (parts.length > 1) {
        // Documents/以降の部分を取得
        final relativePartOnly = parts[1];
        debugPrint('Converting old absolute path to new: $relativePath -> $docsPath/$relativePartOnly');
        return join(docsPath, relativePartOnly);
      }
      // それ以外の絶対パスはそのまま返す（エラーケース）
      return relativePath;
    }
    
    // 相対パスの場合は新しいDocumentsパスと結合
    return join(docsPath, relativePath);
  }

  // メッセージリストのパスを絶対パスに変換
  Future<List<Map<String, dynamic>>> convertPathsToAbsolute(List<Map<String, dynamic>> messages) async {
    final List<Map<String, dynamic>> result = [];
    for (var message in messages) {
      final Map<String, dynamic> convertedMessage = Map.from(message);
      final originalPath = message['filepath'];
      final convertedPath = await toAbsolutePath(message['filepath']);
      
      // デバッグログ
      if (originalPath != null) {
        if (originalPath != convertedPath) {
          debugPrint('Path conversion: $originalPath -> $convertedPath');
        } else if (!originalPath.startsWith('/')) {
          debugPrint('WARNING: Path not converted (still relative): $originalPath');
        }
      }
      
      convertedMessage['filepath'] = convertedPath;
      convertedMessage['thumb_filepath'] = await toAbsolutePath(message['thumb_filepath']);
      result.add(convertedMessage);
    }
    return result;
  }

  initDb() async {
    String path = join(await getDatabasesPath(), 'app_data.db');
    return await openDatabase(path, version: 8, onCreate: (Database db, int version) async {
      await db.execute('''
        CREATE TABLE Messages (
          id INTEGER PRIMARY KEY,
          name TEXT,
          date DATETIME,
          text TEXT,
          filepath TEXT,
          thumb_filepath TEXT,
          is_favorite BOOLEAN,
          video_duration INTEGER,
          audio_duration INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE Talks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT UNIQUE,
          icon_path TEXT,
          call_me TEXT,
          scroll_index INTEGER DEFAULT 0
        )
      ''');
    }, onUpgrade: (db, oldVersion, newVersion) async {
      debugPrint('Database upgrade from version $oldVersion to $newVersion');
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
      if (oldVersion < 4) {
        debugPrint('Upgrading to version 4: Adding scroll_index column');
        // 既存のテーブルにscroll_indexカラムを追加
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='Talks'"
        );
        if (tables.isNotEmpty) {
          final columns = await db.rawQuery('PRAGMA table_info(Talks)');
          final hasScrollIndex = columns.any((col) => col['name'] == 'scroll_index');
          if (!hasScrollIndex) {
            await db.execute('ALTER TABLE Talks ADD COLUMN scroll_index INTEGER DEFAULT 0');
            debugPrint('scroll_index column added successfully');
          }
        }
      }
      if (oldVersion < 5) {
        debugPrint('Upgrading to version 5: Converting absolute paths to relative paths');
        // 既存のメッセージのパスを絶対パスから相対パスに変換
        await _migratePathsToRelative(db);
      }
      if (oldVersion < 6) {
        debugPrint('Upgrading to version 6: Adding video_duration column');
        // 既存のテーブルにvideo_durationカラムを追加
        final columns = await db.rawQuery('PRAGMA table_info(Messages)');
        final hasVideoDuration = columns.any((col) => col['name'] == 'video_duration');
        if (!hasVideoDuration) {
          await db.execute('ALTER TABLE Messages ADD COLUMN video_duration INTEGER');
          debugPrint('video_duration column added successfully');
        }
      }
      if (oldVersion < 7) {
        debugPrint('Upgrading to version 7: Adding audio_duration column');
        // 既存のテーブルにaudio_durationカラムを追加
        final columns = await db.rawQuery('PRAGMA table_info(Messages)');
        final hasAudioDuration = columns.any((col) => col['name'] == 'audio_duration');
        if (!hasAudioDuration) {
          await db.execute('ALTER TABLE Messages ADD COLUMN audio_duration INTEGER');
          debugPrint('audio_duration column added successfully');
        }
      }
      if (oldVersion < 8) {
        debugPrint('Upgrading to version 8: Converting icon paths to relative paths');
        // アイコンパスを相対パスに変換
        await _migrateIconPathsToRelative(db);
      }
    });
  }

  // 既存データのパスを絶対パスから相対パスに変換するマイグレーション処理
  Future<void> _migratePathsToRelative(Database db) async {
    try {
      final docsPath = await getDocumentsPath();
      
      // すべてのメッセージを取得
      final messages = await db.query('Messages');
      
      for (var message in messages) {
        bool needsUpdate = false;
        String? newFilePath = message['filepath'] as String?;
        String? newThumbPath = message['thumb_filepath'] as String?;
        
        // filepathを相対パスに変換
        if (newFilePath != null && newFilePath.startsWith(docsPath)) {
          newFilePath = newFilePath.substring(docsPath.length + 1);
          needsUpdate = true;
        }
        
        // thumb_filepathを相対パスに変換
        if (newThumbPath != null && newThumbPath.startsWith(docsPath)) {
          newThumbPath = newThumbPath.substring(docsPath.length + 1);
          needsUpdate = true;
        }
        
        // 更新が必要な場合のみデータベースを更新
        if (needsUpdate) {
          await db.update(
            'Messages',
            {
              'filepath': newFilePath,
              'thumb_filepath': newThumbPath,
            },
            where: 'id = ?',
            whereArgs: [message['id']],
          );
        }
      }
      
      debugPrint('Successfully migrated paths to relative format');
    } catch (e) {
      debugPrint('Error during path migration: $e');
    }
  }

  // アイコンパスを相対パスに変換するマイグレーション処理
  Future<void> _migrateIconPathsToRelative(Database db) async {
    try {
      final docsPath = await getDocumentsPath();
      
      // すべてのTalksレコードを取得
      final talks = await db.query('Talks');
      
      for (var talk in talks) {
        final iconPath = talk['icon_path'] as String?;
        
        if (iconPath != null && iconPath.isNotEmpty && !iconPath.startsWith('assets/')) {
          String newIconPath = iconPath;
          
          // 絶対パスを相対パスに変換
          if (iconPath.startsWith(docsPath)) {
            newIconPath = iconPath.substring(docsPath.length + 1);
          } else if (iconPath.startsWith('/')) {
            // 異なるアプリケーションパスの場合、ファイル名のみを保持
            final fileName = iconPath.split('/').last;
            final talkName = talk['name'] as String;
            newIconPath = '$talkName/icons/$fileName';
          }
          
          // データベースを更新
          if (newIconPath != iconPath) {
            await db.update(
              'Talks',
              {'icon_path': newIconPath},
              where: 'id = ?',
              whereArgs: [talk['id']],
            );
            debugPrint('Migrated icon path for ${talk['name']}: $iconPath -> $newIconPath');
          }
        }
      }
      
      debugPrint('Successfully migrated icon paths to relative format');
    } catch (e) {
      debugPrint('Error during icon path migration: $e');
    }
  }

  Future<void> insertData(List<List<dynamic>> csvData) async {
    final db = await database;
    for (var row in csvData) {
      // print(row[0]);
      // ファイルパスを相対パスに変換して保存
      final relativePath = await toRelativePath(row[4]);
      final relativeThumbPath = await toRelativePath(row[5]);
      
      // 動画時間を取得（7番目のカラムがある場合）
      int? videoDuration;
      if (row.length > 7) {
        videoDuration = row[7] is int ? row[7] : null;
      }
      
      // 音声時間を取得（8番目のカラムがある場合）
      int? audioDuration;
      if (row.length > 8) {
        audioDuration = row[8] is int ? row[8] : null;
      }
      
      await db.insert(
        'Messages',
        {
          'id': row[0],
          'name': row[1],
          'date': formatDateTimeForDatabase(row[2]),
          'text': row[3],
          'filepath': relativePath,
          'thumb_filepath': relativeThumbPath,
          'is_favorite': row[6] == 'TRUE' ? 1 : 0,  // Adjusted index for is_favorite
          'video_duration': videoDuration,
          'audio_duration': audioDuration,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    debugPrint('Data inserted successfully');
  }


  Future<List<Map<String, dynamic>>> getMessages(String? name, int offset, int limit) async {
    final db = await database;
    final messages = await db.query(
      'Messages',
      where: name != null ? 'name = ?' : null,
      whereArgs: name != null ? [name] : null,
      limit: limit,
      offset: offset,
      orderBy: 'id DESC'  // 最新のデータから取得する場合
    );
    return await convertPathsToAbsolute(messages);
  }

  /// (A) 最新から limit 件だけ取得 (id DESC)
  Future<List<Map<String, dynamic>>> getNewestMessages(String? name, int limit) async {
    final db = await database;
    final messages = await db.query(
      'Messages',
      where: 'name = ?',
      whereArgs: [name],
      orderBy: 'id DESC',
      limit: limit,
    );
    return await convertPathsToAbsolute(messages);
  }

  /// (B) 指定した id より古いメッセージを limit 件 (id DESC)
  Future<List<Map<String, dynamic>>> getOlderMessages(String? name, int olderThanId, int limit) async {
    final db = await database;
    final messages = await db.query(
      'Messages',
      where: 'name = ? AND id < ?',
      whereArgs: [name, olderThanId],
      orderBy: 'id DESC',
      limit: limit,
    );
    return await convertPathsToAbsolute(messages);
  }

  Future<List<Map<String, dynamic>>> getNewerMessages(String? name, int currentMaxId, int limit) async {
    final db = await database;
    final messages = await db.query(
      'Messages',
      where: 'name = ? AND id > ?',
      whereArgs: [name, currentMaxId],
      orderBy: 'id DESC', // 新しい順
      limit: limit,
    );
    return await convertPathsToAbsolute(messages);
  }

  Future<List<Map<String, dynamic>>> getMessagesSinceDate(String? name, DateTime date) async {
    final db = await database;
    // 例: date以上の投稿だけ
    final messages = await db.rawQuery('''
      SELECT * FROM Messages
      WHERE name = ?
        AND date >= ?
      ORDER BY id DESC
    ''', [name, date.toIso8601String()]);
    return await convertPathsToAbsolute(messages);
  }


  Future<List<Map<String, dynamic>>> getAllMessages() async {
    final db = await database;
    final messages = await db.query(
      'Messages',
      orderBy: 'id DESC'
    );
    return await convertPathsToAbsolute(messages);
  }

  // 特定のトークの全メッセージを取得（パス変換込み）
  Future<List<Map<String, dynamic>>> getAllMessagesForTalk(String? name) async {
    final db = await database;
    final messages = await db.query(
      'Messages',
      where: 'name = ?',
      whereArgs: [name],
      orderBy: 'id DESC',
    );
    return await convertPathsToAbsolute(messages);
  }

  Future<List<Map<String, dynamic>>> getOlderMessagesById(String? name, int olderThanId, int limit) async {
    final db = await database;
    // id < olderThanId の投稿を id DESC でlimit件
    final messages = await db.query(
      'Messages',
      where: 'name = ? AND id < ?',
      whereArgs: [name, olderThanId],
      orderBy: 'id DESC',
      limit: limit,
    );
    return await convertPathsToAbsolute(messages);
  }


  Future<void> setIconPath(String name, String iconPath) async {
    final db = await database;
    
    // まず既存のレコードがあるか確認
    final existing = await db.query(
      'Talks',
      where: 'name = ?',
      whereArgs: [name],
    );

    if (existing.isNotEmpty) {
      // 既存データがあれば更新
      await db.update(
        'Talks',
        {'icon_path': iconPath},
        where: 'name = ?',
        whereArgs: [name],
      );
    } else {
      // データがなければ挿入
      await db.insert(
        'Talks',
        {'name': name, 'icon_path': iconPath},
      );
    }
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
    
    // まず既存のレコードがあるか確認
    final existing = await db.query(
      'Talks',
      where: 'name = ?',
      whereArgs: [name],
    );

    if (existing.isNotEmpty) {
      // 既存データがあれば更新
      await db.update(
        'Talks',
        {'call_me': callMeName},
        where: 'name = ?',
        whereArgs: [name],
      );
    } else {
      // データがなければ挿入
      await db.insert(
        'Talks',
        {'name': name, 'call_me': callMeName},
      );
    }
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

  // スクロール位置を保存
  Future<void> setScrollIndex(String name, int scrollIndex) async {
    final db = await database;
    debugPrint('Saving scroll index $scrollIndex for $name');
    
    // まず既存のレコードがあるか確認
    final existing = await db.query(
      'Talks',
      where: 'name = ?',
      whereArgs: [name],
    );

    if (existing.isNotEmpty) {
      // 既存データがあれば更新
      await db.update(
        'Talks',
        {'scroll_index': scrollIndex},
        where: 'name = ?',
        whereArgs: [name],
      );
      debugPrint('Updated scroll index for $name');
    } else {
      // データがなければ挿入
      await db.insert(
        'Talks',
        {'name': name, 'scroll_index': scrollIndex},
      );
      debugPrint('Inserted new talk with scroll index for $name');
    }
  }

  // スクロール位置を取得
  Future<int> getScrollIndex(String name) async {
    final db = await database;
    final result = await db.query(
      'Talks',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );

    if (result.isNotEmpty) {
      final scrollIndex = result.first['scroll_index'] as int? ?? 0;
      debugPrint('Retrieved scroll index $scrollIndex for $name');
      return scrollIndex;
    }
    debugPrint('No scroll index found for $name, returning 0');
    return 0;
  }

  // トーク名を更新
  Future<void> updateTalkName(String oldName, String newName) async {
    final db = await database;
    
    // トランザクションを使用して、関連するすべてのテーブルを更新
    await db.transaction((txn) async {
      // Talksテーブルの名前を更新
      await txn.update(
        'Talks',
        {'name': newName},
        where: 'name = ?',
        whereArgs: [oldName],
      );
      
      // Messagesテーブルの名前を更新
      await txn.update(
        'Messages',
        {'name': newName},
        where: 'name = ?',
        whereArgs: [oldName],
      );
    });
    
    // SharedPreferencesの設定も移行
    final prefs = await SharedPreferences.getInstance();
    
    // 背景画像関連の設定を移行
    final backgroundImagePath = prefs.getString('${oldName}_background_image_path');
    final backgroundOpacity = prefs.getDouble('${oldName}_background_opacity');
    final backgroundFit = prefs.getInt('${oldName}_background_fit');
    
    if (backgroundImagePath != null) {
      await prefs.setString('${newName}_background_image_path', backgroundImagePath);
      await prefs.remove('${oldName}_background_image_path');
    }
    if (backgroundOpacity != null) {
      await prefs.setDouble('${newName}_background_opacity', backgroundOpacity);
      await prefs.remove('${oldName}_background_opacity');
    }
    if (backgroundFit != null) {
      await prefs.setInt('${newName}_background_fit', backgroundFit);
      await prefs.remove('${oldName}_background_fit');
    }
    
    // アイコンパスの設定を移行
    final iconPath = prefs.getString('${oldName}_icon_path');
    if (iconPath != null) {
      await prefs.setString('${newName}_icon_path', iconPath);
      await prefs.remove('${oldName}_icon_path');
    }
    
    // Call Me名の設定を移行
    final callMeName = prefs.getString('${oldName}_call_me');
    if (callMeName != null) {
      await prefs.setString('${newName}_call_me', callMeName);
      await prefs.remove('${oldName}_call_me');
    }
    
    debugPrint('トーク名を "$oldName" から "$newName" に更新しました。');
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
    final messages = await db.query(
      'Messages',
      where: 'name = ? AND is_favorite = 1',
      whereArgs: [name],
      orderBy: 'id DESC',
      limit: limit,
      offset: offset,
    );
    return await convertPathsToAbsolute(messages);
  }


    // database_helper.dart (抜粋)
  Future<List<Map<String, dynamic>>> getImageMessages(String name) async {
    final db = await database;
    final messages = await db.query(
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
    return await convertPathsToAbsolute(messages);
  }

  Future<List<Map<String, dynamic>>> getVideoMessages(String name) async {
    final db = await database;
    final messages = await db.query(
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
    return await convertPathsToAbsolute(messages);
  }

  Future<List<Map<String, dynamic>>> getAudioMessages(String name) async {
    final db = await database;
    final messages = await db.query(
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
    return await convertPathsToAbsolute(messages);
  }

  // 最古のメッセージの日付を取得
  Future<DateTime?> getOldestMessageDate(String name) async {
    final db = await database;
    final result = await db.query(
      'Messages',
      where: 'name = ?',
      whereArgs: [name],
      orderBy: 'date ASC',
      limit: 1,
    );

    if (result.isNotEmpty) {
      final dateString = result.first['date'] as String?;
      if (dateString != null) {
        return DateTime.parse(dateString);
      }
    }
    return null;
  }

  // トーク内の全メッセージの日付範囲を取得
  Future<Map<String, DateTime?>> getMessageDateRange(String name) async {
    final db = await database;
    
    // 最古のメッセージ
    final oldestResult = await db.query(
      'Messages',
      where: 'name = ?',
      whereArgs: [name],
      orderBy: 'date ASC',
      limit: 1,
    );
    
    // 最新のメッセージ
    final newestResult = await db.query(
      'Messages',
      where: 'name = ?',
      whereArgs: [name],
      orderBy: 'date DESC',
      limit: 1,
    );
    
    DateTime? oldest;
    DateTime? newest;
    
    if (oldestResult.isNotEmpty) {
      final dateString = oldestResult.first['date'] as String?;
      if (dateString != null) {
        oldest = DateTime.parse(dateString);
      }
    }
    
    if (newestResult.isNotEmpty) {
      final dateString = newestResult.first['date'] as String?;
      if (dateString != null) {
        newest = DateTime.parse(dateString);
      }
    }
    
    return {
      'oldest': oldest,
      'newest': newest,
    };
  }

  Future<void> updateVideoDuration(int id, int duration) async {
    final db = await database;
    await db.update(
      'Messages',
      {'video_duration': duration},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  Future<void> updateAudioDuration(int id, int duration) async {
    final db = await database;
    await db.update(
      'Messages',
      {'audio_duration': duration},
      where: 'id = ?',
      whereArgs: [id],
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
    return await convertPathsToAbsolute(combined);
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

    return await convertPathsToAbsolute(result);
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
            debugPrint('ファイル削除エラー: $e');
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
            debugPrint('サムネイル削除エラー: $e');
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
    
    debugPrint('トーク "$talkName" の削除が完了しました。');
  }


  // トークを追加
  Future<void> addTalk(String talkName, String iconPath) async {
    final db = await database;
    await db.insert(
      'Talks',
      {'name': talkName, 'icon_path': iconPath},
      conflictAlgorithm: ConflictAlgorithm.replace, // すでに存在する場合は上書き
    );
  }
  
  // すべてのトークを取得
  Future<List<Map<String, dynamic>>> getAllTalks() async {
    final db = await database;
    return await db.query('Talks');
  }

}