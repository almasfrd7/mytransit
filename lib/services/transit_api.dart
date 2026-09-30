import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;

import '../models/route.dart';
import '../models/station.dart';

class TransitService {
  static const String gtfsUrl =
      'https://api.data.gov.my/gtfs-static/prasarana?category=rapid-rail-kl';

  Archive? _archive;

  Future<Archive> _getArchive() async {
    if (_archive != null) {
      return _archive!;
    }

    final response = await http.get(Uri.parse(gtfsUrl));

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to download transit data: ${response.statusCode}',
      );
    }

    _archive = ZipDecoder().decodeBytes(response.bodyBytes);

    return _archive!;
  }

  List<Map<String, dynamic>> _readCsvFile(
      Archive archive,
      String fileName,
      ) {
    final file = archive.findFile(fileName);

    if (file == null) {
      throw Exception('$fileName was not found in the GTFS feed.');
    }

    final text = utf8.decode(file.content as List<int>);

    final cleanedText = text.replaceFirst('\uFEFF', '');

    final rows = const CsvDecoder().convert(cleanedText);

    if (rows.isEmpty) {
      return [];
    }

    final headers = rows.first
        .map((value) => value.toString())
        .toList();

    return rows.skip(1).map((row) {
      final map = <String, dynamic>{};

      for (int i = 0; i < headers.length; i++) {
        if (i < row.length) {
          map[headers[i]] = row[i];
        }
      }

      return map;
    }).toList();
  }

  Future<List<Station>> fetchStations() async {
    final archive = await _getArchive();

    final rows = _readCsvFile(
      archive,
      'stops.txt',
    );

    final stations = <Station>[];

    for (final row in rows) {
      try {
        stations.add(
          Station(
            id: row['stop_id'].toString(),
            name: row['stop_name'].toString(),
            latitude: double.parse(
              row['stop_lat'].toString(),
            ),
            longitude: double.parse(
              row['stop_lon'].toString(),
            ),
          ),
        );
      } catch (_) {
        // Skip invalid station records.
      }
    }

    return stations;
  }

  Future<List<TransitRoute>> fetchRoutes() async {
    final archive = await _getArchive();

    final rows = _readCsvFile(
      archive,
      'routes.txt',
    );

    return rows.map((row) {
      return TransitRoute.fromCsv(row);
    }).toList();
  }
}