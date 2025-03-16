import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart';
import 'package:csv/csv.dart';
import '../utils/database_helper.dart';

class FileManager {
  final DatabaseHelper dbHelper;

  FileManager(this.dbHelper);

  /// **ZIPファイルを選択する**
  Future<String?> pickZipFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result != null) {
      return result.files.single.path!;
    }
    return null;
  }

  /// **ZIPを解凍してCSVデータをDBに保存**
  Future<String?> processZip(String zipFilePath) async {
    final bytes = File(zipFilePath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final directory = await getApplicationDocumentsDirectory();

    // ZIPフォルダ名を取得
    String? rootFolderName;
    for (final file in archive) {
      final parts = file.name.split('/');
      if (parts.isNotEmpty) {
        rootFolderName = parts.first;
        break;
      }
    }

    if (rootFolderName == null) {
      throw Exception('Invalid ZIP structure.');
    }

    final extractPath = join(directory.path, rootFolderName);
    Directory(extractPath).createSync(recursive: true);

    

    String? csvFilePath;

    // ZIP内のCSVファイルを抽出
    for (final file in archive) {
      final filePath = join(extractPath, file.name.replaceFirst('$rootFolderName/', ''));

      if (file.isFile && !file.name.contains('__MACOSX')) {
        final data = file.content as List<int>;
        File(filePath)..createSync(recursive: true)..writeAsBytesSync(data);

        if (file.name.endsWith('.csv')) {
          csvFilePath = filePath;
        }
      }
    }

    

    if (csvFilePath != null) {
      final input = File(csvFilePath).openRead();
      final fields = await input
          .transform(utf8.decoder)
          .transform(const CsvToListConverter(eol: '\n', fieldDelimiter: ','))
          .toList();

      fields.removeAt(0); // ヘッダーを削除
      await dbHelper.insertData(fields);

      String? name;

      if (fields.isNotEmpty) {
        name = fields[0][1];
      }
      // 例: ファイル解凍後、DBにINSERTしたあと
      final allMessages = await dbHelper.getAllMessages();
      print("Total messages in DB: ${allMessages.length}");
      

      return name;

    }
  }
}
