import 'dart:async';

import 'package:get/get.dart';

import 'calendar_controller.dart';
import '../models/device_calendar_event.dart';
import '../models/time_note.dart';
import '../services/device_calendar_service.dart';
import '../services/time_notes_service.dart';

class TimeNotesController extends GetxController {
  final notes = <TimeNote>[].obs;
  final activeNotes = <TimeNote>[].obs;
  final generalNotes = <TimeNote>[].obs;
  final archivedNotes = <TimeNote>[].obs;

  Timer? _ticker;
  Timer? _calendarResyncTicker;
  Worker? _calendarWorker;
  CalendarController? _calendarController;
  bool _resyncInFlight = false;
  DateTime? _lastResync;

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
    _calendarResyncTicker?.cancel();
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
    await _resyncLinkedNotesFromCalendar();
    await _recomputeActive();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      _recomputeActive();
    });

    _calendarResyncTicker?.cancel();
    _calendarResyncTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      _resyncLinkedNotesFromCalendar();
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
    await _recomputeActive();
  }

  Future<void> deleteNote(String id) async {
    notes.removeWhere((n) => n.id == id);
    await TimeNotesService.instance.saveNotes(notes);
    await _recomputeActive();
  }

  Future<void> clearArchived() async {
    notes.removeWhere((n) => n.archivedAt != null);
    await TimeNotesService.instance.saveNotes(notes);
    await _recomputeActive();
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
      DeviceCalendarEvent? event = lookup[key] ?? _findByEventId(lookup, note.calendarEventId);
      event ??= note.calendarEventId != null
          ? await DeviceCalendarService.instance.loadEventById(
              calendarId: note.calendarId,
              eventId: note.calendarEventId!,
              anchor: note.attachToAllOccurrences ? DateTime.now() : note.calendarStart ?? note.startDateTime,
            )
          : null;
      final shouldClear = event == null && !(note.attachToAllOccurrences && note.isRecurringEvent);

      final refreshed = shouldClear
          ? note.copyWith(
              calendarStart: null,
              calendarEnd: null,
              startDateTime: null,
              endDateTime: null,
              startMinutes: 0,
              endMinutes: 0,
              isRecurringEvent: note.isRecurringEvent,
            )
          : () {
              final startRef = event?.start ?? note.calendarStart ?? note.startDateTime;
              final endRef = event?.end ?? note.calendarEnd ?? note.endDateTime;
              final startMinutes = startRef != null ? startRef.hour * 60 + startRef.minute : 0;
              final endMinutes = endRef != null ? endRef.hour * 60 + endRef.minute : 0;
              return note.copyWith(
                calendarStart: event?.start ?? note.calendarStart,
                calendarEnd: event?.end ?? note.calendarEnd,
                calendarTitle: event?.title ?? note.calendarTitle,
                calendarLocation: event?.location ?? note.calendarLocation,
                startDateTime: event?.start ?? note.startDateTime,
                endDateTime: event?.end ?? note.endDateTime,
                startMinutes: startMinutes,
                endMinutes: endMinutes,
                isRecurringEvent: event?.isRecurring ?? note.isRecurringEvent,
              );
            }();
      updated.add(refreshed);
      if (!_calendarFieldsEqual(note, refreshed)) {
        changed = true;
      }
    }

    if (changed) {
      notes.assignAll(updated);
      await TimeNotesService.instance.saveNotes(notes);
    }
    await _recomputeActive();
  }

  /// Periodically refresh calendar-linked notes by eventId to pick up time changes
  /// even when the event list/window hasn't been refreshed.
  Future<void> _resyncLinkedNotesFromCalendar() async {
    if (_resyncInFlight) return;
    final now = DateTime.now();
    if (_lastResync != null && now.difference(_lastResync!) < const Duration(minutes: 1)) {
      return;
    }
    _resyncInFlight = true;
    _lastResync = now;
    try {
      if (notes.isEmpty) return;
      bool changed = false;
      final updated = <TimeNote>[];
      for (final note in notes) {
        if (!note.isCalendarLinked) {
          updated.add(note);
          continue;
        }
        final event = note.calendarEventId != null
            ? await DeviceCalendarService.instance.loadEventById(
                calendarId: note.calendarId,
                eventId: note.calendarEventId!,
                anchor: note.attachToAllOccurrences ? DateTime.now() : note.calendarStart ?? note.startDateTime,
              )
            : null;
        final refreshed = event == null
            ? note.copyWith(
                calendarStart: null,
                calendarEnd: null,
                startDateTime: null,
                endDateTime: null,
                startMinutes: 0,
                endMinutes: 0,
                isRecurringEvent: note.isRecurringEvent,
              )
            : () {
                final startRef = event.start;
                final endRef = event.end;
                final startMinutes = startRef.hour * 60 + startRef.minute;
                final endMinutes = endRef.hour * 60 + endRef.minute;
                return note.copyWith(
                  calendarStart: event.start,
                  calendarEnd: event.end,
                  calendarTitle: event.title,
                  calendarLocation: event.location,
                  startDateTime: startRef,
                  endDateTime: endRef,
                  startMinutes: startMinutes,
                  endMinutes: endMinutes,
                  isRecurringEvent: event.isRecurring,
                );
              }();
        updated.add(refreshed);
        if (!_calendarFieldsEqual(note, refreshed)) {
          changed = true;
        }
      }

      if (changed) {
        notes.assignAll(updated);
        await TimeNotesService.instance.saveNotes(notes);
      }
      await _recomputeActive();
    } finally {
      _resyncInFlight = false;
    }
  }

  bool _calendarFieldsEqual(TimeNote a, TimeNote b) {
    return a.calendarStart == b.calendarStart &&
        a.calendarEnd == b.calendarEnd &&
        a.calendarTitle == b.calendarTitle &&
        a.calendarLocation == b.calendarLocation &&
        a.startDateTime == b.startDateTime &&
        a.endDateTime == b.endDateTime &&
        a.startMinutes == b.startMinutes &&
        a.endMinutes == b.endMinutes &&
        a.isRecurringEvent == b.isRecurringEvent;
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

  Future<void> _recomputeActive() async {
    final now = DateTime.now();
    await _cleanupExpiredNotes(now);
    final active = notes.where((n) => n.isActiveAt(now)).toList();
    activeNotes.assignAll(active);
    generalNotes.assignAll(notes.where((n) => n.type == TimeNoteType.general && n.archivedAt == null));
    archivedNotes.assignAll(notes.where((n) => n.archivedAt != null));
  }

  Future<void> _cleanupExpiredNotes(DateTime now) async {
    bool changed = false;
    final remaining = <TimeNote>[];
    for (final note in notes) {
      if (note.archivedAt != null) {
        remaining.add(note);
        continue;
      }
      if (_isExpired(note, now)) {
        if (note.endAction == TimeNoteEndAction.delete) {
          changed = true;
          continue;
        }
        remaining.add(note.copyWith(archivedAt: now));
        changed = true;
        continue;
      }
      remaining.add(note);
    }
    if (changed) {
      notes.assignAll(remaining);
      await TimeNotesService.instance.saveNotes(notes);
    }
  }

  bool _isExpired(TimeNote note, DateTime now) {
    if (note.archivedAt != null) return false;
    if (note.type == TimeNoteType.general) return false;
    if (note.recurrence == TimeNoteRecurrence.weekly) return false;
    if (note.attachToAllOccurrences && note.isRecurringEvent) return false;

    if (note.isCalendarLinked) {
      if (note.calendarEnd == null) return false;
      final windowEnd = note.calendarEnd!.add(Duration(minutes: note.postOffsetMinutes));
      return now.isAfter(windowEnd);
    }

    if (note.recurrence == TimeNoteRecurrence.once) {
      if (note.endDateTime == null) return false;
      final windowEnd = note.endDateTime!.add(Duration(minutes: note.postOffsetMinutes));
      return now.isAfter(windowEnd);
    }

    return false;
  }
}
