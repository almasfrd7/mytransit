// Dev tool: fetch the KTMB GTFS-Realtime feed, decode it, and check how
// well live trip ids join against the bundled static schedule.
//
// Run: dart run tool/check_live_feed.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:MYTransit/services/gtfs_realtime_service.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  const url =
      'https://api.data.gov.my/gtfs-realtime/vehicle-position/ktmb/';
  final svc = GtfsRealtimeService();

  final res = await http.get(Uri.parse(url));
  print('HTTP ${res.statusCode}, ${res.bodyBytes.length} bytes');
  if (res.statusCode != 200) return;

  final sw = Stopwatch()..start();
  final positions = svc.decode(res.bodyBytes);
  sw.stop();
  print('decoded ${positions.length} vehicles in ${sw.elapsedMilliseconds}ms');
  if (positions.isEmpty) {
    print('EMPTY FEED or decode failure');
    return;
  }

  // Join against the bundled KTMB static trips.
  final tripRoutes = <String, String>{};
  final f = File('GTFS/ktmb/trips.txt');
  if (f.existsSync()) {
    final lines = f.readAsLinesSync();
    if (lines.isNotEmpty) {
      final header = lines.first.split(',').map((h) => h.trim()).toList();
      final ti = header.indexOf('trip_id');
      final ri = header.indexOf('route_id');
      if (ti >= 0 && ri >= 0) {
        for (final line in lines.skip(1)) {
          final cols = line.split(',');
          if (cols.length > [ti, ri].reduce((a, b) => a > b ? a : b)) {
            tripRoutes[cols[ti].trim()] = cols[ri].trim();
          }
        }
      }
    }
  }
  print('static trip index: ${tripRoutes.length} trips');

  var joined = 0;
  var withRouteId = 0;
  for (final p in positions) {
    if (p.routeId != null) withRouteId++;
    if (p.tripId != null && tripRoutes.containsKey(p.tripId)) joined++;
  }
  print('positions with routeId from feed: $withRouteId');
  print('trip ids joined to static schedule: $joined/${positions.length}');

  for (final p in positions.take(8)) {
    final route = tripRoutes[p.tripId];
    print('  ${p.displayName.padRight(8)} '
        'trip=${p.tripId ?? '-'} route=${route ?? p.routeId ?? '?'} '
        'lat=${p.lat.toStringAsFixed(4)} lng=${p.lng.toStringAsFixed(4)} '
        '${p.speedKmhLabel()} ${p.compassHeading()} '
        'feedTime=${p.fetchedAt.toIso8601String()}');
  }
}
