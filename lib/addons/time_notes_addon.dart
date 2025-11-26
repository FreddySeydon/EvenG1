import '../models/addon.dart';
import '../views/addons/time_notes_dashboard_tile.dart';
import '../views/addons/time_notes_page.dart';

final AddonDefinition timeNotesAddon = AddonDefinition(
  manifest: AddonManifest(
    id: 'time_notes',
    name: 'Time-aware Notes',
    description: 'Create time-bound or weekly recurring notes and surface the active ones on your G1 dashboard.',
    version: '0.1.0',
    author: 'Addon System',
    tags: ['notes', 'productivity', 'schedule'],
    category: 'Productivity',
  ),
  pageBuilder: (context) => const TimeNotesPage(),
  dashboardBuilder: (context) => const TimeNotesDashboardTile(),
);
