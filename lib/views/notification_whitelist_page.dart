// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:demo_ai_even/services/notification_service.dart';

class NotificationWhitelistPage extends StatefulWidget {
  const NotificationWhitelistPage({super.key});

  @override
  _NotificationWhitelistPageState createState() => _NotificationWhitelistPageState();
}

class _NotificationWhitelistPageState extends State<NotificationWhitelistPage> {
  final TextEditingController _whitelistSearchCtl = TextEditingController();
  final TextEditingController _allAppsSearchCtl = TextEditingController();

  List<AppInfo> _allApps = [];
  Set<String> _whitelistedPackages = {};
  bool _isLoading = true;
  bool _notificationsEnabled = false;

  @override
  void initState() {
    super.initState();
    _whitelistSearchCtl.addListener(() => setState(() {}));
    _allAppsSearchCtl.addListener(() => setState(() {}));
    _loadState();
  }

  @override
  void dispose() {
    _whitelistSearchCtl.dispose();
    _allAppsSearchCtl.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final enabled = await NotificationService.instance.checkNotificationPermission();
      final apps = await NotificationService.instance.getInstalledApps();
      final whitelist = NotificationService.instance.whitelistedApps;
      if (!mounted) return;
      setState(() {
        _notificationsEnabled = enabled;
        _allApps = apps;
        _whitelistedPackages = whitelist;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading apps: $e')),
      );
    }
  }

  Future<void> _toggleEnabled(bool value) async {
    if (value) {
      final ok = await NotificationService.instance.requestNotificationPermission();
      if (!mounted) return;
      if (ok) {
        await NotificationService.instance.startListening();
        if (mounted) setState(() => _notificationsEnabled = true);
      }
    } else {
      NotificationService.instance.stopListening();
      if (mounted) setState(() => _notificationsEnabled = false);
    }
  }

  void _toggleApp(String packageName) {
    setState(() {
      if (_whitelistedPackages.contains(packageName)) {
        _whitelistedPackages.remove(packageName);
      } else {
        _whitelistedPackages.add(packageName);
      }
    });
    NotificationService.instance.setWhitelistedApps(_whitelistedPackages);
  }

  List<AppInfo> get _whitelistFiltered {
    final query = _whitelistSearchCtl.text.toLowerCase();
    final list = _allApps.where((a) => _whitelistedPackages.contains(a.packageName)).toList();
    if (query.isEmpty) return list;
    return list
        .where((a) =>
            a.appName.toLowerCase().contains(query) ||
            a.packageName.toLowerCase().contains(query))
        .toList();
  }

  List<AppInfo> get _allFiltered {
    final query = _allAppsSearchCtl.text.toLowerCase();

    const pinned = [
      'com.whatsapp',
      'com.facebook.orca', // Messenger
      'com.instagram.android',
      'com.google.android.gm', // Gmail
      'com.google.android.apps.messaging', // Messages
      'com.google.android.dialer', // Phone
      'com.android.contacts',
      'com.snapchat.android',
      'com.twitter.android', // X
      'com.slack', // Slack
      'com.microsoft.teams',
      'com.discord',
      'com.outlook.Z7', // Outlook variant
      'com.google.android.youtube',
      'com.netflix.mediaclient',
    ];

    List<AppInfo> list = _allApps;
    if (query.isNotEmpty) {
      list = list
          .where((a) =>
              a.appName.toLowerCase().contains(query) ||
              a.packageName.toLowerCase().contains(query))
          .toList();
    }

    // Promote pinned apps to the top (preserve their original order otherwise)
    final pinnedSet = pinned.toSet();
    final pinnedApps = list.where((a) => pinnedSet.contains(a.packageName)).toList();
    final rest = list.where((a) => !pinnedSet.contains(a.packageName)).toList();
    return [...pinnedApps, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notification whitelist'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Whitelist'),
              Tab(text: 'All Apps'),
            ],
          ),
        ),
        body: Column(
          children: [
            SwitchListTile(
              title: const Text('Enable notification forwarding'),
              subtitle: Text(_notificationsEnabled
                  ? 'Notifications will be shown on the glasses'
                  : 'Notifications are disabled'),
              value: _notificationsEnabled,
              onChanged: _toggleEnabled,
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        _buildWhitelistTab(context),
                        _buildAllAppsTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWhitelistTab(BuildContext context) {
    final items = _whitelistFiltered;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _whitelistSearchCtl,
            decoration: InputDecoration(
              hintText: 'Search whitelisted apps',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _whitelistSearchCtl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _whitelistSearchCtl.clear(),
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        Expanded(
          child: _whitelistedPackages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('All notifications are allowed.'),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (innerCtx) => TextButton(
                          onPressed: () => DefaultTabController.of(innerCtx)?.animateTo(1),
                          child: const Text('Browse all apps'),
                        ),
                      ),
                    ],
                  ),
                )
              : items.isEmpty
                  ? const Center(child: Text('No whitelisted apps match your search.'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final app = items[index];
                        return ListTile(
                          title: Text(app.appName),
                          subtitle: Text(app.packageName, style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => _toggleApp(app.packageName),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildAllAppsTab() {
    final items = _allFiltered;
    const pinnedPackages = {
      'com.whatsapp',
      'com.facebook.orca',
      'com.instagram.android',
      'com.google.android.gm',
      'com.google.android.apps.messaging',
      'com.google.android.dialer',
      'com.android.contacts',
      'com.snapchat.android',
      'com.twitter.android',
      'com.slack',
      'com.microsoft.teams',
      'com.discord',
      'org.telegram.messenger',
      'com.outlook.Z7',
      'com.google.android.youtube',
      'com.netflix.mediaclient',
    };
    final pinned = items.where((a) => pinnedPackages.contains(a.packageName)).toList();
    final rest = items.where((a) => !pinnedPackages.contains(a.packageName)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _allAppsSearchCtl,
            decoration: InputDecoration(
              hintText: 'Search apps',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _allAppsSearchCtl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _allAppsSearchCtl.clear(),
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('No apps found.'))
              : ListView(
                  children: [
                    if (pinned.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          'Suggested',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
                        ),
                      ),
                      ...pinned.map(_appTile),
                      const Divider(height: 1),
                    ],
                    ...rest.map(_appTile),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _appTile(AppInfo app) {
    final isWhitelisted = _whitelistedPackages.contains(app.packageName);
    return ListTile(
      title: Text(app.appName),
      subtitle: Text(app.packageName, style: const TextStyle(fontSize: 12)),
      trailing: Switch(
        value: isWhitelisted,
        onChanged: (_) => _toggleApp(app.packageName),
      ),
      onTap: () => _toggleApp(app.packageName),
    );
  }
}
