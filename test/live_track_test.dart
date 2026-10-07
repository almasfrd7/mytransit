import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:MYTransit/repositories/transit_repositories.dart';
import 'package:MYTransit/services/gtfs_realtime_service.dart';
import 'package:MYTransit/services/transit_api.dart';

/// End-to-end checks for the live track feature: both bundled feeds merge,
/// KTMB geometry is derived, and a captured GTFS-Realtime payload decodes
/// and joins to a route.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final repo = TransitRepository(TransitApi());
  final svc = GtfsRealtimeService();

  test('routes merge both feeds', () async {
    final routes = await repo.getRoutes();
    final ids = routes.map((r) => r.id).toSet();

    // Klang Valley rail.
    expect(ids, containsAll(['AG', 'KJ', 'KGL']));
    // KTMB.
    expect(ids, containsAll(['ETS', 'KC05_KB18', 'KA15_KD19']));

    final ets = routes.firstWhere((r) => r.id == 'ETS');
    expect(ets.shortName, 'ETS');
    expect(ets.category, 'KTM');
    expect(ets.colorValue, 0xFFFFC72C);
  });

  test('KTMB stations are derived per route from stop_times', () async {
    final stations = await repo.getStationsForRoute('ETS');
    expect(stations, isNotEmpty);
    expect(stations.every((s) => s.routeId == 'ETS'), isTrue);
    expect(stations.every((s) => s.category == 'KTM'), isTrue);
  });

  test('ETS geometry falls back to the stop sequence (no shapes.txt)',
      () async {
    final shapes = await repo.getShapesForRoute('ETS');
    expect(shapes, isNotEmpty);

    final path = shapes.values.first;
    expect(path.length, greaterThan(5));
    // Somewhere along the west-coast ETS corridor.
    expect(path.first.lat, inInclusiveRange(1.0, 6.5));
    expect(path.first.lng, inInclusiveRange(99.0, 105.0));
  });

  test('captured live payload decodes and every vehicle joins to ETS',
      () async {
    final bytes = Uint8List.fromList(
      File('test/fixtures/ktmb.pb').readAsBytesSync(),
    );
    final positions = svc.decode(bytes);

    expect(positions, isNotEmpty);
    expect(positions.first.label, startsWith('ETS'));
    // Coordinates land in Malaysia, not garbage.
    for (final p in positions) {
      expect(p.lat, inInclusiveRange(1.0, 7.5));
      expect(p.lng, inInclusiveRange(99.0, 120.0));
      // Placeholder speed (90 m/s) must be discarded as implausible.
      expect(p.speed, anyOf(isNull, lessThanOrEqualTo(50.0)));
    }

    final known = (await repo.getRoutes()).map((r) => r.id).toSet();
    final resolved = await repo.resolvePositions(positions, known);
    expect(resolved, hasLength(positions.length));
    expect(resolved.every((p) => p.routeId == 'ETS'), isTrue);
  });

  test('malformed feed bytes decode to an empty list instead of throwing',
      () {
    expect(svc.decode(Uint8List.fromList([0xFF, 0xFF, 0xFF])), isEmpty);
    expect(svc.decode(Uint8List(0)), isEmpty);
  });
}
