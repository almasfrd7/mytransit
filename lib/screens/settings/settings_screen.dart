import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader('Appearance'),
          const SizedBox(height: 10),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Theme',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  'Match your phone, or force light / dark.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeModeNotifier,
                  builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('System'),
                        icon: Icon(Icons.brightness_auto_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_outlined, size: 18),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) =>
                    themeModeNotifier.value = s.first,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader('About'),
          const SizedBox(height: 10),
          const AppCard(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.train_outlined,
                  title: 'MyTransit',
                  subtitle: 'Version 1.0.0',
                ),
                Divider(indent: 16, endIndent: 16),
                _InfoRow(
                  icon: Icons.dataset_outlined,
                  title: 'Data source',
                  subtitle: 'Bundled GTFS feed · Klang Valley + KTMB rail',
                ),
                Divider(indent: 16, endIndent: 16),
                _InfoRow(
                  icon: Icons.schedule_outlined,
                  title: 'Times are scheduled',
                  subtitle: 'Live positions come from KTMB GTFS-Realtime',
                ),
                Divider(indent: 16, endIndent: 16),
                _InfoRow(
                  icon: Icons.campaign_outlined,
                  title: 'Service advisories',
                  subtitle: 'Published notices are read from advisories.json',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: cs.primary, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
    );
  }
}