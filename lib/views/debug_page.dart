import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/services/calendar_service.dart';
import 'package:flutter/material.dart';

class DebugPage extends StatefulWidget {
  const DebugPage({super.key});

  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  final _calendarTitleController = TextEditingController();
  final _calendarTimeController = TextEditingController();
  final _calendarLocationController = TextEditingController();

  @override
  void dispose() {
    _calendarTitleController.dispose();
    _calendarTimeController.dispose();
    _calendarLocationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug Tools')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _calendarDebugCard(context),
        ],
      ),
    );
  }

  Widget _calendarDebugCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Calendar pane debug',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _calendarTitleController,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          TextField(
            controller: _calendarTimeController,
            decoration: const InputDecoration(labelText: 'Time (e.g., 11:33)'),
          ),
          TextField(
            controller: _calendarLocationController,
            decoration: const InputDecoration(labelText: 'Location'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final title = _calendarTitleController.text.trim();
                final time = _calendarTimeController.text.trim();
                final location = _calendarLocationController.text.trim();

                if (!BleManager.get().isConnected) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Connect glasses first.')),
                  );
                  return;
                }

                final formattedTitle = [
                  if (time.isNotEmpty) 'Leave at $time',
                  if (location.isNotEmpty) 'for $location',
                  if (title.isNotEmpty) '| $title',
                ].join(' ');

                final ok = await CalendarService.instance.sendCalendarItem(
                  name: title.isEmpty ? 'No upcoming events' : title,
                  time: time,
                  location: location,
                  titleOverride: formattedTitle.isNotEmpty
                      ? formattedTitle
                      : (title.isEmpty ? 'No upcoming events' : title),
                  fullSync: true,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Calendar sent to G1'
                        : 'Failed to send calendar to G1'),
                  ),
                );
              },
              child: const Text('Send to calendar pane'),
            ),
          ),
        ],
      ),
    );
  }
}
