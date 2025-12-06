import '../addons/time_notes_addon.dart';
import '../addons/world_time_addon.dart';
import '../models/addon.dart';

/// Central registry for all addons the app knows how to load. Developers can
/// add new addons by exporting a new [AddonDefinition] here.
class AddonRegistry {
  static List<AddonDefinition> getAvailableAddons() {
    return [
      timeNotesAddon,
      worldTimeAddon,
    ];
  }
}
