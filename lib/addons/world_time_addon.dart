import '../models/addon.dart';
import '../views/addons/world_time_page.dart';
import '../views/addons/world_time_dashboard_tile.dart';

final AddonDefinition worldTimeAddon = AddonDefinition(
  manifest: AddonManifest(
    id: 'world_time',
    name: 'World Time',
    description: 'Show a secondary timezone on the dashboard by pinning it into the note title.',
    version: '0.1.0',
    author: 'Addon System',
    tags: ['clock', 'timezone', 'dashboard'],
    category: 'Utilities',
  ),
  pageBuilder: (context) => const WorldTimePage(),
  dashboardBuilder: (context) => const WorldTimeDashboardTile(),
);
