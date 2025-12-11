import 'dart:async';

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../ble_manager.dart';
import '../../controllers/calendar_controller.dart';
import '../../controllers/time_notes_controller.dart';
import '../../models/device_calendar_event.dart';
import '../../models/time_note.dart';
import '../../services/calendar_service.dart';
import '../../services/dashboard_note_service.dart';
import '../../services/pin_text_service.dart';
import '../../services/time_notes_scheduler.dart';

class TimeNotesPage extends StatelessWidget {
  const TimeNotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<TimeNotesController>();
    final calendarController = Get.find<CalendarController>();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Time-aware Notes'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Calendar'),
              Tab(text: 'Scheduled'),
              Tab(text: 'Archived'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Calendar tab
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _CalendarSection(
                  calendarController: calendarController,
                  notesController: controller,
                ),
              ],
            ),
            // Scheduled tab
            Obx(() {
              final notes = controller.notes.where((n) => n.archivedAt == null).toList();
              final activeIds = controller.activeNotes.map((n) => n.id).toSet();
              if (notes.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No time-aware notes yet. Tap + to add one.'),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: notes.length,
                itemBuilder: (context, index) {
                  final note = notes[index];
                  final isActive = activeIds.contains(note.id);
                  final linkedEvent = note.isCalendarLinked
                      ? calendarController.findEvent(note.calendarEventId, note.calendarId)
                      : null;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: isActive ? Colors.green.withOpacity(0.08) : null,
                    child: ListTile(
                      title: Text(note.title.isEmpty ? 'Untitled note' : note.title),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            _scheduleLabel(note),
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            note.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isActive)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                'Active now',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.send),
                            tooltip: 'Send to G1 dashboard',
                            onPressed: () => _sendToDashboard(context, note),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () async {
                              await controller.deleteNote(note.id);
                              if (controller.activeNotes.any((n) => n.id == note.id)) {
                                await DashboardNoteService.instance.clearNote(
                                  noteNumber: 1,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      onTap: () => _openEditor(
                        context,
                        controller,
                        note: note,
                        attachedEvent: linkedEvent,
                      ),
                    ),
                  );
                },
              );
            }),
            // Archived tab
            Obx(() {
              final archived = controller.archivedNotes;
              if (archived.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No archived notes'),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      const Text(
                        'Archived notes',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => controller.clearArchived(),
                        child: const Text('Clear all'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...archived.map(
                    (note) => Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: Colors.grey.withOpacity(0.08),
                      child: ListTile(
                        title: Text(
                          note.title.isEmpty ? 'Archived note' : note.title,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              _scheduleLabel(note),
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              note.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete',
                          onPressed: () => controller.deleteNote(note.id),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _openEditor(context, controller),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _CalendarSection extends StatelessWidget {
  const _CalendarSection({
    required this.calendarController,
    required this.notesController,
  });

  final CalendarController calendarController;
  final TimeNotesController notesController;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final hasPermission = calendarController.hasPermission.value;
      final isLoading = calendarController.isLoading.value;
      final error = calendarController.errorMessage.value;
      final events = calendarController.events;
      final calendars = calendarController.calendars;
      final selectedIds = calendarController.selectedCalendarIds;

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
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Calendar events',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh events',
                  onPressed: hasPermission
                      ? () => calendarController.refreshCalendarsAndEvents()
                      : null,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!hasPermission)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Grant calendar permission to attach notes to events.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => calendarController.requestPermission(),
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Allow calendar access'),
                  ),
                ],
              )
            else ...[
              if (calendars.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _showCalendarPicker(context, calendarController),
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
                      Flexible(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            TextButton(
                              onPressed: () => calendarController.selectAllCalendars(calendars),
                              child: const Text('Check all'),
                            ),
                            TextButton(
                              onPressed: () => calendarController.clearCalendarSelection(),
                              child: const Text('Uncheck all'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Window',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Text(
                            _windowDates(calendarController),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          tooltip: 'Previous window',
                          onPressed: () => calendarController.moveWindowByDays(
                            -calendarController.windowSpanDays.value,
                          ),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        IconButton(
                          tooltip: 'Next window',
                          onPressed: () => calendarController.moveWindowByDays(
                            calendarController.windowSpanDays.value,
                          ),
                          icon: const Icon(Icons.chevron_right),
                        ),
                        PopupMenuButton<int>(
                          tooltip: 'Window length',
                          onSelected: (days) => calendarController.setWindowSpan(days),
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
                          onPressed: () => calendarController.resetWindow(),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    error,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Loading events...'),
                    ],
                  ),
                ),
              if (!isLoading && events.isEmpty)
                const Text(
                  'No events found in the selected window.',
                  style: TextStyle(color: Colors.grey),
                )
              else
                ...events.take(5).map(
                  (event) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_formatEventDate(event.start)} · ${_formatEventRange(event)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (event.location.isNotEmpty)
                          Text(
                            event.location,
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.note_add_outlined),
                          tooltip: 'Attach note to this event',
                          onPressed: () {
                            _openEditor(
                              context,
                              notesController,
                              attachedEvent: event,
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.send),
                          tooltip: 'Send to G1 calendar pane',
                          onPressed: () => _sendCalendarEvent(context, event, calendarController),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    });
  }

  Future<void> _sendCalendarEvent(
    BuildContext context,
    DeviceCalendarEvent event,
    CalendarController calendarController,
  ) async {
    if (!BleManager.get().isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect the glasses first.')),
      );
      return;
    }
    final payload = _formatCalendarPayload(event);
    final ok = await CalendarService.instance.sendCalendarItem(
      name: payload.title,
      time: payload.timeLine,
      location: payload.location,
      fullSync: true,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Previewing on G1 for 5 seconds...' : 'Failed to send calendar to G1'),
      ),
    );
    if (ok) {
      Timer(const Duration(seconds: 5), () => _restoreCalendarPane(calendarController));
    }
  }

  Future<void> _restoreCalendarPane(CalendarController controller) async {
    final events = controller.events;
    if (events.isEmpty) {
      await CalendarService.instance.sendCalendarItem(
        name: 'No upcoming events',
        time: '',
        location: '',
        fullSync: true,
      );
      return;
    }

    final now = DateTime.now();
    final next = events.firstWhere(
      (e) => e.start.isAfter(now),
      orElse: () => events.first,
    );

    final payload = _formatCalendarPayload(next);

    await CalendarService.instance.sendCalendarItem(
      name: payload.title,
      time: payload.timeLine,
      location: payload.location,
      fullSync: true,
    );
  }
}
Future<void> _sendToDashboard(BuildContext context, TimeNote note) async {
  if (!BleManager.get().isConnected) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Connect the glasses first to send notes.')),
    );
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Previewing note on G1 for 5 seconds...')),
  );
  await PinTextService.instance.sendPinText(note.content);
  Timer(const Duration(seconds: 5), () {
    if (Get.isRegistered<TimeNotesScheduler>()) {
      Get.find<TimeNotesScheduler>().resendActiveNow();
    }
  });
}

String _scheduleLabel(TimeNote note) {
  if (note.isCalendarLinked) {
    final start = note.calendarStart ?? note.startDateTime;
    final end = note.calendarEnd ?? note.endDateTime;
    final datePart = start != null
        ? '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}'
        : 'Calendar event';
    final range = (start != null && end != null)
        ? '${_formatTime(start)} - ${_formatTime(end)}'
        : 'Active during event';
    final location = note.calendarLocation?.isNotEmpty == true ? note.calendarLocation! : '';
    return [
      'Calendar',
      datePart,
      range,
      if (location.isNotEmpty) location,
    ].join(' · ');
  }

  if (note.type == TimeNoteType.general) {
    return 'General note (shown when no timed note is active)';
  }
  if (note.recurrence == TimeNoteRecurrence.once) {
    final start = note.startDateTime;
    final end = note.endDateTime;
    if (start == null || end == null) return 'One-time (unscheduled)';
    final date = '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final range = '${_formatTime(start)} - ${_formatTime(end)}';
    return '$date · $range';
  }

  final days = note.weekdays.map(_weekdayLabel).join(', ');
  return 'Weekly on $days · ${_formatMinutes(note.startMinutes)} - ${_formatMinutes(note.endMinutes)}';
}

String _formatEventRange(DeviceCalendarEvent event) {
  return '${_formatTime(event.start)} - ${_formatTime(event.end)}';
}

String _formatEventDate(DateTime time) {
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}

String _formatTime(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String _formatMinutes(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

String _weekdayLabel(int weekday) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (weekday < 1 || weekday > 7) return 'Day';
  return names[weekday - 1];
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

String _windowDates(CalendarController controller) {
  final now = DateTime.now();
  final start = now.add(Duration(days: controller.windowStartOffsetDays.value));
  final end = start.add(Duration(days: controller.windowSpanDays.value));
  return '${_formatEventDate(start)} - ${_formatEventDate(end)}';
}

class _CalendarPayload {
  final String title;
  final String timeLine;
  final String location;
  _CalendarPayload({
    required this.title,
    required this.timeLine,
    required this.location,
  });
}

_CalendarPayload _formatCalendarPayload(DeviceCalendarEvent event) {
  final now = DateTime.now();
  final isToday = event.start.year == now.year &&
      event.start.month == now.month &&
      event.start.day == now.day;
  final isTomorrow = !isToday &&
      event.start.isAfter(now) &&
      event.start.isBefore(now.add(const Duration(days: 2))) &&
      event.start.day != now.day;

  final dateLabel = isTomorrow
      ? 'Tomorrow'
      : isToday
          ? 'Today'
          : '${event.start.day.toString().padLeft(2, '0')}.${event.start.month.toString().padLeft(2, '0')}.${event.start.year}';
  final timeLabel =
      '${event.start.hour.toString().padLeft(2, '0')}:${event.start.minute.toString().padLeft(2, '0')}';

  String trunc(String input, int max) {
    if (input.length <= max) return input;
    if (max <= 3) return input.substring(0, max);
    return input.substring(0, max - 3) + '...';
  }

  final title = trunc(event.title, 30);
  final location = trunc(event.location, 15);
  final timeLine =
      location.isNotEmpty ? '$dateLabel $timeLabel | $location' : '$dateLabel $timeLabel';

  return _CalendarPayload(
    title: title,
    timeLine: timeLine,
    location: '',
  );
}

String _truncate(String input, int maxChars) {
  if (input.length <= maxChars) return input;
  if (maxChars <= 1) return input.substring(0, maxChars);
  return input.substring(0, maxChars - 1) + '…';
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

Future<void> _openEditor(
  BuildContext context,
  TimeNotesController controller, {
  TimeNote? note,
  DeviceCalendarEvent? attachedEvent,
}) async {
  final isEditing = note != null;
  final recurrence = ValueNotifier<TimeNoteRecurrence>(
    note?.recurrence ?? TimeNoteRecurrence.once,
  );
  final isGeneral = ValueNotifier<bool>(note?.type == TimeNoteType.general);
  final linkedEvent = ValueNotifier<DeviceCalendarEvent?>(
    attachedEvent ??
        (note?.isCalendarLinked == true
            ? DeviceCalendarEvent(
                id: note!.calendarEventId ?? '',
                calendarId: note.calendarId ?? '',
                title: note.calendarTitle ?? note.title,
                start: note.calendarStart ?? note.startDateTime ?? DateTime.now(),
                end: note.calendarEnd ?? note.endDateTime ?? DateTime.now().add(const Duration(hours: 1)),
                location: note.calendarLocation ?? '',
                allDay: false,
              )
            : null),
  );
  DateTime? oneTimeStart = note?.startDateTime ?? DateTime.now();
  DateTime? oneTimeEnd = note?.endDateTime ?? DateTime.now().add(const Duration(hours: 1));
  List<int> weekdays = note?.weekdays.isNotEmpty == true
      ? List<int>.from(note!.weekdays)
      : [DateTime.now().weekday];
  int startMinutes = note?.startMinutes ?? (DateTime.now().hour * 60 + DateTime.now().minute);
  int endMinutes = note?.endMinutes ?? startMinutes + 60;
  int preOffsetMinutes = note?.preOffsetMinutes ?? 10;
  int postOffsetMinutes = note?.postOffsetMinutes ?? 10;
  bool attachToAllOccurrences = note?.attachToAllOccurrences ?? (linkedEvent.value?.isRecurring ?? false);
  bool isLinkedEventRecurring = linkedEvent.value?.isRecurring ?? note?.isRecurringEvent ?? false;
  final endAction = ValueNotifier<TimeNoteEndAction>(note?.endAction ?? TimeNoteEndAction.delete);
  final titleController = TextEditingController(text: note?.title ?? '');
  final contentController = TextEditingController(text: note?.content ?? '');

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEditing ? 'Edit note' : 'New time-aware note',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contentController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Note content',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Recurrence:'),
                      const SizedBox(width: 12),
                      DropdownButton<TimeNoteRecurrence>(
                        value: recurrence.value,
                        items: const [
                          DropdownMenuItem(
                            value: TimeNoteRecurrence.once,
                            child: Text('One-time'),
                          ),
                          DropdownMenuItem(
                            value: TimeNoteRecurrence.weekly,
                            child: Text('Weekly'),
                          ),
                        ],
                        onChanged: linkedEvent.value != null
                            ? null
                            : (val) {
                                if (val != null) {
                                  setState(() {
                                    recurrence.value = val;
                                  });
                                }
                              },
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          const Text('General note'),
                          Switch(
                            value: isGeneral.value,
                            onChanged: linkedEvent.value != null
                                ? null
                                : (val) {
                                    isGeneral.value = val;
                                    setState(() {});
                                  },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (linkedEvent.value != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CalendarEventSummary(
                          event: linkedEvent.value!,
                          onClear: () {
                            setState(() {
                              linkedEvent.value = null;
                              isLinkedEventRecurring = false;
                              attachToAllOccurrences = false;
                            });
                          },
                        ),
                        if (isLinkedEventRecurring)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Attach to all occurrences'),
                            subtitle: const Text('Stay linked across the series'),
                            value: attachToAllOccurrences,
                            onChanged: (val) {
                              setState(() {
                                attachToAllOccurrences = val;
                              });
                            },
                          ),
                        const SizedBox(height: 12),
                        _OffsetFields(
                          preMinutes: preOffsetMinutes,
                          postMinutes: postOffsetMinutes,
                          onChanged: (pre, post) {
                            setState(() {
                              preOffsetMinutes = pre;
                              postOffsetMinutes = post;
                            });
                          },
                        ),
                        if (!isLinkedEventRecurring || !attachToAllOccurrences)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: _EndActionPicker(
                              value: endAction.value,
                              onChanged: (action) {
                                endAction.value = action;
                                setState(() {});
                              },
                            ),
                          ),
                      ],
                    )
                  else ...[
                    if (!isGeneral.value && recurrence.value == TimeNoteRecurrence.once) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DateTimeField(
                            label: 'Start',
                            value: oneTimeStart,
                            onPick: () async {
                              final picked = await _pickDateTime(context, oneTimeStart ?? DateTime.now());
                              if (picked == null) return;
                              setState(() {
                                oneTimeStart = picked;
                                if (oneTimeEnd != null && oneTimeEnd!.isBefore(picked)) {
                                  oneTimeEnd = picked.add(const Duration(hours: 1));
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          _DateTimeField(
                            label: 'End',
                            value: oneTimeEnd,
                            onPick: () async {
                              final picked = await _pickDateTime(context, oneTimeEnd ?? DateTime.now());
                              if (picked == null) return;
                              setState(() {
                                oneTimeEnd = picked;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _OffsetFields(
                        preMinutes: preOffsetMinutes,
                        postMinutes: postOffsetMinutes,
                        onChanged: (pre, post) {
                          setState(() {
                            preOffsetMinutes = pre;
                            postOffsetMinutes = post;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      _EndActionPicker(
                        value: endAction.value,
                        onChanged: (action) {
                          endAction.value = action;
                          setState(() {});
                        },
                      ),
                    ] else if (!isGeneral.value)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Days of week',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            children: List.generate(7, (index) {
                              final day = index + 1;
                              final label = ['M', 'T', 'W', 'T', 'F', 'S', 'S'][index];
                              final selected = weekdays.contains(day);
                              return ChoiceChip(
                                label: Text(label),
                                selected: selected,
                                onSelected: (_) {
                                  setState(() {
                                    if (selected) {
                                      weekdays.remove(day);
                                    } else {
                                      weekdays.add(day);
                                      weekdays.sort();
                                    }
                                  });
                                },
                              );
                            }),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _TimeField(
                                  label: 'Start',
                                  valueMinutes: startMinutes,
                                  onPick: () async {
                                    final picked = await _pickTime(context, startMinutes);
                                    if (picked != null) {
                                      setState(() {
                                        startMinutes = picked;
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _TimeField(
                                  label: 'End',
                                  valueMinutes: endMinutes,
                                  onPick: () async {
                                    final picked = await _pickTime(context, endMinutes);
                                    if (picked != null) {
                                      setState(() {
                                        endMinutes = picked;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _OffsetFields(
                            preMinutes: preOffsetMinutes,
                            postMinutes: postOffsetMinutes,
                            onChanged: (pre, post) {
                              setState(() {
                                preOffsetMinutes = pre;
                                postOffsetMinutes = post;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          _EndActionPicker(
                            value: endAction.value,
                            onChanged: (action) {
                              endAction.value = action;
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final newNote = _buildNote(
                          note: note,
                          title: titleController.text.trim(),
                          content: contentController.text.trim(),
                          isGeneral: isGeneral.value,
                          recurrence: recurrence.value,
                          oneTimeStart: oneTimeStart,
                          oneTimeEnd: oneTimeEnd,
                          weekdays: weekdays,
                          startMinutes: startMinutes,
                          endMinutes: endMinutes,
                          linkedEvent: linkedEvent.value,
                          endAction: endAction.value,
                          preOffsetMinutes: preOffsetMinutes,
                          postOffsetMinutes: postOffsetMinutes,
                          attachToAllOccurrences: attachToAllOccurrences,
                          isRecurringEvent: isLinkedEventRecurring,
                        );

                        if (newNote == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please fill all required fields with a valid time range.')),
                          );
                          return;
                        }

                        await controller.addOrUpdate(newNote);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Text(isEditing ? 'Save changes' : 'Add note'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

TimeNote? _buildNote({
  required String title,
  required String content,
  required TimeNoteRecurrence recurrence,
  required bool isGeneral,
  required DateTime? oneTimeStart,
  required DateTime? oneTimeEnd,
  required List<int> weekdays,
  required int startMinutes,
  required int endMinutes,
  required TimeNoteEndAction endAction,
  required int preOffsetMinutes,
  required int postOffsetMinutes,
  required bool attachToAllOccurrences,
  required bool isRecurringEvent,
  TimeNote? note,
  DeviceCalendarEvent? linkedEvent,
}) {
  if (content.isEmpty) return null;

  if (linkedEvent != null) {
    return TimeNote(
      id: note?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      content: content,
      type: TimeNoteType.timed,
      recurrence: TimeNoteRecurrence.once,
      startMinutes: linkedEvent.start.hour * 60 + linkedEvent.start.minute,
      endMinutes: linkedEvent.end.hour * 60 + linkedEvent.end.minute,
      startDateTime: linkedEvent.start,
      endDateTime: linkedEvent.end,
      calendarEventId: linkedEvent.id,
      calendarId: linkedEvent.calendarId,
      calendarStart: linkedEvent.start,
      calendarEnd: linkedEvent.end,
      calendarTitle: linkedEvent.title,
      calendarLocation: linkedEvent.location,
      endAction: endAction,
      preOffsetMinutes: preOffsetMinutes,
      postOffsetMinutes: postOffsetMinutes,
      attachToAllOccurrences: attachToAllOccurrences && isRecurringEvent,
      isRecurringEvent: isRecurringEvent,
    );
  }

  if (isGeneral) {
    return TimeNote(
      id: note?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      content: content,
      type: TimeNoteType.general,
      recurrence: TimeNoteRecurrence.once,
      startMinutes: 0,
      endMinutes: 0,
      endAction: endAction,
      preOffsetMinutes: preOffsetMinutes,
      postOffsetMinutes: postOffsetMinutes,
      attachToAllOccurrences: false,
      isRecurringEvent: false,
    );
  }

  if (recurrence == TimeNoteRecurrence.once) {
    if (oneTimeStart == null || oneTimeEnd == null) return null;
    if (!oneTimeEnd.isAfter(oneTimeStart)) return null;
    return TimeNote(
      id: note?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      content: content,
      type: TimeNoteType.timed,
      recurrence: recurrence,
      startDateTime: oneTimeStart,
      endDateTime: oneTimeEnd,
      startMinutes: oneTimeStart.hour * 60 + oneTimeStart.minute,
      endMinutes: oneTimeEnd.hour * 60 + oneTimeEnd.minute,
      endAction: endAction,
      preOffsetMinutes: preOffsetMinutes,
      postOffsetMinutes: postOffsetMinutes,
      attachToAllOccurrences: false,
      isRecurringEvent: false,
    );
  }

  if (weekdays.isEmpty) return null;
  if (endMinutes <= startMinutes) return null;

  return TimeNote(
    id: note?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
    title: title,
    content: content,
    type: TimeNoteType.timed,
    recurrence: recurrence,
    startMinutes: startMinutes,
    endMinutes: endMinutes,
    weekdays: weekdays,
    endAction: endAction,
    preOffsetMinutes: preOffsetMinutes,
    postOffsetMinutes: postOffsetMinutes,
    attachToAllOccurrences: false,
    isRecurringEvent: false,
  );
}

class _EndActionPicker extends StatelessWidget {
  const _EndActionPicker({
    required this.value,
    required this.onChanged,
  });

  final TimeNoteEndAction value;
  final ValueChanged<TimeNoteEndAction> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'After it ends',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Delete'),
              selected: value == TimeNoteEndAction.delete,
              onSelected: (_) => onChanged(TimeNoteEndAction.delete),
            ),
            ChoiceChip(
              label: const Text('Archive'),
              selected: value == TimeNoteEndAction.archive,
              onSelected: (_) => onChanged(TimeNoteEndAction.archive),
            ),
          ],
        ),
      ],
    );
  }
}

class _OffsetFields extends StatelessWidget {
  const _OffsetFields({
    required this.preMinutes,
    required this.postMinutes,
    required this.onChanged,
  });

  final int preMinutes;
  final int postMinutes;
  final void Function(int pre, int post) onChanged;

  List<int> get _options => const [0, 5, 10, 15, 30, 60];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Display window',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Show before (min)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    isDense: true,
                    value: preMinutes,
                    items: _options
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text('$v'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      onChanged(v, postMinutes);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Keep after (min)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    isDense: true,
                    value: postMinutes,
                    items: _options
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text('$v'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      onChanged(preMinutes, v);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CalendarEventSummary extends StatelessWidget {
  const _CalendarEventSummary({
    required this.event,
    required this.onClear,
  });

  final DeviceCalendarEvent event;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: Colors.blue.withOpacity(0.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_available, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Detach calendar event',
                onPressed: onClear,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${_formatEventDate(event.start)} · ${_formatEventRange(event)}'),
          if (event.location.isNotEmpty)
            Text(
              event.location,
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final DateTime? value;
  final Future<void> Function() onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 4),
                Text(
                  value != null
                      ? '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')} ${value!.hour.toString().padLeft(2, '0')}:${value!.minute.toString().padLeft(2, '0')}'
                      : 'Pick date & time',
                ),
              ],
            ),
            const Icon(Icons.calendar_today, size: 18),
          ],
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.valueMinutes,
    required this.onPick,
  });

  final String label;
  final int valueMinutes;
  final Future<void> Function() onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 4),
                Text(_format(valueMinutes)),
              ],
            ),
            const Icon(Icons.schedule, size: 18),
          ],
        ),
      ),
    );
  }

  String _format(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}

Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime.now().subtract(const Duration(days: 1)),
    lastDate: DateTime.now().add(const Duration(days: 365)),
  );
  if (date == null) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

Future<int?> _pickTime(BuildContext context, int initialMinutes) async {
  final initialTime = TimeOfDay(
    hour: (initialMinutes ~/ 60) % 24,
    minute: initialMinutes % 60,
  );
  final picked = await showTimePicker(context: context, initialTime: initialTime);
  if (picked == null) return null;
  return picked.hour * 60 + picked.minute;
}

String _calendarDisplayName(Calendar cal) {
  final name = (cal.name ?? 'Calendar').trim();
  final account = (cal.accountName ?? '').trim();
  if (account.isEmpty) return name.isEmpty ? 'Calendar' : name;
  return '${name.isEmpty ? 'Calendar' : name} ($account)';
}

