import 'package:flutter/material.dart';

import '../models/route.dart';
import '../models/station.dart';
import 'ui.dart';

/// Reusable station row: coloured id badge, name, optional subtitle/trailing.
class StationCard extends StatelessWidget {
  const StationCard({
    super.key,
    required this.station,
    required this.route,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final Station station;
  final TransitRoute? route;
  final VoidCallback onTap;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = route != null ? Color(route!.colorValue) : cs.outline;
    final onColor = routeOnColor(route, cs.onInverseSurface);

    return AppCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 54),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              station.id,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: onColor,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  station.name.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                    TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (station.isAccessible)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child:
              Icon(Icons.accessible, size: 18, color: cs.onSurfaceVariant),
            ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: cs.outline),
        ],
      ),
    );
  }
}