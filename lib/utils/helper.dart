

String datetimeConverter(String datetime) {
  if (datetime.length >= 14) {
    return datetime.substring(0, 4) + "/" + 
           datetime.substring(5, 7) + "/" + 
           datetime.substring(7, 9) + " " + 
           datetime.substring(10, 12) + ":" + 
           datetime.substring(12, 14);
  } else {
    throw FormatException("Invalid datetime format");
  }
}