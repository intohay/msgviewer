

String formatDateTimeForDatabase(String inputDateTime) {
  DateTime parsedDateTime;

  if (RegExp(r'^\d{4}-\d{4}-\d{6}$').hasMatch(inputDateTime)) {
    // `2024-1217-161129` の形式ならそのままパース
    parsedDateTime = DateTime.parse(
        "${inputDateTime.substring(0, 4)}-${inputDateTime.substring(5, 7)}-${inputDateTime.substring(7, 9)} "
        "${inputDateTime.substring(10, 12)}:${inputDateTime.substring(12, 14)}:${inputDateTime.substring(14, 16)}");
  } else if (RegExp(r'^\d{14}$').hasMatch(inputDateTime)) {
    // `20241217161129` の形式ならパースして9時間足す
    parsedDateTime = DateTime.parse(
        "${inputDateTime.substring(0, 4)}-${inputDateTime.substring(4, 6)}-${inputDateTime.substring(6, 8)} "
        "${inputDateTime.substring(8, 10)}:${inputDateTime.substring(10, 12)}:${inputDateTime.substring(12, 14)}")
        .add(Duration(hours: 9));
  } else {
    throw FormatException("Invalid datetime format: $inputDateTime");
  }

  return parsedDateTime.toIso8601String(); // SQLiteのDATETIME型に適した形式で返す
}




