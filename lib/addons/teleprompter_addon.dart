import '../models/addon.dart';
import '../views/addons/teleprompter_addon_page.dart';

final AddonDefinition teleprompterAddon = AddonDefinition(
  manifest: AddonManifest(
    id: 'teleprompter',
    name: 'Teleprompter',
    description: 'Send slide-based teleprompter text to the glasses.',
    version: '0.1.0',
    author: 'Community Port',
    tags: ['teleprompter', 'slides', 'presentations'],
    category: 'Productivity',
  ),
  pageBuilder: (context) => const TeleprompterAddonPage(),
);
