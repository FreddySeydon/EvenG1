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
  final bool isRecurring;

  const DeviceCalendarEvent({
    required this.id,
    required this.calendarId,
    required this.title,
    required this.start,
    required this.end,
    required this.location,
    required this.allDay,
    this.isRecurring = false,
  });

  factory DeviceCalendarEvent.fromPlugin(Event event, String calendarId) {
    final startDate = event.start;
    final endDate = event.end;
    final eventId = event.eventId;
    if (startDate == null || endDate == null || eventId == null || eventId.isEmpty) {
      throw ArgumentError('Event is missing start/end');
    }
    DateTime normalize(DateTime dt, bool isAllDay) {
      // Plugin can return UTC or a naive (offset=0) timestamp; convert to local wall time.
      final isNaiveUtc = !dt.isUtc &&
          dt.timeZoneOffset == Duration.zero &&
          DateTime.now().timeZoneOffset != Duration.zero;
      final local = dt.isUtc || isNaiveUtc
          ? DateTime.fromMillisecondsSinceEpoch(dt.millisecondsSinceEpoch, isUtc: true).toLocal()
          : dt;
      if (!isAllDay) return local;
      // Keep date for all-day events but strip any time-zone adjustment noise.
      return DateTime(local.year, local.month, local.day, local.hour, local.minute);
    }
    final allDayFlag = event.allDay ?? false;
    final recurringFlag = event.recurrenceRule != null;
    return DeviceCalendarEvent(
      id: eventId,
      calendarId: calendarId,
      title: event.title?.trim().isNotEmpty == true ? event.title!.trim() : 'Untitled event',
      start: normalize(startDate, allDayFlag),
      end: normalize(endDate, allDayFlag),
      location: event.location ?? '',
      allDay: allDayFlag,
      isRecurring: recurringFlag,
    );
  }

  bool isActiveAt(DateTime now) {
    return !now.isBefore(start) && now.isBefore(end);
  }
}
