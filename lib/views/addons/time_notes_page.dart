import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:device_calendar/device_calendar.dart';

import '../../ble_manager.dart';
import '../../controllers/calendar_controller.dart';
import '../../controllers/time_notes_controller.dart';
import '../../models/device_calendar_event.dart';
import '../../models/time_note.dart';
import '../../services/calendar_service.dart';
import '../../services/dashboard_note_service.dart';
import '../../services/pin_text_service.dart';

class TimeNotesPage extends StatelessWidget {
  const TimeNotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<TimeNotesController>();
    final calendarController = Get.find<CalendarController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Time-aware Notes'),
      ),
      body: Obx(() {
        final notes = controller.notes;
        final activeIds = controller.activeNotes.map((n) => n.id).toSet();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CalendarSection(
              calendarController: calendarController,
              notesController: controller,
            ),
            const SizedBox(height: 12),
            if (notes.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(
                  child: Text('No time-aware notes yet. Tap + to add one.'),
                ),
              )
            else
              ...List.generate(notes.length, (index) {
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
              }),
          ],
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(context, controller),
        child: const Icon(Icons.add),
      ),
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
    const SnackBar(content: Text('Sending note to G1 dashboard...')),
  );
  await PinTextService.instance.sendPinText(note.content);
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Note sent to G1 dashboard')),
  );
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
    ].join(' Жњ ');
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
    return '$date Жњ $range';
  }

  final days = note.weekdays.map(_weekdayLabel).join(', ');
  return 'Weekly on $days Жњ ${_formatMinutes(note.startMinutes)} - ${_formatMinutes(note.endMinutes)}';
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
      names.add(cal.name ?? 'Calendar');
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
                          title: Text(cal.name ?? 'Calendar'),
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
                    _CalendarEventSummary(
                      event: linkedEvent.value!,
                      onClear: () {
                        setState(() {
                          linkedEvent.value = null;
                        });
                      },
                    )
                  else ...[
                    if (!isGeneral.value && recurrence.value == TimeNoteRecurrence.once)
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
                      )
                    else if (!isGeneral.value)
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
  );
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
                      TextButton(
                        onPressed: () => calendarController.selectAllCalendars(calendars),
                        child: const Text('Check all'),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () => calendarController.clearCalendarSelection(),
                        child: const Text('Uncheck all'),
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
                  'No events found in the next few days.',
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
                          onPressed: () => _sendCalendarEvent(context, event),
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
  ) async {
    if (!BleManager.get().isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect the glasses first.')),
      );
      return;
    }
    final timeLabel = _formatEventRange(event);
    final formattedTitle = [
      timeLabel,
      if (event.location.isNotEmpty) event.location,
      event.title,
    ].where((part) => part.isNotEmpty).join(' | ');
    final ok = await CalendarService.instance.sendCalendarItem(
      name: event.title,
      time: timeLabel,
      location: event.location,
      titleOverride: formattedTitle,
      fullSync: true,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Calendar sent to G1' : 'Failed to send calendar to G1'),
        ),
      );
    }
  }
}
