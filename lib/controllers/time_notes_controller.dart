import 'dart:async';

import 'package:get/get.dart';

import 'calendar_controller.dart';
import '../models/device_calendar_event.dart';
import '../models/time_note.dart';
import '../services/time_notes_service.dart';

class TimeNotesController extends GetxController {
  final notes = <TimeNote>[].obs;
  final activeNotes = <TimeNote>[].obs;
  final generalNotes = <TimeNote>[].obs;

  Timer? _ticker;
  Worker? _calendarWorker;
  CalendarController? _calendarController;

  @override
  void onInit() {
    super.onInit();
    if (Get.isRegistered<CalendarController>()) {
      _calendarController = Get.find<CalendarController>();
      _calendarWorker = ever<List<DeviceCalendarEvent>>(
        _calendarController!.events,
        (events) => syncCalendarAttachments(events),
      );
    }
    _load();
  }

  @override
  void onClose() {
    _ticker?.cancel();
    _calendarWorker?.dispose();
    super.onClose();
  }

  Future<void> _load() async {
    final loaded = await TimeNotesService.instance.loadNotes();
    notes.assignAll(loaded);
    if (_calendarController != null && _calendarController!.events.isNotEmpty) {
      await syncCalendarAttachments(_calendarController!.events);
    }
    _startTicker();
    _recomputeActive();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      _recomputeActive();
    });
  }

  Future<void> addOrUpdate(TimeNote note) async {
    final idx = notes.indexWhere((n) => n.id == note.id);
    if (idx >= 0) {
      notes[idx] = note;
    } else {
      notes.add(note);
    }
    await TimeNotesService.instance.saveNotes(notes);
    _recomputeActive();
  }

  Future<void> deleteNote(String id) async {
    notes.removeWhere((n) => n.id == id);
    await TimeNotesService.instance.saveNotes(notes);
    _recomputeActive();
  }

  Future<void> syncCalendarAttachments(List<DeviceCalendarEvent> events) async {
    if (events.isEmpty) {
      _recomputeActive();
      return;
    }

    bool changed = false;
    final lookup = <String, DeviceCalendarEvent>{};
    for (final event in events) {
      final key = '${event.calendarId}::${event.id}';
      lookup[key] = event;
    }

    final updated = <TimeNote>[];
    for (final note in notes) {
      if (!note.isCalendarLinked) {
        updated.add(note);
        continue;
      }

      final key = '${note.calendarId ?? ''}::${note.calendarEventId ?? ''}';
      final event = lookup[key] ?? _findByEventId(lookup, note.calendarEventId);
      if (event == null) {
        updated.add(note);
        continue;
      }

      final refreshed = note.copyWith(
        calendarStart: event.start,
        calendarEnd: event.end,
        calendarTitle: event.title,
        calendarLocation: event.location,
        startDateTime: event.start,
        endDateTime: event.end,
        startMinutes: event.start.hour * 60 + event.start.minute,
        endMinutes: event.end.hour * 60 + event.end.minute,
      );
      updated.add(refreshed);
      if (!_calendarFieldsEqual(note, refreshed)) {
        changed = true;
      }
    }

    if (changed) {
      notes.assignAll(updated);
      await TimeNotesService.instance.saveNotes(notes);
    }
    _recomputeActive();
  }

  bool _calendarFieldsEqual(TimeNote a, TimeNote b) {
    return a.calendarStart == b.calendarStart &&
        a.calendarEnd == b.calendarEnd &&
        a.calendarTitle == b.calendarTitle &&
        a.calendarLocation == b.calendarLocation &&
        a.startDateTime == b.startDateTime &&
        a.endDateTime == b.endDateTime &&
        a.startMinutes == b.startMinutes &&
        a.endMinutes == b.endMinutes;
  }

  DeviceCalendarEvent? _findByEventId(
    Map<String, DeviceCalendarEvent> lookup,
    String? eventId,
  ) {
    if (eventId == null) return null;
    for (final entry in lookup.values) {
      if (entry.id == eventId) return entry;
    }
    return null;
  }

  void _recomputeActive() {
    final now = DateTime.now();
    final active = notes.where((n) => n.isActiveAt(now)).toList();
    activeNotes.assignAll(active);
    generalNotes.assignAll(notes.where((n) => n.type == TimeNoteType.general));
  }
}
