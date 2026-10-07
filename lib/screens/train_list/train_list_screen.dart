import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/route.dart';
import '../../models/station.dart';
import '../../repositories/transit_repositories.dart';
import '../../services/transit_api.dart';
import '../../widgets/live_clock.dart';
import '../station/station_detail_screen.dart';

/// Searchable list of every station, grouped by line.
class TrainListScreen extends StatefulWidget {
  const TrainListScreen({super.key, this.repo});

  /// Reuse a repository so GTFS tables are only parsed once per session.
  final TransitRepository? repo;

  @override
  State<TrainListScreen> createState() => _TrainListScreenState();
}

// ───────────────────────── Data ─────────────────────────

class _Data {
  final List<TransitRoute> routes;
  final List<Station> stations;
  _Data(this.routes, this.stations);

  late final Map<String, TransitRoute> routesById = {
    for (final r in routes) r.id: r,
  };

  /// Other stops with the same name (interchanges), excluding [s] itself.
  List<Station> interchangesOf(Station s) => stations
      .where((o) =>
          o.id != s.id && o.name.toUpperCase() == s.name.toUpperCase())
      .toList();
}

class _Header {
  final TransitRoute? route; // null = "Other"
  final int count;
  _Header(this.route, this.count);
}

// ───────────────────────── Screen ─────────────────────────

class _TrainListScreenState extends State<TrainListScreen> {
  late final TransitRepository _repo =
      widget.repo ?? TransitRepository(TransitApi());
  late final Future<_Data> _future = _load();
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _routeFilter;

  Future<_Data> _load() async =>
      _Data(await _repo.getRoutes(), await _repo.getStations());

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openStation(_Data data, Station s) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StationDetailScreen(
          station: s,
          route: data.routesById[s.routeId],
          interchanges: data.interchangesOf(s),
          routesById: data.routesById,
          repo: _repo,
          onOpenStation: (o) => _openStation(data, o),
        ),
      ),
    );
  }

  List<Object> _buildItems(_Data d) {
    final q = _query.trim().toUpperCase();
    bool match(Station s) =>
        q.isEmpty ||
        s.name.toUpperCase().contains(q) ||
        s.id.toUpperCase().contains(q);

    final items = <Object>[];
    for (final r in d.routes) {
      if (_routeFilter != null && _routeFilter != r.id) continue;
      final list =
          d.stations.where((s) => s.routeId == r.id && match(s)).toList();
      if (list.isEmpty) continue;
      items.add(_Header(r, list.length));
      items.addAll(list);
    }
    if (_routeFilter == null) {
      final known = d.routes.map((r) => r.id).toSet();
      final orphans = d.stations
          .where((s) => !known.contains(s.routeId) && match(s))
          .toList();
      if (orphans.isNotEmpty) {
        items.add(_Header(null, orphans.length));
        items.addAll(orphans);
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Data>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: const Text('Train list')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Train list')),
            body: Center(child: Text('Failed to load: ${snap.error}')),
          );
        }
        final data = snap.data!;
        final items = _buildItems(data);

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              const SliverAppBar.large(title: Text('Train list')),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: LiveClock(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SearchBar(
                    controller: _searchCtrl,
                    hintText: 'Search stations',
                    elevation: const WidgetStatePropertyAll(0),
                    leading: const Icon(Icons.search),
                    trailing: [
                      if (_query.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                    ],
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('All'),
                          selected: _routeFilter == null,
                          onSelected: (_) =>
                              setState(() => _routeFilter = null),
                        ),
                      ),
                      for (final r in data.routes)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: CircleAvatar(
                              radius: 6,
                              backgroundColor: Color(r.colorValue),
                            ),
                            label: Text(r.shortName),
                            selected: _routeFilter == r.id,
                            onSelected: (_) => setState(() =>
                                _routeFilter =
                                    _routeFilter == r.id ? null : r.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (items.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(),
                )
              else
                SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    if (item is _Header) return _LineHeader(header: item);
                    final s = item as Station;
                    return _StationCard(
                      station: s,
                      route: data.routesById[s.routeId],
                      onTap: () => _openStation(data, s),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 56, color: cs.outline),
          const SizedBox(height: 12),
          Text('No stations found',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Try a different name or line.',
              style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _LineHeader extends StatelessWidget {
  const _LineHeader({required this.header});
  final _Header header;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = header.route;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          if (r != null)
            _LineBadge(route: r)
          else
            const CircleAvatar(child: Icon(Icons.help_outline)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r?.longName ?? 'Other',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        )),
                Text(r?.description ?? 'No matching line',
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
          Text('${header.count}',
              style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _StationCard extends StatelessWidget {
  const _StationCard({
    required this.station,
    required this.route,
    required this.onTap,
  });
  final Station station;
  final TransitRoute? route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = route != null ? Color(route!.colorValue) : cs.outline;
    final onColor =
        route != null ? Color(route!.textColorValue) : cs.onInverseSurface;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 54),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  station.id,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: onColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  station.name.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              if (station.isAccessible)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.accessible,
                      size: 18, color: cs.onSurfaceVariant),
                ),
              Icon(Icons.chevron_right, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineBadge extends StatelessWidget {
  const _LineBadge({required this.route});
  final TransitRoute route;
  static const double radius = 20;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Color(route.colorValue),
      child: Text(
        route.shortName,
        style: TextStyle(
          color: Color(route.textColorValue),
          fontSize: radius * 0.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
