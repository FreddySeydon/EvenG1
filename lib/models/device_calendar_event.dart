import 'package:device_calendar/device_calendar.dart';

/// Light wrapper around a device calendar event with only the fields we need
/// for scheduling and display.
class DeviceCalendarEvent {
  final String id;
  final String calendarId;
  final String title;
  final DateTime start;
  final DateTime end;
  final String location;
  final bool allDay;

  const DeviceCalendarEvent({
    required this.id,
    required this.calendarId,
    required this.title,
    required this.start,
    required this.end,
    required this.location,
    required this.allDay,
  });

  factory DeviceCalendarEvent.fromPlugin(Event event, String calendarId) {
    final startDate = event.start;
    final endDate = event.end;
    final eventId = event.eventId;
    if (startDate == null || endDate == null || eventId == null || eventId.isEmpty) {
      throw ArgumentError('Event is missing start/end');
    }
    return DeviceCalendarEvent(
      id: eventId,
      calendarId: calendarId,
      title: event.title?.trim().isNotEmpty == true ? event.title!.trim() : 'Untitled event',
      start: startDate,
      end: endDate,
      location: event.location ?? '',
      allDay: event.allDay ?? false,
    );
  }

  bool isActiveAt(DateTime now) {
    return !now.isBefore(start) && now.isBefore(end);
  }
}
