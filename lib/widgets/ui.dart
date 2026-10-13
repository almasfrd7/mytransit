import 'package:flutter/material.dart';

import '../models/route.dart';
import '../models/service_status.dart';
import '../theme.dart';

/// Readable text colour on a line's colour (the feed says white on yellow).
Color routeOnColor(TransitRoute? r, Color fallback) {
  if (r == null) return fallback;
  final c = Color(r.colorValue);
  return ThemeData.estimateBrightnessForColor(c) == Brightness.dark
      ? Colors.white
      : Colors.black87;
}

Color severityColor(AdvisorySeverity s) => switch (s) {
  AdvisorySeverity.info => Tone.info,
  AdvisorySeverity.warning => Tone.warn,
  AdvisorySeverity.disruption => Tone.bad,
};

extension ServiceLevelUi on ServiceLevel {
  Color get color => switch (this) {
    ServiceLevel.normal => Tone.ok,
    ServiceLevel.offPeak => Tone.info,
    ServiceLevel.closed => Tone.idle,
    ServiceLevel.advisory => Tone.warn,
  };

  String get label => switch (this) {
    ServiceLevel.normal => 'Normal',
    ServiceLevel.offPeak => 'Off-peak',
    ServiceLevel.closed => 'Not in service',
    ServiceLevel.advisory => 'Advisory',
  };

  IconData get icon => switch (this) {
    ServiceLevel.normal => Icons.check_circle_rounded,
    ServiceLevel.offPeak => Icons.timelapse_rounded,
    ServiceLevel.closed => Icons.bedtime_rounded,
    ServiceLevel.advisory => Icons.warning_amber_rounded,
  };
}

Color statusColor(ServiceStatus s) =>
    (s.level == ServiceLevel.advisory && s.hasDisruption)
        ? Tone.bad
        : s.level.color;

String statusLabel(ServiceStatus s) =>
    (s.level == ServiceLevel.advisory && s.hasDisruption)
        ? 'Disruption'
        : s.level.label;

/// Rounded, softly bordered card used everywhere.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Brand.isDark(context);
    final inner = Padding(padding: padding, child: child);
    return Material(
      color: color ?? Brand.card(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: dark ? 0.35 : 0.6),
        ),
      ),
      child: onTap == null ? inner : InkWell(onTap: onTap, child: inner),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800, fontSize: 17),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Coloured short-name pill for a line, e.g. "KJL".
class LineBadge extends StatelessWidget {
  const LineBadge({super.key, required this.route});
  final TransitRoute route;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 44),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Color(route.colorValue),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        route.shortName,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: routeOnColor(route, Colors.white),
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.circle, size: icon == null ? 8 : 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Gradient banner that sits behind a screen's title area.
class GradientHeader extends StatelessWidget {
  const GradientHeader({
    super.key,
    required this.child,
    this.colors,
    this.bottomRadius = 32,
  });

  final Widget child;
  final List<Color>? colors;
  final double bottomRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.paddingOf(context).top + 12, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors ?? Brand.heroColors(context),
        ),
        borderRadius:
        BorderRadius.vertical(bottom: Radius.circular(bottomRadius)),
      ),
      child: child,
    );
  }
}

class AdvisoryCard extends StatelessWidget {
  const AdvisoryCard({super.key, required this.advisory, this.routeName});
  final Advisory advisory;
  final String? routeName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = severityColor(advisory.severity);
    final icon = switch (advisory.severity) {
      AdvisorySeverity.info => Icons.info_outline_rounded,
      AdvisorySeverity.warning => Icons.warning_amber_rounded,
      AdvisorySeverity.disruption => Icons.report_problem_rounded,
    };
    return AppCard(
      color: Color.alphaBlend(c.withValues(alpha: 0.10), Brand.card(context)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(advisory.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
                if (routeName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(routeName!,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ),
                if (advisory.message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(advisory.message,
                        style: const TextStyle(fontSize: 13, height: 1.35)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}