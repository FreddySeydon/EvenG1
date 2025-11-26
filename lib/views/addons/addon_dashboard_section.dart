import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/addon_controller.dart';
import '../../models/addon.dart';

class AddonDashboardSection extends StatelessWidget {
  const AddonDashboardSection({super.key});

  @override
  Widget build(BuildContext context) {
    final addonController = Get.find<AddonController>();

    return Obx(() {
      final starred = addonController.starredAddons();
      if (starred.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pinned addons',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...starred.map((addon) => _AddonTile(addon: addon)).toList(),
          const SizedBox(height: 12),
        ],
      );
    });
  }
}

class _AddonTile extends StatelessWidget {
  const _AddonTile({required this.addon});

  final AddonDefinition addon;

  @override
  Widget build(BuildContext context) {
    final widgetBuilder = addon.dashboardBuilder;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: widgetBuilder != null
          ? widgetBuilder(context)
          : _FallbackCard(name: addon.manifest.name),
    );
  }
}

class _FallbackCard extends StatelessWidget {
  const _FallbackCard({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            'No dashboard view yet',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
