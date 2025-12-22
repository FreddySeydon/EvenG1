import '../models/addon.dart';
import '../views/addons/bahn_addon_page.dart';
import '../views/addons/bahn_dashboard_tile.dart';

final bahnAddon = AddonDefinition(
  manifest: AddonManifest(
    id: 'bahn_timetable',
    name: 'DB Timetable',
    description: 'Search Deutsche Bahn train connections and get real-time updates on your G1 glasses dashboard. '
        'Smart refresh automatically updates delays and platform changes.',
    version: '1.0.0',
    author: 'EvenG1',
    tags: ['transport', 'timetable', 'travel', 'trains', 'realtime'],
    category: 'Mobility',
  ),
  pageBuilder: (context) => BahnAddonPage(),
  dashboardBuilder: (context) => BahnDashboardTile(),
);
