import 'package:flutter/services.dart' show rootBundle;

/// Reads raw GTFS files. Swap this for an HTTP download later.
class TransitApi {
  Future<List<Map<String, String>>> readTable(String file) async {
    var text = await rootBundle.loadString('GTFS/$file');
    if (text.startsWith('\uFEFF')) text = text.substring(1); // strip BOM
    final rows = _parseCsv(text);
    if (rows.isEmpty) return [];
    final header = rows.first.map((e) => e.trim()).toList();
    return [
      for (final r in rows.skip(1))
        if (r.length >= header.length)
          {for (var i = 0; i < header.length; i++) header[i]: r[i].trim()},
    ];
  }

  List<List<String>> _parseCsv(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == ',') {
        row.add(field.toString());
        field.clear();
      } else if (c == '\n') {
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
      } else if (c != '\r') {
        field.write(c);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }
}