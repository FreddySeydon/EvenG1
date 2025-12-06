import 'package:flutter/material.dart';

import '../../services/world_time_service.dart';

class WorldTimePage extends StatefulWidget {
  const WorldTimePage({super.key});

  @override
  State<WorldTimePage> createState() => _WorldTimePageState();
}

class _WorldTimePageState extends State<WorldTimePage> {
  bool _enabled = false;
  String _label = 'Home';
  int _offset = 0;
  late final TextEditingController _labelCtl;

  @override
  void initState() {
    super.initState();
    _labelCtl = TextEditingController(text: _label);
    _load();
  }

  Future<void> _load() async {
    final svc = WorldTimeService.instance;
    await svc.ensureReady();
    if (!mounted) return;
    setState(() {
      _enabled = svc.enabled;
      _label = svc.label;
      _offset = svc.offsetHours;
      _labelCtl.text = _label;
    });
  }

  Future<void> _saveEnabled(bool value) async {
    await WorldTimeService.instance.setEnabled(value);
    _load();
  }

  Future<void> _saveLabel(String value) async {
    await WorldTimeService.instance.setLabel(value);
    _load();
  }

  Future<void> _saveOffset(int value) async {
    await WorldTimeService.instance.setOffsetHours(value);
    _load();
  }

  @override
  void dispose() {
    _labelCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = WorldTimeService.instance;
    final preview = _enabled ? svc.formattedTime(includeDay: true) : 'Disabled';

    return Scaffold(
      appBar: AppBar(
        title: const Text('World time'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Show world time in note title'),
            subtitle: const Text('Pins the world clock into the dashboard note title; note title moves into the body.'),
            value: _enabled,
            onChanged: _saveEnabled,
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Label (e.g., Home, NYC)',
              border: OutlineInputBorder(),
            ),
            controller: _labelCtl,
            onSubmitted: _saveLabel,
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Offset from UTC (hours)',
              border: OutlineInputBorder(),
            ),
            child: DropdownButton<int>(
              value: _offset,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: List.generate(29, (i) => i - 12).map((val) {
                final sign = val >= 0 ? '+' : '';
                return DropdownMenuItem(
                  value: val,
                  child: Text('UTC $sign$val'),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) _saveOffset(val);
              },
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            title: const Text('Preview'),
            subtitle: Text(preview),
            trailing: const Icon(Icons.visibility),
          ),
          const SizedBox(height: 8),
          const Text(
            'When enabled, the dashboard note title will show the world time (e.g., "NYC 08:15"), and your note title will be prepended to the note body to keep content visible.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
