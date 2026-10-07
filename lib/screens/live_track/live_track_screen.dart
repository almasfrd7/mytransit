import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/route.dart';
import '../../models/station.dart';
import '../../repositories/transit_repositories.dart';
import '../../services/transit_api.dart';

/// Draws a line's shape with its stations and moves a train marker along it.
class LiveTrackScreen extends StatefulWidget {
  const LiveTrackScreen({super.key, this.repo});

  /// Reuse a repository so GTFS tables are only parsed once per session.
  final TransitRepository? repo;

  @override
  State<LiveTrackScreen> createState() => _LiveTrackScreenState();
}

class _LiveTrackScreenState extends State<LiveTrackScreen>
    with SingleTickerProviderStateMixin {
  late final TransitRepository _repo =
      widget.repo ?? TransitRepository(TransitApi());
  late final Future<List<TransitRoute>> _routes = _repo.getRoutes();

  final Map<String, Future<_TrackData>> _tracks = {};
  String? _routeId;

  late final AnimationController _marker;

  Future<_TrackData> _trackFor(TransitRoute r) => _tracks[r.id] ??= () async {
        final shapes = await _repo.getShapesForRoute(r.id);
        final stations = await _repo.getStationsForRoute(r.id);
        return _TrackData(r, shapes.values.toList(), stations);
      }();

  @override
  void initState() {
    super.initState();
    _marker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    )..repeat();
  }

  @override
  void dispose() {
    _marker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live track')),
      body: FutureBuilder<List<TransitRoute>>(
        future: _routes,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Failed to load: ${snap.error}'));
          }
          final routes = snap.data ?? const <TransitRoute>[];
          if (routes.isEmpty) {
            return const Center(child: Text('No lines available.'));
          }
          final route = routes.firstWhere((r) => r.id == _routeId,
              orElse: () => routes.first);

          return Column(
            children: [
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  children: [
                    for (final r in routes)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: CircleAvatar(
                            radius: 6,
                            backgroundColor: Color(r.colorValue),
                          ),
                          label: Text(r.shortName),
                          selected: r.id == route.id,
                          onSelected: (_) => setState(() => _routeId = r.id),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<_TrackData>(
                  future: _trackFor(route),
                  builder: (context, t) {
                    if (t.hasError) {
                      return Center(
                          child: Text('Could not load map: ${t.error}'));
                    }
                    if (!t.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final data = t.data!;
                    if (data.shapes.isEmpty) {
                      return const Center(
                        child: Text('No map geometry for this line yet.'),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Column(
                        children: [
                          Expanded(child: _TrackMap(data: data, animation: _marker)),
                          const SizedBox(height: 12),
                          _TrackInfo(data: data),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrackData {
  _TrackData(this.route, this.shapes, this.stations);
  final TransitRoute route;
  final List<List<({double lng, double lat})>> shapes;
  final List<Station> stations;
}

// ───────────────────────── Map ─────────────────────────

class _TrackMap extends StatelessWidget {
  const _TrackMap({required this.data, required this.animation});

  final _TrackData data;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: SizedBox.expand(
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) => CustomPaint(
              painter: _TrackPainter(
                shapes: data.shapes,
                stations: data.stations,
                color: Color(data.route.colorValue),
                dotFill: cs.surface,
                progress: animation.value,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.shapes,
    required this.stations,
    required this.color,
    required this.dotFill,
    this.progress = 0,
  });

  final List<List<({double lng, double lat})>> shapes;
  final List<Station> stations;
  final Color color;
  final Color dotFill;

  /// Position of the marker along the first shape, 0..1.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (shapes.isEmpty || size.isEmpty) return;

    double minLng = double.infinity, maxLng = double.negativeInfinity;
    double minLat = double.infinity, maxLat = double.negativeInfinity;
    void grow(double lng, double lat) {
      minLng = math.min(minLng, lng);
      maxLng = math.max(maxLng, lng);
      minLat = math.min(minLat, lat);
      maxLat = math.max(maxLat, lat);
    }

    for (final path in shapes) {
      for (final p in path) {
        grow(p.lng, p.lat);
      }
    }
    for (final s in stations) {
      grow(s.lng, s.lat);
    }

    final spanLng = maxLng - minLng;
    final spanLat = maxLat - minLat;
    if (spanLng <= 0 || spanLat <= 0) return;

    const pad = 22.0;
    final scale = math.min(
      (size.width - 2 * pad) / spanLng,
      (size.height - 2 * pad) / spanLat,
    );
    if (!scale.isFinite || scale <= 0) return;

    final dx = (size.width - spanLng * scale) / 2;
    final dy = (size.height - spanLat * scale) / 2;
    Offset proj(double lng, double lat) =>
        Offset(dx + (lng - minLng) * scale, dy + (maxLat - lat) * scale);

    // Line: soft halo underneath, solid colour on top.
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: 0.22);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    for (final path in shapes) {
      if (path.length < 2) continue;
      final geo = Path();
      for (var i = 0; i < path.length; i++) {
        final p = proj(path[i].lng, path[i].lat);
        i == 0 ? geo.moveTo(p.dx, p.dy) : geo.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(geo, halo);
      canvas.drawPath(geo, line);
    }

    // Stations along the line.
    final fill = Paint()..color = dotFill;
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (final s in stations) {
      final p = proj(s.lng, s.lat);
      canvas.drawCircle(p, 5.5, fill);
      canvas.drawCircle(p, 5.5, ring);
    }

    // Moving train marker.
    final path = [
      for (final p in shapes.first) proj(p.lng, p.lat),
    ];
    if (path.isEmpty) return;
    final at = _pointAt(path, progress);

    canvas.drawCircle(at, 15, Paint()..color = color.withValues(alpha: 0.30));
    canvas.drawCircle(at, 11.5, Paint()..color = color);
    canvas.drawCircle(
      at,
      11.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    final glyph = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.train.codePoint),
        style: TextStyle(
          fontSize: 13,
          height: 1,
          fontFamily: Icons.train.fontFamily,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    glyph.paint(canvas, at - Offset(glyph.width / 2, glyph.height / 2));
  }

  static Offset _pointAt(List<Offset> path, double t) {
    if (path.length == 1) return path.first;
    var target = t.clamp(0.0, 1.0);
    final total = _lengthOf(path);
    if (total <= 0) return path.first;
    target *= total;
    for (var i = 1; i < path.length; i++) {
      final d = (path[i] - path[i - 1]).distance;
      if (target <= d) {
        final f = d == 0 ? 0.0 : target / d;
        return Offset.lerp(path[i - 1], path[i], f)!;
      }
      target -= d;
    }
    return path.last;
  }

  static double _lengthOf(List<Offset> path) {
    var total = 0.0;
    for (var i = 1; i < path.length; i++) {
      total += (path[i] - path[i - 1]).distance;
    }
    return total;
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.dotFill != dotFill ||
      old.shapes != shapes ||
      old.stations != stations;
}

// ───────────────────────── Info ─────────────────────────

class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.data});

  final _TrackData data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = data.route;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Color(r.colorValue),
              child: Text(
                r.shortName,
                style: TextStyle(
                  color: Color(r.textColorValue),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.longName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${data.stations.length} stations · ${r.category}',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: cs.outline),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Preview — the marker follows the route shape; '
                          'live GPS is coming soon.',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
