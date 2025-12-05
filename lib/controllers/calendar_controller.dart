import 'package:get/get.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble_manager.dart';
import '../models/device_calendar_event.dart';
import '../services/calendar_service.dart';
import '../services/device_calendar_service.dart';

class CalendarController extends GetxController {
  final isLoading = false.obs;
  final hasPermission = false.obs;
  final calendars = <Calendar>[].obs;
  final events = <DeviceCalendarEvent>[].obs;
  final errorMessage = RxnString();
  final selectedCalendarIds = <String>{}.obs;
  final windowStartOffsetDays = 0.obs;
  final windowSpanDays = 14.obs;
  final autoSendNextEvent = false.obs;

  static const _prefSelectedIds = 'calendar_selected_ids';
  static const _prefAutoSend = 'calendar_auto_send_next';

  /// How far ahead we look for events when refreshing.
  Duration get horizon => Duration(days: windowSpanDays.value);

  @override
  void onInit() {
    super.onInit();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final granted = await DeviceCalendarService.instance.hasPermissions();
    hasPermission.value = granted;
    if (granted) {
      await _loadSelectedCalendars();
      await _loadAutoSendPref();
      await refreshCalendarsAndEvents();
    }
  }

  Future<void> requestPermission() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final granted = await DeviceCalendarService.instance.requestPermissions();
      hasPermission.value = granted;
      if (granted) {
        await refreshCalendarsAndEvents();
      }
    } catch (e) {
      errorMessage.value = 'Failed to request calendar permission: $e';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refreshCalendarsAndEvents() async {
    if (!hasPermission.value) return;
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final loadedCalendars = await DeviceCalendarService.instance.loadCalendars();
      calendars.assignAll(loadedCalendars);
      await _ensureSelectionSeeded(loadedCalendars);

      final now = DateTime.now();
      final start = now.add(Duration(days: windowStartOffsetDays.value));
      final end = start.add(horizon);
      final loadedEvents = await DeviceCalendarService.instance.loadEvents(
        start: start,
        end: end,
        calendarIds: _effectiveCalendarIds(loadedCalendars),
      );
      events.assignAll(loadedEvents..sort((a, b) => a.start.compareTo(b.start)));

      if (autoSendNextEvent.value && BleManager.get().isConnected) {
        await sendNextEventToGlasses(fullSync: true);
      }
    } catch (e) {
      errorMessage.value = 'Failed to load calendar events: $e';
    } finally {
      isLoading.value = false;
    }
  }

  DeviceCalendarEvent? findEvent(String? eventId, String? calendarId) {
    if (eventId == null) return null;
    for (final event in events) {
      if (event.id == eventId && (calendarId == null || event.calendarId == calendarId)) {
        return event;
      }
    }
    return null;
  }

  List<DeviceCalendarEvent> activeEvents(DateTime now) {
    return events.where((e) => e.isActiveAt(now)).toList();
  }

  Future<void> toggleCalendarSelection(String calendarId, bool selected) async {
    if (selected) {
      selectedCalendarIds.add(calendarId);
    } else {
      selectedCalendarIds.remove(calendarId);
    }
    selectedCalendarIds.refresh();
    await _persistSelectedCalendars();
    await refreshCalendarsAndEvents();
  }

  Future<void> moveWindowByDays(int delta) async {
    windowStartOffsetDays.value += delta;
    await refreshCalendarsAndEvents();
  }

  Future<void> setWindowSpan(int days) async {
    if (days < 1) return;
    windowSpanDays.value = days;
    await refreshCalendarsAndEvents();
  }

  Future<void> resetWindow() async {
    windowStartOffsetDays.value = 0;
    windowSpanDays.value = 14;
    await refreshCalendarsAndEvents();
  }

  Future<void> selectAllCalendars(List<Calendar> list) async {
    selectedCalendarIds
      ..clear()
      ..addAll(list.map((c) => c.id).whereType<String>());
    selectedCalendarIds.refresh();
    await _persistSelectedCalendars();
    await refreshCalendarsAndEvents();
  }

  Future<void> clearCalendarSelection() async {
    selectedCalendarIds.clear();
    selectedCalendarIds.refresh();
    await _persistSelectedCalendars();
    events.clear();
  }

  Future<void> _loadSelectedCalendars() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_prefSelectedIds) ?? <String>[];
      selectedCalendarIds
        ..clear()
        ..addAll(stored);
    } catch (e) {
      print('CalendarController: failed to load selected calendars: $e');
    }
  }

  Future<void> _persistSelectedCalendars() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefSelectedIds, selectedCalendarIds.toList());
    } catch (e) {
      print('CalendarController: failed to persist selected calendars: $e');
    }
  }

  Future<void> _loadAutoSendPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(_prefAutoSend);
      if (stored != null) {
        autoSendNextEvent.value = stored;
      }
    } catch (e) {
      print('CalendarController: failed to load auto-send pref: $e');
    }
  }

  Future<void> setAutoSendNextEvent(bool value) async {
    autoSendNextEvent.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefAutoSend, value);
    } catch (e) {
      print('CalendarController: failed to persist auto-send pref: $e');
    }
    if (value) {
      await refreshCalendarsAndEvents();
    }
  }

  Future<void> _ensureSelectionSeeded(List<Calendar> loadedCalendars) async {
    if (selectedCalendarIds.isNotEmpty) return;
    if (loadedCalendars.isEmpty) return;
    final firstId = loadedCalendars.first.id;
    if (firstId == null || firstId.isEmpty) return;
    selectedCalendarIds
      ..clear()
      ..add(firstId);
    await _persistSelectedCalendars();
  }

  List<String> _effectiveCalendarIds(List<Calendar> loadedCalendars) {
    final ids = selectedCalendarIds.toList();
    if (ids.isNotEmpty) return ids;
    return const <String>[];
  }

  Future<bool> sendNextEventToGlasses({bool fullSync = true}) async {
    if (!BleManager.get().isConnected) return false;
    if (events.isEmpty) {
      return CalendarService.instance.sendCalendarItem(
        name: 'No upcoming events',
        time: '',
        location: '',
        fullSync: fullSync,
      );
    }
    final now = DateTime.now();
    final upcoming = events.where((e) => e.start.isAfter(now)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final next = upcoming.isNotEmpty ? upcoming.first : events.first;
    final timeLabel = _formatTimeLabel(next);
    return CalendarService.instance.sendCalendarItem(
      name: next.title,
      time: timeLabel,
      location: next.location,
      fullSync: fullSync,
    );
  }

  String _formatTimeLabel(DeviceCalendarEvent event) {
    final now = DateTime.now();
    final isToday = event.start.year == now.year &&
        event.start.month == now.month &&
        event.start.day == now.day;
    final isTomorrow = !isToday &&
        event.start.isAfter(now) &&
        event.start.isBefore(now.add(const Duration(days: 2))) &&
        event.start.day != now.day;
    final datePart = isToday
        ? 'Today'
        : (isTomorrow
            ? 'Tomorrow'
            : '${event.start.day.toString().padLeft(2, '0')}.${event.start.month.toString().padLeft(2, '0')}.${event.start.year}');
    final timePart =
        '${event.start.hour.toString().padLeft(2, '0')}:${event.start.minute.toString().padLeft(2, '0')}';
    return '$datePart  $timePart';
  }
}
