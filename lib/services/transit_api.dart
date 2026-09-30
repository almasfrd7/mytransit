import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;

import '../models/station.dart';

class TransitService {
  static const String gtfsUrl =
      'https://api.data.gov.my/gtfs-static/prasarana?category=rapid-rail-kl';

  Future<List<Station>> fetchStations() async {
    final response = await http.get(Uri.parse(gtfsUrl));

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to download transit data: ${response.statusCode}',
      );
    }

    final archive = ZipDecoder().decodeBytes(response.bodyBytes);

    final stopsFile = archive.findFile('stops.txt');

    if (stopsFile == null) {
      throw Exception('stops.txt was not found in the GTFS feed.');
    }

    final csvText = utf8.decode(stopsFile.content as List<int>);

    final cleanedCsv = csvText.replaceFirst('\uFEFF', '');

    final rows = const CsvDecoder().convert(cleanedCsv);

    if (rows.isEmpty) {
      throw Exception('stops.txt is empty.');
    }

    final headers = rows.first.map((value) => value.toString()).toList();

    final stopIdIndex = headers.indexOf('stop_id');
    final stopNameIndex = headers.indexOf('stop_name');
    final latitudeIndex = headers.indexOf('stop_lat');
    final longitudeIndex = headers.indexOf('stop_lon');

    if (stopIdIndex == -1 ||
        stopNameIndex == -1 ||
        latitudeIndex == -1 ||
        longitudeIndex == -1) {
      throw Exception('Required station fields were not found.');
    }

    final stations = <Station>[];

    for (final row in rows.skip(1)) {
      if (row.length <= longitudeIndex) {
        continue;
      }

      try {
        stations.add(
          Station(
            id: row[stopIdIndex].toString(),
            name: row[stopNameIndex].toString(),
            latitude: double.parse(row[latitudeIndex].toString()),
            longitude: double.parse(row[longitudeIndex].toString()),
          ),
        );
      } catch (_) {
        // Skip invalid rows.
      }
    }

    return stations;
  }
}