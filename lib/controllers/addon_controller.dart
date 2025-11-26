import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/addon.dart';
import '../services/addon_registry.dart';

class AddonController extends GetxController {
  final availableAddons = <AddonDefinition>[].obs;
  final installedAddonIds = <String>{}.obs;
  final starredAddonIds = <String>{}.obs;

  static const _installedKey = 'addon_installed_ids';
  static const _starredKey = 'addon_starred_ids';

  SharedPreferences? _prefs;

  @override
  void onInit() {
    super.onInit();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _prefs = await SharedPreferences.getInstance();
    _loadPersistedState();
    refreshAvailableAddons();
  }

  void refreshAvailableAddons() {
    final registry = AddonRegistry.getAvailableAddons();
    availableAddons.assignAll(registry);
  }

  void _loadPersistedState() {
    final installed = _prefs?.getStringList(_installedKey) ?? [];
    final starred = _prefs?.getStringList(_starredKey) ?? [];

    installedAddonIds.value = installed.toSet();
    starredAddonIds.value = starred.toSet();
  }

  Future<void> _persistState() async {
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
    }
    await _prefs?.setStringList(_installedKey, installedAddonIds.toList());
    await _prefs?.setStringList(_starredKey, starredAddonIds.toList());
  }

  AddonDefinition? definitionFor(String addonId) {
    try {
      return availableAddons.firstWhere((addon) => addon.manifest.id == addonId);
    } catch (_) {
      return null;
    }
  }

  bool isInstalled(String addonId) => installedAddonIds.contains(addonId);

  bool isStarred(String addonId) => starredAddonIds.contains(addonId);

  Future<void> installAddon(String addonId) async {
    if (isInstalled(addonId)) return;
    installedAddonIds.add(addonId);

    final definition = definitionFor(addonId);
    if (definition?.onInstall != null) {
      await definition!.onInstall!.call();
    }

    await _persistState();
  }

  Future<void> uninstallAddon(String addonId) async {
    if (!isInstalled(addonId)) return;

    installedAddonIds.remove(addonId);
    starredAddonIds.remove(addonId);

    final definition = definitionFor(addonId);
    if (definition?.onUninstall != null) {
      await definition!.onUninstall!.call();
    }

    await _persistState();
  }

  Future<void> toggleStar(String addonId) async {
    if (!isInstalled(addonId)) return;

    if (isStarred(addonId)) {
      starredAddonIds.remove(addonId);
    } else {
      starredAddonIds.add(addonId);
    }
    await _persistState();
  }

  List<AddonDefinition> installedAddons() => availableAddons
      .where((addon) => installedAddonIds.contains(addon.manifest.id))
      .toList();

  List<AddonDefinition> starredAddons() => availableAddons
      .where((addon) =>
          installedAddonIds.contains(addon.manifest.id) &&
          starredAddonIds.contains(addon.manifest.id))
      .toList();
}
