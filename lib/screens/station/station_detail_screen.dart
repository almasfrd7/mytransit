import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/arrival.dart';
import '../../models/route.dart';
import '../../models/service_status.dart';
import '../../models/station.dart';
import '../../repositories/transit_repositories.dart';
import '../../services/favourites_store.dart';
import '../../widgets/live_clock.dart';
import '../../widgets/ui.dart';

/// One station: details, line status, interchanges and the next trains.
class StationDetailScreen extends StatefulWidget {
  const StationDetailScreen({
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
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  late Future<List<Arrival>> _arrivals = _fetch();
  late Future<ServiceStatus>? _status = _fetchStatus();
  Timer? _timer; // refetches arrivals + status
  Timer? _tick; // refreshes the "x min" labels every second

  Future<List<Arrival>> _fetch() => widget.repo.getNextArrivals(
    widget.station.id,
    routeId: widget.station.routeId,
    limit: 6,
  );

  Future<ServiceStatus>? _fetchStatus() => widget.route == null
      ? null
      : widget.repo.getServiceStatus(widget.route!);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {
          _arrivals = _fetch();
          _status = _fetchStatus();
        });
      }
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tick?.cancel();
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
    final onColor = routeOnColor(r, cs.onPrimary);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 200,
            backgroundColor: color,
            foregroundColor: onColor,
            surfaceTintColor: Colors.transparent,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            actions: [
              ListenableBuilder(
                listenable: FavouritesStore.instance,
                builder: (context, _) {
                  final fav = FavouritesStore.instance.contains(s);
                  return IconButton(
                    tooltip: fav ? 'Remove favourite' : 'Add favourite',
                    icon: Icon(fav ? Icons.favorite : Icons.favorite_border),
                    onPressed: () => FavouritesStore.instance.toggle(s),
                  );
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(
                  start: 56, bottom: 16, end: 16),
              title: Text(
                s.name.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: onColor, fontWeight: FontWeight.w800),
              ),
              background: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(28)),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color, color.withValues(alpha: 0.72)],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 64),
                alignment: Alignment.bottomLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r?.longName ?? s.category} · ${s.id}',
                      style: TextStyle(
                          color: onColor.withValues(alpha: 0.9),
                          fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    _headerStatus(onColor),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(
              children: [
                const LiveClock(),
                _advisories(),
                const SizedBox(height: 16),
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
                  const SectionHeader('Interchange'),
                  const SizedBox(height: 10),
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
                const SectionHeader('Next trains'),
                const SizedBox(height: 2),
                Text('Scheduled times, not live',
                    style:
                    TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(height: 12),
                _arrivalsView(cs, color, onColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerStatus(Color onColor) {
    return FutureBuilder<ServiceStatus>(
      future: _status,
      builder: (context, snap) {
        final st = snap.data;
        if (st == null) return const SizedBox(height: 26);
        final label = statusLabel(st) +
            (st.headwayLabel != null ? ' · ${st.headwayLabel}' : '');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: onColor.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(st.level.icon, size: 14, color: onColor),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: onColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        );
      },
    );
  }

  Widget _advisories() {
    return FutureBuilder<ServiceStatus>(
      future: _status,
      builder: (context, snap) {
        final st = snap.data;
        if (st == null || st.advisories.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            const SizedBox(height: 16),
            for (final a in st.advisories)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AdvisoryCard(advisory: a),
              ),
          ],
        );
      },
    );
  }

  Widget _arrivalsView(ColorScheme cs, Color color, Color onColor) {
    return FutureBuilder<List<Arrival>>(
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
          return const AppCard(
            child: Text('No more scheduled trips today.'),
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
              const SizedBox(height: 10),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < rest.length; i++) ...[
                      if (i > 0) const Divider(indent: 16),
                      ListTile(
                        leading: Icon(Icons.train_outlined, color: cs.primary),
                        title: Text(rest[i].headsign,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(rest[i].label),
                        trailing: Text(
                          _minsLabel(rest[i]),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
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
    );
  }
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.78)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
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
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2)),
                const SizedBox(height: 6),
                Text(arrival.headsign,
                    style: TextStyle(
                        color: onColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
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
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}