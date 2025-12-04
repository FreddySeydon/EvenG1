import 'package:get/get.dart';
import 'package:device_calendar/device_calendar.dart';

import '../models/device_calendar_event.dart';
import '../services/device_calendar_service.dart';

class CalendarController extends GetxController {
  final isLoading = false.obs;
  final hasPermission = false.obs;
  final calendars = <Calendar>[].obs;
  final events = <DeviceCalendarEvent>[].obs;
  final errorMessage = RxnString();

  /// How far ahead we look for events when refreshing.
  Duration horizon = const Duration(days: 3);

  @override
  void onInit() {
    super.onInit();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final granted = await DeviceCalendarService.instance.hasPermissions();
    hasPermission.value = granted;
    if (granted) {
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

      final now = DateTime.now();
      final start = now.subtract(const Duration(days: 1));
      final end = now.add(horizon);
      final loadedEvents = await DeviceCalendarService.instance.loadEvents(
        start: start,
        end: end,
        calendarIds: loadedCalendars.map((c) => c.id).whereType<String>().toList(),
      );
      events.assignAll(loadedEvents..sort((a, b) => a.start.compareTo(b.start)));
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
}
