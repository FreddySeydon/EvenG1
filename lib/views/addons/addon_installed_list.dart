import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/addon_controller.dart';
import '../../models/addon.dart';

class AddonInstalledList extends StatelessWidget {
  const AddonInstalledList({super.key});

  @override
  Widget build(BuildContext context) {
    final addonController = Get.find<AddonController>();

    return Obx(() {
      final installed = addonController.installedAddons();
      if (installed.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Installed addons',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...installed.map((addon) => _AddonInstalledCard(addon: addon)),
          const SizedBox(height: 12),
        ],
      );
    });
  }
}

class _AddonInstalledCard extends StatelessWidget {
  const _AddonInstalledCard({required this.addon});

  final AddonDefinition addon;

  @override
  Widget build(BuildContext context) {
    final addonController = Get.find<AddonController>();
    final isStarred = addonController.isStarred(addon.manifest.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ListTile(
        title: Text(
          addon.manifest.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          addon.manifest.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                isStarred ? Icons.star : Icons.star_border,
                color: isStarred ? Colors.amber : Colors.grey,
              ),
              tooltip: isStarred ? 'Unpin' : 'Pin to dashboard',
              onPressed: () => addonController.toggleStar(addon.manifest.id),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => addon.pageBuilder(context),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ],
        ),
      ),
    );
  }
}
