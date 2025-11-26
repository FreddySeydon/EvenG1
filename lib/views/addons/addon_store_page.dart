import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/addon_controller.dart';
import '../../models/addon.dart';

class AddonStorePage extends StatelessWidget {
  const AddonStorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final addonController = Get.find<AddonController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Addon Store'),
      ),
      body: Obx(
        () => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: addonController.availableAddons.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final addon = addonController.availableAddons[index];
            return _AddonCard(addon: addon);
          },
        ),
      ),
    );
  }
}

class _AddonCard extends StatelessWidget {
  const _AddonCard({required this.addon});

  final AddonDefinition addon;

  @override
  Widget build(BuildContext context) {
    final addonController = Get.find<AddonController>();

    return Obx(() {
      final isInstalled =
          addonController.installedAddonIds.contains(addon.manifest.id);
      final isStarred =
          addonController.starredAddonIds.contains(addon.manifest.id);

      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        addon.manifest.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        addon.manifest.description,
                        style:
                            const TextStyle(fontSize: 14, color: Colors.black87),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: -6,
                        children: addon.manifest.tags
                            .map(
                              (tag) => Chip(
                                label: Text(tag),
                                backgroundColor:
                                    Colors.blueGrey.withOpacity(0.1),
                                labelStyle: const TextStyle(fontSize: 12),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isStarred ? Icons.star : Icons.star_border,
                    color: isStarred ? Colors.amber : Colors.grey,
                  ),
                  onPressed: isInstalled
                      ? () => addonController.toggleStar(addon.manifest.id)
                      : null,
                  tooltip: isInstalled
                      ? 'Pin/unpin on dashboard'
                      : 'Install to pin on dashboard',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  onPressed: isInstalled
                      ? () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => addon.pageBuilder(context),
                            ),
                          );
                        }
                      : () => addonController.installAddon(addon.manifest.id),
                  child: Text(isInstalled ? 'Open' : 'Install'),
                ),
                const SizedBox(width: 8),
                if (isInstalled)
                  TextButton(
                    onPressed: () =>
                        addonController.uninstallAddon(addon.manifest.id),
                    child: const Text('Remove'),
                  ),
                const Spacer(),
                Text(
                  'v${addon.manifest.version}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}
