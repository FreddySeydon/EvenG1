import 'package:flutter/material.dart';

/// Metadata describing an addon that can be listed in the store and installed.
class AddonManifest {
  final String id;
  final String name;
  final String description;
  final String version;
  final String author;
  final List<String> tags;
  final String? category;
  final String? docsUrl;

  const AddonManifest({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.author,
    this.tags = const [],
    this.category,
    this.docsUrl,
  });
}

/// Factory type that builds the main screen for an addon.
typedef AddonPageBuilder = Widget Function(BuildContext context);

/// Optional builder for a dashboard-friendly widget. When provided and the addon
/// is starred, this widget is rendered in the home dashboard list.
typedef AddonDashboardBuilder = Widget Function(BuildContext context);

/// Lifecycle hook definitions for addons.
typedef AddonLifecycleHook = Future<void> Function();

/// Definition used by the registry to expose an addon implementation.
class AddonDefinition {
  final AddonManifest manifest;
  final AddonPageBuilder pageBuilder;
  final AddonDashboardBuilder? dashboardBuilder;
  final AddonLifecycleHook? onInstall;
  final AddonLifecycleHook? onUninstall;

  const AddonDefinition({
    required this.manifest,
    required this.pageBuilder,
    this.dashboardBuilder,
    this.onInstall,
    this.onUninstall,
  });
}
