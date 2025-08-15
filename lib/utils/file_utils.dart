import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart'; // Archive 4.0.4 用の archive_io.dart
import 'package:path/path.dart' as p;
import 'package:csv/csv.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';
import '../utils/database_helper.dart';
import 'helper.dart';

class FileManager {
  final DatabaseHelper dbHelper;

  FileManager(this.dbHelper);

  /// ZIPファイルを選択する
  Future<String?> pickZipFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result != null) {
      return result.files.single.path;
    }
    return null;
  }

  /// ZIPを解凍してデータベースに保存する
  Future<String?> processZip(String zipFilePath) async {
    final directory = await getApplicationDocumentsDirectory(); // アプリのドキュメントディレクトリ
    // ZIPファイル名からトーク名を生成（例：sample.zip → sample）
    final talkName = p.basenameWithoutExtension(zipFilePath); // これがトーク名として使用される
    
    // InputFileStream を用いて ZIP をストリーム処理し、decodeStream で Archive を取得
    final inputStream = InputFileStream(zipFilePath);
    final archive = ZipDecoder().decodeStream(inputStream);
    
    // アーカイブ内の実際のフォルダ名を取得
    String? actualFolderName;
    for (final file in archive) {
      if (file.name.contains('/')) {
        actualFolderName = file.name.split('/').first;
        break;
      }
    }
    
    // 実際のフォルダ名がない場合はトーク名を使用
    if (actualFolderName == null) {
      actualFolderName = talkName;
    }
    
    // extractArchiveToDisk で Archive の内容を extractPath に直接展開
    await extractArchiveToDisk(archive, directory.path);
    
    // 展開先ディレクトリ（実際のフォルダ名を使用）
    final extractPath = p.join(directory.path, actualFolderName);
    
    // 展開先ディレクトリ内から CSV ファイルを検索
    final csvFiles = Directory(extractPath)
        .listSync(recursive: true)
        .where((entity) => entity is File && entity.path.endsWith('.csv'))
        .toList();

    if (csvFiles.isNotEmpty) {
      return await _processWithCsvFromDisk(
          extractPath, (csvFiles.first as File).path, talkName); // トーク名を渡す
    } else {
      return await _processWithoutCsvFromDisk(extractPath, talkName); // トーク名を渡す
    }
  }

  /// CSV が存在する場合の処理（ディスク上のファイルを利用）
  Future<String?> _processWithCsvFromDisk(
      String extractPath, String csvFilePath, String rootFolderName) async {
    final mediaPath = p.join(extractPath, 'media'); // アプリのドキュメントディレクトリ/hoge岸piyoり/media
   

    // CSV ファイルを読み込み、パースする
    final input = File(csvFilePath).openRead();
    final fields = await input
        .transform(utf8.decoder)
        .transform(const CsvToListConverter(eol: '\n', fieldDelimiter: ','))
        .toList();

    if (fields.isNotEmpty) {
      fields.removeAt(0); // ヘッダー行を削除
    }

    // CSV の各行について、ファイルパスやサムネイルパスを更新
    for (var row in fields) {
      if (row.length > 4 &&
          row[4] is String &&
          (row[4] as String).isNotEmpty) {
        final filename = row[4] as String;
        // メディアファイルのフルパス（media フォルダ内に配置）
        final fullFilePath = p.join(mediaPath, filename);
        row[4] = fullFilePath;

        String thumb = "";
        if (filename.endsWith('.jpg')) {
          thumb = filename.replaceFirst('.jpg', '_thumb.jpg');

          final fullThumbPath = p.join(mediaPath, thumb);
          if (File(fullFilePath).existsSync()) {
            await generateThumbnail(fullFilePath, fullThumbPath);
            row.insert(5, fullThumbPath);
          } else {
            row.insert(5, "");
          }
          // 画像の場合はvideo_durationとaudio_durationをnullに
          row.add(null);  // video_duration
          row.add(null);  // audio_duration
        } else if (filename.endsWith('.mp4')) {
          thumb = filename.replaceFirst('.mp4', '_thumb.jpg');

          final fullThumbPath = p.join(mediaPath, thumb);
          if (File(fullFilePath).existsSync()) {
            await generateVideoThumbnail(fullFilePath, fullThumbPath);
            row.insert(5, fullThumbPath);
            
            // 動画の長さを取得
            try {
              final controller = VideoPlayerController.file(File(fullFilePath));
              await controller.initialize();
              final duration = controller.value.duration;
              row.add(duration.inMilliseconds); // video_duration（ミリ秒単位で保存）
              controller.dispose();
            } catch (e) {
              print('Error getting video duration: $e');
              row.add(null); // エラー時はnullを追加
            }
            row.add(null); // audio_durationはnull
          } else {
            row.insert(5, "");
            row.add(null); // video_durationがnull
            row.add(null); // audio_durationがnull
          }
        } else if (filename.endsWith('.m4a') || (filename.contains('_3_') && filename.endsWith('.mp4'))) {
          // 音声ファイルの処理
          row.insert(5, ""); // サムネイルなし
          row.add(null); // video_durationはnull
          
          // 音声の長さを取得
          if (File(fullFilePath).existsSync()) {
            try {
              final audioPlayer = AudioPlayer();
              final duration = await audioPlayer.setFilePath(fullFilePath);
              if (duration != null) {
                row.add(duration.inMilliseconds); // audio_duration（ミリ秒単位で保存）
              } else {
                row.add(null);
              }
              audioPlayer.dispose();
            } catch (e) {
              print('Error getting audio duration: $e');
              row.add(null); // エラー時はnullを追加
            }
          } else {
            row.add(null); // ファイルが存在しない場合もnullを追加
          }
        } else {
          // その他のファイルの場合
          row.insert(5, ""); // サムネイルなし
          row.add(null); // video_durationはnull
          row.add(null); // audio_durationはnull
        }

      
      } else {
        row.insert(5, "");
        row.add(null); // video_durationをnullに
        row.add(null); // audio_durationをnullに
      }
    }

    // CSV内の名前をtalkNameに置き換える
    for (var row in fields) {
      if (row.length > 1) {
        row[1] = rootFolderName; // トーク名として使用
      }
    }
    
    await dbHelper.insertData(fields);
    return rootFolderName; // トーク名を返す
  }

  /// CSV が存在しない場合の処理（ディスク上のファイルを利用）
  Future<String?> _processWithoutCsvFromDisk(
      String extractPath, String rootFolderName) async {
    List<List<dynamic>> extractedData = [];
    String? extractedName;
    final mediaPath = p.join(extractPath, 'media');
    Directory(mediaPath).createSync(recursive: true);

    final textExtensions = {'.txt'};
    final imageExtensions = {'.jpg', '.jpeg', '.png'};
    final videoExtensions = {'.mp4'};
    final audioExtensions = {'.m4a', '.mp4'};

    Map<String, Map<String, dynamic>> groupedEntries = {};
    // 再帰的に展開ディレクトリ内の全ファイルを取得
    final files = Directory(extractPath)
        .listSync(recursive: true)
        .whereType<File>();
    final regex =
        RegExp(r'(\d+)_(\d)_(\d{14})\.(txt|jpg|jpeg|png|mp4|m4a)');

    for (final file in files) {
      final relativePath = p.relative(file.path, from: extractPath);
      final match = regex.firstMatch(relativePath);
      if (match == null) continue;

      final String id = match.group(1)!;
      final int type = int.parse(match.group(2)!);
      final String date = match.group(3)!;
      final String extension = match.group(4)!;

      if (extractedName == null) extractedName = rootFolderName;

      groupedEntries.putIfAbsent(id, () => {
            "id": id,
            "name": rootFolderName,
            "date": date,
            "text": null,
            "filepath": null,
            "thumb_filepath": null,
            "is_favorite": false,
          });

      if ((type == 0 || type == 1) &&
          textExtensions.contains(".$extension")) {
        groupedEntries[id]!["text"] = file.readAsStringSync();
      } else if (type == 1 && imageExtensions.contains(".$extension")) {
        final mediaFilePath = p.join(mediaPath, p.basename(file.path));
        file.copySync(mediaFilePath);
        groupedEntries[id]!["filepath"] = mediaFilePath;

        final thumbFileName =
            p.basenameWithoutExtension(file.path) + "_thumb.$extension";
        final thumbFilePath = p.join(mediaPath, thumbFileName);
        try {
          await generateThumbnail(mediaFilePath, thumbFilePath);
          groupedEntries[id]!["thumb_filepath"] = thumbFilePath;
        } catch (e) {
          throw Exception(
              "Failed to generate thumbnail for $mediaFilePath: $e");
        }
      } else if (type == 2 && videoExtensions.contains(".$extension")) {
        final mediaFilePath = p.join(mediaPath, p.basename(file.path));
        file.copySync(mediaFilePath);
        groupedEntries[id]!["filepath"] = mediaFilePath;

        final thumbFileName =
            p.basenameWithoutExtension(file.path) + "_thumb.jpg";
        final thumbFilePath = p.join(mediaPath, thumbFileName);
        try {
          await generateVideoThumbnail(mediaFilePath, thumbFilePath);
          groupedEntries[id]!["thumb_filepath"] = thumbFilePath;
        } catch (e) {
          throw Exception(
              "Failed to generate video thumbnail for $mediaFilePath: $e");
        }
        
        // 動画の長さを取得
        try {
          final controller = VideoPlayerController.file(File(mediaFilePath));
          await controller.initialize();
          final duration = controller.value.duration;
          groupedEntries[id]!["video_duration"] = duration.inMilliseconds;
          controller.dispose();
        } catch (e) {
          print('Error getting video duration: $e');
          groupedEntries[id]!["video_duration"] = null;
        }
      } else if (type == 3 && audioExtensions.contains(".$extension")) {
        final mediaFilePath = p.join(mediaPath, p.basename(file.path));
        file.copySync(mediaFilePath);
        groupedEntries[id]!["filepath"] = mediaFilePath;
        
        // 音声の長さを取得
        try {
          final audioPlayer = AudioPlayer();
          final duration = await audioPlayer.setFilePath(mediaFilePath);
          if (duration != null) {
            groupedEntries[id]!["audio_duration"] = duration.inMilliseconds;
          } else {
            groupedEntries[id]!["audio_duration"] = null;
          }
          audioPlayer.dispose();
        } catch (e) {
          print('Error getting audio duration: $e');
          groupedEntries[id]!["audio_duration"] = null;
        }
      }
    }

    for (var entry in groupedEntries.values) {
      extractedData.add([
        entry["id"],
        entry["name"],
        entry["date"],
        entry["text"] ?? "",
        entry["filepath"],
        entry["thumb_filepath"],
        false,
        entry["video_duration"],  // 動画時間
        entry["audio_duration"],  // 音声時間を追加
      ]);
    }

    if (extractedData.isNotEmpty) {
      await dbHelper.insertData(extractedData);
    }
    return extractedName;
  }
}