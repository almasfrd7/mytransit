import 'dart:async';

import 'package:flutter/material.dart';

import 'models/arrival.dart';
import 'models/route.dart';
import 'models/station.dart';
import 'repositories/transit_repositories.dart';
import 'services/transit_api.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _theme(Brightness b) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.indigo,
      brightness: b,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyTransit',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const StationPage(),
    );
  }
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

// ───────────────────────── Home ─────────────────────────

class StationPage extends StatefulWidget {
  const StationPage({super.key});

  @override
  State<StationPage> createState() => _StationPageState();
}

class _StationPageState extends State<StationPage> {
  final _repo = TransitRepository(TransitApi());
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
        builder: (_) => StationDetailPage(
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
            appBar: AppBar(title: const Text('MyTransit')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('MyTransit')),
            body: Center(child: Text('Failed to load: ${snap.error}')),
          );
        }
        final data = snap.data!;
        final items = _buildItems(data);

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              const SliverAppBar.large(title: Text('MyTransit')),
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
  const _LineBadge({required this.route, this.radius = 20});
  final TransitRoute route;
  final double radius;

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

// ───────────────────────── Station detail ─────────────────────────

class StationDetailPage extends StatefulWidget {
  const StationDetailPage({
    super.key,
    required this.station,
    required this.route,
    required this.interchanges,
    required this.routesById,
    required this.repo,
    required this.onOpenStation,
  });

  final Station station;
  final TransitRoute? route;
  final List<Station> interchanges;
  final Map<String, TransitRoute> routesById;
  final TransitRepository repo;
  final void Function(Station) onOpenStation;

  @override
  State<StationDetailPage> createState() => _StationDetailPageState();
}

class _StationDetailPageState extends State<StationDetailPage> {
  late Future<List<Arrival>> _arrivals = _fetch();
  Timer? _timer;

  Future<List<Arrival>> _fetch() =>
      widget.repo.getNextArrivals(widget.station.id, limit: 6);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _arrivals = _fetch());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Duration _nowOffset() {
    final n = DateTime.now();
    return Duration(hours: n.hour, minutes: n.minute, seconds: n.second);
  }

  String _minsLabel(Arrival a) {
    final m = (a.time - _nowOffset()).inMinutes;
    return m <= 0 ? 'Now' : '$m min';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.station;
    final r = widget.route;
    final color = r != null ? Color(r.colorValue) : cs.primary;
    final onColor = r != null ? Color(r.textColorValue) : cs.onPrimary;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 170,
            backgroundColor: color,
            foregroundColor: onColor,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(
                  start: 56, bottom: 16, end: 16),
              title: Text(
                s.name.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: onColor, fontWeight: FontWeight.bold),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color, color.withValues(alpha: 0.75)],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 56),
                alignment: Alignment.bottomLeft,
                child: Text(
                  '${r?.longName ?? s.category} · ${s.id}',
                  style: TextStyle(
                      color: onColor.withValues(alpha: 0.9), fontSize: 14),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (s.isAccessible)
                      const Chip(
                        avatar: Icon(Icons.accessible, size: 18),
                        label: Text('Accessible'),
                      ),
                    Chip(
                      avatar: const Icon(Icons.place_outlined, size: 18),
                      label: Text('${s.lat.toStringAsFixed(4)}, '
                          '${s.lng.toStringAsFixed(4)}'),
                    ),
                  ],
                ),
                if (widget.interchanges.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _SectionTitle('Interchange'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final o in widget.interchanges)
                        ActionChip(
                          avatar: widget.routesById[o.routeId] != null
                              ? CircleAvatar(
                            backgroundColor: Color(
                                widget.routesById[o.routeId]!.colorValue),
                          )
                              : null,
                          label: Text(
                              '${widget.routesById[o.routeId]?.longName ?? o.routeId} · ${o.id}'),
                          onPressed: () => widget.onOpenStation(o),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                _SectionTitle('Next trains'),
                const SizedBox(height: 2),
                Text('Scheduled times, not live',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(height: 12),
                FutureBuilder<List<Arrival>>(
                  future: _arrivals,
                  builder: (context, snap) {
                    if (snap.hasError && !snap.hasData) {
                      return Text('Could not load arrivals: ${snap.error}');
                    }
                    if (!snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final list = snap.data!;
                    if (list.isEmpty) {
                      return Card(
                        elevation: 0,
                        color: cs.surfaceContainerLow,
                        child: const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No more scheduled trips today.'),
                        ),
                      );
                    }
                    final next = list.first;
                    final rest = list.skip(1).toList();
                    return Column(
                      children: [
                        _NextTrainCard(
                          arrival: next,
                          minutes: _minsLabel(next),
                          color: color,
                          onColor: onColor,
                        ),
                        if (rest.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Card(
                            elevation: 0,
                            margin: EdgeInsets.zero,
                            color: cs.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            child: Column(
                              children: [
                                for (var i = 0; i < rest.length; i++) ...[
                                  if (i > 0)
                                    const Divider(height: 1, indent: 16),
                                  ListTile(
                                    leading: const Icon(Icons.train_outlined),
                                    title: Text(rest[i].headsign),
                                    subtitle: Text(rest[i].label),
                                    trailing: Text(
                                      _minsLabel(rest[i]),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.w600),
  );
}

class _NextTrainCard extends StatelessWidget {
  const _NextTrainCard({
    required this.arrival,
    required this.minutes,
    required this.color,
    required this.onColor,
  });
  final Arrival arrival;
  final String minutes;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NEXT TRAIN',
                    style: TextStyle(
                        color: onColor.withValues(alpha: 0.8),
                        fontSize: 12,
                        letterSpacing: 1.2)),
                const SizedBox(height: 6),
                Text(arrival.headsign,
                    style: TextStyle(
                        color: onColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Scheduled ${arrival.label}',
                    style: TextStyle(color: onColor.withValues(alpha: 0.85))),
              ],
            ),
          ),
          Text(
            minutes,
            style: TextStyle(
              color: onColor,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}