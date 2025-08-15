import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart'; // Archive 4.0.4 用の archive_io.dart
import 'package:path/path.dart' as p;
import 'package:csv/csv.dart';
import 'package:video_player/video_player.dart';
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
    // ZIPファイル名からフォルダ名を生成（例：sample.zip → sample）
    final rootFolderName = p.basenameWithoutExtension(zipFilePath); // hoge岸piyoり.zip -> hoge岸piyoり


    // InputFileStream を用いて ZIP をストリーム処理し、decodeStream で Archive を取得
    final inputStream = InputFileStream(zipFilePath);
    final archive = ZipDecoder().decodeStream(inputStream);

    // extractArchiveToDisk で Archive の内容を extractPath に直接展開
    await extractArchiveToDisk(archive, directory.path);

    // 展開先ディレクトリ内から CSV ファイルを検索
    final extractPath = p.join(directory.path, rootFolderName); // アプリのドキュメントディレクトリ/hoge岸piyoり
    final csvFiles = Directory(extractPath)
        .listSync(recursive: true)
        .where((entity) => entity is File && entity.path.endsWith('.csv'))
        .toList();

    if (csvFiles.isNotEmpty) {
      return await _processWithCsvFromDisk(
          extractPath, (csvFiles.first as File).path, rootFolderName);
    } else {
      return await _processWithoutCsvFromDisk(extractPath, rootFolderName);
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
          // 画像の場合はvideo_durationをnullに
          row.add(null);
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
              row.add(duration.inMilliseconds); // ミリ秒単位で保存
              controller.dispose();
            } catch (e) {
              print('Error getting video duration: $e');
              row.add(null); // エラー時はnullを追加
            }
          } else {
            row.insert(5, "");
            row.add(null); // ファイルが存在しない場合もnullを追加
          }
        } else {
          // 動画以外のファイルの場合はnullを追加
          if (row.length == 6) {
            row.add(null);
          }
        }

      
      } else {
        row.insert(5, "");
        row.add(null); // ファイルパスが空の場合もvideo_durationをnullに
      }
    }

    await dbHelper.insertData(fields);
    return fields.isNotEmpty ? fields[0][1] : null;
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
    final audioExtensions = {'.mp4'};

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
        entry["video_duration"],  // 動画時間を追加
      ]);
    }

    if (extractedData.isNotEmpty) {
      await dbHelper.insertData(extractedData);
    }
    return extractedName;
  }
}