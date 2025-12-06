import 'package:flutter/material.dart';

import '../../services/world_time_service.dart';

class WorldTimeDashboardTile extends StatefulWidget {
  const WorldTimeDashboardTile({super.key});

  @override
  State<WorldTimeDashboardTile> createState() => _WorldTimeDashboardTileState();
}

class _WorldTimeDashboardTileState extends State<WorldTimeDashboardTile> {
  String _label = '';
  int _offset = 0;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = WorldTimeService.instance;
    await svc.ensureReady();
    if (!mounted) return;
    setState(() {
      _label = svc.label;
      _offset = svc.offsetHours;
      _enabled = svc.enabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    final svc = WorldTimeService.instance;
    final nowText = _enabled ? svc.formattedTime(includeDay: true) : 'Disabled';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.public, size: 18),
              const SizedBox(width: 8),
              Text(
                'World time',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Switch(
                value: _enabled,
                onChanged: (val) async {
                  await svc.setEnabled(val);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            nowText,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            'Label: $_label • Offset: ${_offset >= 0 ? '+' : ''}$_offset h',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
