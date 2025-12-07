import 'package:device_calendar/device_calendar.dart';

import '../models/device_calendar_event.dart';

class DeviceCalendarService {
  DeviceCalendarService._();

  static final DeviceCalendarService instance = DeviceCalendarService._();
  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  Future<bool> hasPermissions() async {
    try {
      final result = await _plugin.hasPermissions();
      return result.data ?? false;
    } catch (e) {
      print('DeviceCalendarService.hasPermissions error: $e');
      return false;
    }
  }

  Future<bool> requestPermissions() async {
    try {
      final result = await _plugin.requestPermissions();
      return result.data ?? false;
    } catch (e) {
      print('DeviceCalendarService.requestPermissions error: $e');
      return false;
    }
  }

  Future<List<Calendar>> loadCalendars() async {
    try {
      final calendars = await _plugin.retrieveCalendars();
      return calendars.data ?? <Calendar>[];
    } catch (e) {
      print('DeviceCalendarService.loadCalendars error: $e');
      return <Calendar>[];
    }
  }

  Future<DeviceCalendarEvent?> loadEventById({
    String? calendarId,
    required String eventId,
    DateTime? anchor,
  }) async {
    if (eventId.isEmpty) return null;
    try {
      final ids = calendarId != null && calendarId.isNotEmpty
          ? <String>[calendarId]
          : (await loadCalendars()).map((c) => c.id).whereType<String>().toList();
      final center = anchor ?? DateTime.now();
      final start = center.subtract(const Duration(days: 365));
      final end = center.add(const Duration(days: 365));
      for (final id in ids) {
        final response = await _plugin.retrieveEvents(
          id,
          RetrieveEventsParams(
            startDate: start,
            endDate: end,
          ),
        );
        final data = response.data ?? <Event>[];
        for (final event in data) {
          if (event.eventId != eventId) continue;
          if (event.start == null || event.end == null) continue;
          try {
            return DeviceCalendarEvent.fromPlugin(event, id);
          } catch (_) {
            // Skip malformed events.
          }
        }
      }
    } catch (e) {
      print('DeviceCalendarService.loadEventById error: $e');
    }
    return null;
  }

  Future<List<DeviceCalendarEvent>> loadEvents({
    required DateTime start,
    required DateTime end,
    List<String>? calendarIds,
  }) async {
    final results = <DeviceCalendarEvent>[];
    try {
      final calendars = calendarIds;
      final ids = calendars ?? (await loadCalendars()).map((c) => c.id).whereType<String>().toList();
      for (final id in ids) {
        final response = await _plugin.retrieveEvents(
          id,
          RetrieveEventsParams(
            startDate: start,
            endDate: end,
          ),
        );
        final data = response.data ?? <Event>[];
        for (final event in data) {
          if (event.start == null || event.end == null) continue;
          try {
            results.add(DeviceCalendarEvent.fromPlugin(event, id));
          } catch (_) {
            // Skip malformed events.
          }
        }
      }
    } catch (e) {
      print('DeviceCalendarService.loadEvents error: $e');
    }
    return results;
  }
}
