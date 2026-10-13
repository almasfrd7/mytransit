import 'route.dart';

enum ServiceLevel { normal, offPeak, closed, advisory }

enum AdvisorySeverity { info, warning, disruption }

/// A published service notice (from assets/advisories.json for now).
class Advisory {
  const Advisory({
    required this.id,
    required this.title,
    required this.message,
    this.routeId,
    this.severity = AdvisorySeverity.info,
    this.from,
    this.until,
  });

  final String id;
  final String title;
  final String message;

  /// null = applies to the whole network.
  final String? routeId;
  final AdvisorySeverity severity;
  final DateTime? from;
  final DateTime? until;

  factory Advisory.fromJson(Map<String, dynamic> j) {
    AdvisorySeverity sev(String? s) => switch (s) {
      'disruption' => AdvisorySeverity.disruption,
      'warning' => AdvisorySeverity.warning,
      _ => AdvisorySeverity.info,
    };
    final route = j['route_id'] as String?;
    return Advisory(
      id: '${j['id'] ?? j['title']}',
      title: '${j['title'] ?? 'Service notice'}',
      message: '${j['message'] ?? ''}',
      routeId: (route == null || route.isEmpty || route == '*') ? null : route,
      severity: sev(j['severity'] as String?),
      from: DateTime.tryParse('${j['from'] ?? ''}'),
      until: DateTime.tryParse('${j['until'] ?? ''}'),
    );
  }

  bool activeAt(DateTime now) =>
      (from == null || !now.isBefore(from!)) &&
          (until == null || now.isBefore(until!));

  bool appliesTo(String id) => routeId == null || routeId == id;
}

class ServiceStatus {
  const ServiceStatus({
    required this.route,
    required this.level,
    required this.headline,
    this.detail,
    this.headwayMin,
    this.headwayMax,
    this.firstTrain,
    this.lastTrain,
    this.advisories = const [],
  });

  final TransitRoute route;
  final ServiceLevel level;
  final String headline;
  final String? detail;

  /// Current gap between trains, in minutes (frequency-based lines only).
  final int? headwayMin;
  final int? headwayMax;
  final Duration? firstTrain;
  final Duration? lastTrain;
  final List<Advisory> advisories;

  bool get hasDisruption =>
      advisories.any((a) => a.severity == AdvisorySeverity.disruption);

  String? get headwayLabel {
    final lo = headwayMin;
    final hi = headwayMax;
    if (lo == null || hi == null) return null;
    return lo == hi ? 'Every $lo min' : 'Every $lo–$hi min';
  }

  /// "6:05 AM"; wraps past midnight.
  static String clock(Duration d) {
    final total = d.inMinutes % (24 * 60);
    final h24 = total ~/ 60;
    final m = total % 60;
    final h = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h:${m.toString().padLeft(2, '0')} ${h24 < 12 ? 'AM' : 'PM'}';
  }
}

/// One-line roll-up of every line, used by Home and the status screen.
class NetworkSummary {
  NetworkSummary(List<ServiceStatus> list)
      : total = list.length,
        active = list.where((s) => s.level != ServiceLevel.closed).length,
        advisories =
            list.where((s) => s.level == ServiceLevel.advisory).length;

  final int total;
  final int active;
  final int advisories;

  bool get hasAdvisory => advisories > 0;

  String get headline {
    if (advisories == 1) return '1 line has a service advisory';
    if (advisories > 1) return '$advisories lines have service advisories';
    if (active == 0) return 'No lines in service right now';
    return 'Service running normally';
  }

  String get subline => '$active of $total lines in service now';
}