import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/gtfs_realtime.dart';
import '../../models/service_status.dart';
import '../../repositories/transit_repositories.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';

/// Per-line service status: timetable-derived state, published advisories
/// and KTMB live-feed health.
class ServiceStatusScreen extends StatefulWidget {
  const ServiceStatusScreen({super.key, required this.repo});
  final TransitRepository repo;

  @override
  State<ServiceStatusScreen> createState() => _ServiceStatusScreenState();
}

class _Data {
  _Data(this.statuses, this.advisories, this.at);
  final List<ServiceStatus> statuses;
  final List<Advisory> advisories;
  final DateTime at;
}

class _ServiceStatusScreenState extends State<ServiceStatusScreen> {
  _Data? _data;
  Object? _error;
  Map<String, int> _live = const {};
  StreamSubscription<List<VehiclePosition>>? _sub;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    widget.repo.startLivePolling();
    _sub = widget.repo.livePositionsStream.listen(_onLive);
    final current = widget.repo.livePositions;
    if (current != null) _onLive(current);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    widget.repo.stopLivePolling();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final now = DateTime.now();
      final adv = await widget.repo.getAdvisories(now: now);
      final st = await widget.repo.getServiceStatuses(now: now);
      if (!mounted) return;
      setState(() {
        _data = _Data(st, adv, now);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _onLive(List<VehiclePosition> pos) async {
    final routes = await widget.repo.getRoutes();
    final resolved = await widget.repo
        .resolvePositions(pos, {for (final r in routes) r.id});
    if (!mounted) return;
    final counts = <String, int>{};
    for (final p in resolved) {
      final id = p.routeId;
      if (id != null) counts[id] = (counts[id] ?? 0) + 1;
    }
    setState(() => _live = counts);
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final d = _data;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header(d)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              sliver: SliverList.list(children: _body(d)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(_Data? d) {
    const white = Colors.white;
    final String headline;
    final String sub;
    if (d != null) {
      final s = NetworkSummary(d.statuses);
      headline = s.headline;
      sub = '${s.subline} · updated ${_two(d.at.hour)}:${_two(d.at.minute)}';
    } else {
      headline = _error != null ? 'Status unavailable' : 'Checking service…';
      sub = _error != null ? 'Pull down to retry' : '';
    }

    return GradientHeader(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: white),
              ),
              const SizedBox(width: 4),
              const Text('Service status',
                  style: TextStyle(
                      color: white, fontSize: 20, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 16),
          Text(headline,
              style: const TextStyle(
                  color: white,
                  fontSize: 26,
                  height: 1.15,
                  fontWeight: FontWeight.w800)),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(sub,
                style: TextStyle(
                    color: white.withValues(alpha: 0.8), fontSize: 13.5)),
          ],
        ],
      ),
    );
  }

  List<Widget> _body(_Data? d) {
    if (d == null) {
      return [
        if (_error == null)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load service status: $_error'),
          ),
      ];
    }

    String? routeName(String? id) => id == null
        ? 'All lines'
        : d.statuses
        .where((s) => s.route.id == id)
        .firstOrNull
        ?.route
        .longName;

    return [
      if (d.advisories.isNotEmpty) ...[
        const SectionHeader('Active advisories'),
        const SizedBox(height: 10),
        for (final a in d.advisories)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AdvisoryCard(advisory: a, routeName: routeName(a.routeId)),
          ),
        const SizedBox(height: 14),
      ],
      const SectionHeader('Lines'),
      const SizedBox(height: 10),
      for (final s in d.statuses)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _LineCard(status: s, live: _live[s.route.id]),
        ),
      const SizedBox(height: 8),
      _feedCard(),
      const SizedBox(height: 14),
      Text(
        'Status is derived from published timetables. Service disruptions '
            'appear here when an advisory is published.',
        style: TextStyle(
            fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ];
  }

  Widget _feedCard() {
    final cs = Theme.of(context).colorScheme;
    final last = widget.repo.lastLiveFetchAt;
    final err = widget.repo.liveFetchError;

    final String text;
    final Color color;
    if (last != null) {
      final age = DateTime.now().difference(last).inSeconds;
      final stale = age > 120;
      text = stale
          ? 'Last update ${age}s ago (may be stale)'
          : 'Live · updated ${age}s ago';
      color = stale ? Tone.warn : Tone.ok;
    } else if (err != null) {
      text = 'Unavailable right now';
      color = Tone.bad;
    } else {
      text = 'Connecting…';
      color = Tone.idle;
    }

    return AppCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.sensors, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('KTMB live tracking',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                Text(text,
                    style:
                    TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.status, this.live});
  final ServiceStatus status;
  final int? live;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = status.route;
    final c = statusColor(status);
    final first = status.firstTrain;
    final last = status.lastTrain;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LineBadge(route: r),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  r.longName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(
                label: statusLabel(status),
                color: c,
                icon: status.level.icon,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(status.headline,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14.5)),
          if (status.detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(status.detail!,
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurfaceVariant, height: 1.3)),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (status.headwayLabel != null)
                _Fact(icon: Icons.timer_outlined, text: status.headwayLabel!),
              if (first != null && last != null)
                _Fact(
                  icon: Icons.schedule,
                  text: 'First ${ServiceStatus.clock(first)} · '
                      'Last ${ServiceStatus.clock(last)}',
                ),
              if (live != null && live! > 0)
                _Fact(
                  icon: Icons.sensors,
                  text: '$live live',
                  color: Tone.ok,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? cs.onSurfaceVariant).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  fontSize: 12, color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}