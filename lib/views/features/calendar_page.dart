import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../ble_manager.dart';
import '../../controllers/calendar_controller.dart';
import '../../models/device_calendar_event.dart';

class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<CalendarController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
      ),
      body: Obx(() {
        final hasPermission = controller.hasPermission.value;
        final isLoading = controller.isLoading.value;
        final error = controller.errorMessage.value;
        final calendars = controller.calendars;
        final selectedIds = controller.selectedCalendarIds;
        final autoSend = controller.autoSendNextEvent.value;
        final events = controller.events;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionCard(
              title: 'Permissions',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasPermission ? 'Calendar access granted' : 'Calendar access not granted',
                    style: TextStyle(
                      color: hasPermission ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => controller.requestPermission(),
                    icon: const Icon(Icons.lock_open),
                    label: Text(hasPermission ? 'Re-check permission' : 'Grant permission'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Calendars',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(error, style: const TextStyle(color: Colors.red)),
                    ),
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Loading calendars...'),
                        ],
                      ),
                    ),
                  if (calendars.isEmpty)
                    const Text('No calendars found. Grant permission and refresh.')
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _showCalendarPicker(context, controller),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _calendarSelectionLabel(calendars, selectedIds),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            TextButton(
                              onPressed: () => controller.selectAllCalendars(calendars),
                              child: const Text('Check all'),
                            ),
                            TextButton(
                              onPressed: () => controller.clearCalendarSelection(),
                              child: const Text('Uncheck all'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => controller.refreshCalendarsAndEvents(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh events'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Window & Auto-send',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Window', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text(_windowDates(controller)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Previous window',
                        onPressed: () => controller.moveWindowByDays(-controller.windowSpanDays.value),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'Next window',
                        onPressed: () => controller.moveWindowByDays(controller.windowSpanDays.value),
                        icon: const Icon(Icons.chevron_right),
                      ),
                      PopupMenuButton<int>(
                        tooltip: 'Window length',
                        onSelected: (days) => controller.setWindowSpan(days),
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 7, child: Text('7 days')),
                          PopupMenuItem(value: 14, child: Text('14 days')),
                          PopupMenuItem(value: 30, child: Text('30 days')),
                        ],
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.calendar_view_week),
                        ),
                      ),
                      TextButton(
                        onPressed: () => controller.resetWindow(),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto-display next event on glasses'),
                    subtitle: const Text('When events refresh and glasses are connected'),
                    value: autoSend,
                    onChanged: (val) => controller.setAutoSendNextEvent(val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Next event',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _nextEventTile(events),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: !BleManager.get().isConnected
                        ? null
                        : () => controller.sendNextEventToGlasses(fullSync: true),
                    icon: const Icon(Icons.send),
                    label: Text(
                      BleManager.get().isConnected ? 'Send to glasses' : 'Connect glasses first',
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _nextEventTile(List<DeviceCalendarEvent> events) {
    if (events.isEmpty) {
      return const Text('No events in the current window.');
    }
    final sorted = [...events]..sort((a, b) => a.start.compareTo(b.start));
    final now = DateTime.now();
    final upcoming = sorted.where((e) => e.start.isAfter(now)).toList();
    if (upcoming.isEmpty) {
      return const Text('No upcoming events in the current window.');
    }
    final next = upcoming.first;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(next.title),
      subtitle: Text(
        '${_formatDate(next.start)} | ${_formatTimeRange(next)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: next.location.isEmpty
          ? null
          : SizedBox(
              width: 120,
              child: Text(
                next.location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
    );
  }

  String _windowDates(CalendarController controller) {
    final now = DateTime.now();
    final start = now.add(Duration(days: controller.windowStartOffsetDays.value));
    final end = start.add(Duration(days: controller.windowSpanDays.value));
    return '${_formatDate(start)} - ${_formatDate(end)}';
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  String _formatTimeRange(DeviceCalendarEvent event) {
    final start = event.start;
    final end = event.end;
    String fmt(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '${fmt(start)}-${fmt(end)}';
  }
}

String _calendarSelectionLabel(
  List<Calendar> calendars,
  Set<String> selectedIds,
) {
  if (selectedIds.isEmpty) return 'Select calendars';
  final names = <String>[];
  for (final cal in calendars) {
    final id = cal.id ?? '';
    if (selectedIds.contains(id)) {
      names.add(_calendarDisplayName(cal));
    }
  }
  if (names.isEmpty) return 'Select calendars';
  final joined = names.join(', ');
  return 'Calendars (${selectedIds.length}): $joined';
}

Future<void> _showCalendarPicker(
  BuildContext context,
  CalendarController controller,
) async {
  final calendars = controller.calendars;
  if (calendars.isEmpty) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DraggableScrollableSheet(
            expand: false,
            builder: (context, scrollController) {
              return Obx(() {
                final selectedIds = controller.selectedCalendarIds;
                return SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Choose calendars',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              controller.selectAllCalendars(calendars);
                              Navigator.pop(context);
                            },
                            child: const Text('Check all'),
                          ),
                          TextButton(
                            onPressed: () {
                              controller.clearCalendarSelection();
                              Navigator.pop(context);
                            },
                            child: const Text('Uncheck all'),
                          ),
                        ],
                      ),
                      const Divider(),
                      ...calendars.map((cal) {
                        final id = cal.id ?? '';
                        final isSelected = selectedIds.contains(id);
                        return CheckboxListTile(
                          title: Text(_calendarDisplayName(cal)),
                          value: isSelected,
                          onChanged: (val) {
                            controller.toggleCalendarSelection(id, val ?? false);
                          },
                        );
                      }),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                );
              });
            },
          ),
        ),
      );
    },
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

String _calendarDisplayName(Calendar cal) {
  final name = (cal.name ?? 'Calendar').trim();
  final account = (cal.accountName ?? '').trim();
  if (account.isEmpty) return name.isEmpty ? 'Calendar' : name;
  return '${name.isEmpty ? 'Calendar' : name} ($account)';
}
