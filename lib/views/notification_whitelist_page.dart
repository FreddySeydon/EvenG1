// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:demo_ai_even/services/notification_service.dart';
import 'package:flutter/services.dart';

class NotificationWhitelistPage extends StatefulWidget {
  const NotificationWhitelistPage({super.key});

  @override
  _NotificationWhitelistPageState createState() => _NotificationWhitelistPageState();
}

class _NotificationWhitelistPageState extends State<NotificationWhitelistPage> {
  static const MethodChannel _methodChannel = MethodChannel('method.bluetooth');
  
  List<AppInfo> _allApps = [];
  Set<String> _whitelistedPackages = {};
  bool _showAllApps = false; // Toggle between all apps and whitelisted only
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadWhitelist();
    _loadInstalledApps();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  Future<void> _loadWhitelist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final whitelistString = prefs.getString('notification_whitelist') ?? '';
      
      setState(() {
        if (whitelistString.isEmpty) {
          _whitelistedPackages = {};
        } else {
          _whitelistedPackages = whitelistString.split(',').toSet();
        }
      });
      
      // Update notification service
      NotificationService.instance.setWhitelistedApps(_whitelistedPackages);
    } catch (e) {
      print('Error loading whitelist: $e');
    }
  }

  Future<void> _saveWhitelist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_whitelistedPackages.isEmpty) {
        await prefs.remove('notification_whitelist');
      } else {
        await prefs.setString('notification_whitelist', _whitelistedPackages.join(','));
      }
      
      // Update notification service
      NotificationService.instance.setWhitelistedApps(_whitelistedPackages);
    } catch (e) {
      print('Error saving whitelist: $e');
    }
  }

  Future<void> _loadInstalledApps() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final List<dynamic> apps = await _methodChannel.invokeMethod('getInstalledApps') ?? [];
      
      setState(() {
        _allApps = apps.map((app) => AppInfo(
          packageName: app['packageName'] as String,
          appName: app['appName'] as String,
        )).toList();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading installed apps: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading apps: $e')),
        );
      }
    }
  }

  void _toggleAppWhitelist(String packageName) {
    setState(() {
      if (_whitelistedPackages.contains(packageName)) {
        _whitelistedPackages.remove(packageName);
      } else {
        _whitelistedPackages.add(packageName);
      }
    });
    _saveWhitelist();
  }

  void _clearWhitelist() {
    setState(() {
      _whitelistedPackages.clear();
    });
    _saveWhitelist();
  }

  List<AppInfo> get _filteredApps {
    var apps = _showAllApps ? _allApps : _allApps.where((app) => _whitelistedPackages.contains(app.packageName)).toList();
    
    if (_searchQuery.isNotEmpty) {
      apps = apps.where((app) => 
        app.appName.toLowerCase().contains(_searchQuery) ||
        app.packageName.toLowerCase().contains(_searchQuery)
      ).toList();
    }
    
    return apps;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Whitelist'),
        actions: [
          // Toggle between all apps and whitelisted only
          IconButton(
            icon: Icon(_showAllApps ? Icons.checklist : Icons.list),
            tooltip: _showAllApps ? 'Show Whitelisted Only' : 'Show All Apps',
            onPressed: () {
              setState(() {
                _showAllApps = !_showAllApps;
              });
            },
          ),
          // Clear whitelist
          if (_whitelistedPackages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear Whitelist',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear Whitelist'),
                    content: const Text('Remove all apps from whitelist? (This will allow all notifications)'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _clearWhitelist();
                        },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search apps...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          // Info banner
          Container(
            width: double.infinity,
            color: Colors.blue.withOpacity(0.1),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _whitelistedPackages.isEmpty
                        ? 'All notifications will be forwarded'
                        : '${_whitelistedPackages.length} app(s) whitelisted',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          // App list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredApps.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.apps,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No apps found matching "$_searchQuery"'
                                  : _showAllApps
                                      ? 'No apps found'
                                      : 'No apps in whitelist',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredApps.length,
                        itemBuilder: (context, index) {
                          final app = _filteredApps[index];
                          final isWhitelisted = _whitelistedPackages.contains(app.packageName);
                          
                          return ListTile(
                            title: Text(app.appName),
                            subtitle: Text(
                              app.packageName,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            trailing: Switch(
                              value: isWhitelisted,
                              onChanged: (value) {
                                _toggleAppWhitelist(app.packageName);
                              },
                            ),
                            onTap: () {
                              _toggleAppWhitelist(app.packageName);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class AppInfo {
  final String packageName;
  final String appName;

  AppInfo({
    required this.packageName,
    required this.appName,
  });
}

