enum TimeNoteRecurrence { once, weekly }
enum TimeNoteType { timed, general }
enum TimeNoteEndAction { delete, archive }

class TimeNote {
  final String id;
  final String title;
  final String content;
  final TimeNoteType type;
  final TimeNoteRecurrence recurrence;
  final TimeNoteEndAction endAction;
  final int preOffsetMinutes; // Minutes before start to show
  final int postOffsetMinutes; // Minutes after end to keep showing
  final DateTime? startDateTime; // Used for one-time notes
  final DateTime? endDateTime; // Used for one-time notes
  final List<int> weekdays; // 1 = Monday, 7 = Sunday for weekly recurrence
  final int startMinutes; // Minutes from midnight (00:00)
  final int endMinutes; // Minutes from midnight (00:00)
  final String? calendarEventId; // Event identifier from device calendar
  final String? calendarId; // Calendar identifier
  final DateTime? calendarStart; // Cached event start time
  final DateTime? calendarEnd; // Cached event end time
  final String? calendarTitle;
  final String? calendarLocation;
  final bool attachToAllOccurrences; // For recurring calendar events
  final bool isRecurringEvent; // Flag from the calendar source
  final DateTime? archivedAt; // When set, treat as archived/past

  const TimeNote({
    required this.id,
    required this.title,
    required this.content,
    this.type = TimeNoteType.timed,
    required this.recurrence,
    this.endAction = TimeNoteEndAction.delete,
    this.preOffsetMinutes = 10,
    this.postOffsetMinutes = 10,
    required this.startMinutes,
    required this.endMinutes,
    this.startDateTime,
    this.endDateTime,
    this.weekdays = const [],
    this.calendarEventId,
    this.calendarId,
    this.calendarStart,
    this.calendarEnd,
    this.calendarTitle,
    this.calendarLocation,
    this.attachToAllOccurrences = false,
    this.isRecurringEvent = false,
    this.archivedAt,
  });

  bool get isCalendarLinked =>
      calendarEventId != null &&
      calendarEventId!.isNotEmpty &&
      calendarStart != null &&
      calendarEnd != null;

  bool isActiveAt(DateTime now) {
    final pre = preOffsetMinutes;
    final post = postOffsetMinutes;
    if (archivedAt != null) {
      return false;
    }

    if (isCalendarLinked) {
      final start = calendarStart;
      final end = calendarEnd;
      if (start == null || end == null) return false;
      final windowStart = start.subtract(Duration(minutes: pre));
      final windowEnd = end.add(Duration(minutes: post));
      return !now.isBefore(windowStart) && now.isBefore(windowEnd);
    }

    if (type == TimeNoteType.general) {
      return false;
    }

    if (recurrence == TimeNoteRecurrence.once) {
      if (startDateTime == null || endDateTime == null) return false;
      final windowStart = startDateTime!.subtract(Duration(minutes: pre));
      final windowEnd = endDateTime!.add(Duration(minutes: post));
      return !now.isBefore(windowStart) && now.isBefore(windowEnd);
    }

    // Weekly recurrence: match weekday and time window
    if (weekdays.isEmpty || !weekdays.contains(now.weekday)) return false;

    final minutesNow = now.hour * 60 + now.minute;
    // Assume same-day window; if end <= start, treat as inactive to avoid cross-midnight complexity
    if (endMinutes <= startMinutes) return false;
    final windowStart = ((startMinutes - pre).clamp(0, 24 * 60)).toInt();
    final windowEnd = ((endMinutes + post).clamp(0, 24 * 60)).toInt();
    return minutesNow >= windowStart && minutesNow < windowEnd;
  }

  TimeNote copyWith({
    String? id,
    String? title,
    String? content,
    TimeNoteType? type,
    TimeNoteRecurrence? recurrence,
    TimeNoteEndAction? endAction,
    int? preOffsetMinutes,
    int? postOffsetMinutes,
    DateTime? startDateTime,
    DateTime? endDateTime,
    List<int>? weekdays,
    int? startMinutes,
    int? endMinutes,
    String? calendarEventId,
    String? calendarId,
    DateTime? calendarStart,
    DateTime? calendarEnd,
    String? calendarTitle,
    String? calendarLocation,
    bool? attachToAllOccurrences,
    bool? isRecurringEvent,
    DateTime? archivedAt,
  }) {
    return TimeNote(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      type: type ?? this.type,
      recurrence: recurrence ?? this.recurrence,
      endAction: endAction ?? this.endAction,
      preOffsetMinutes: preOffsetMinutes ?? this.preOffsetMinutes,
      postOffsetMinutes: postOffsetMinutes ?? this.postOffsetMinutes,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
      weekdays: weekdays ?? List<int>.from(this.weekdays),
      calendarEventId: calendarEventId ?? this.calendarEventId,
      calendarId: calendarId ?? this.calendarId,
      calendarStart: calendarStart ?? this.calendarStart,
      calendarEnd: calendarEnd ?? this.calendarEnd,
      calendarTitle: calendarTitle ?? this.calendarTitle,
      calendarLocation: calendarLocation ?? this.calendarLocation,
      attachToAllOccurrences: attachToAllOccurrences ?? this.attachToAllOccurrences,
      isRecurringEvent: isRecurringEvent ?? this.isRecurringEvent,
      archivedAt: archivedAt ?? this.archivedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'type': type.name,
      'recurrence': recurrence.name,
      'endAction': endAction.name,
      'preOffsetMinutes': preOffsetMinutes,
      'postOffsetMinutes': postOffsetMinutes,
      'startDateTime': startDateTime?.toIso8601String(),
      'endDateTime': endDateTime?.toIso8601String(),
      'weekdays': weekdays,
      'startMinutes': startMinutes,
      'endMinutes': endMinutes,
      'calendarEventId': calendarEventId,
      'calendarId': calendarId,
      'calendarStart': calendarStart?.toIso8601String(),
      'calendarEnd': calendarEnd?.toIso8601String(),
      'calendarTitle': calendarTitle,
      'calendarLocation': calendarLocation,
      'attachToAllOccurrences': attachToAllOccurrences,
      'isRecurringEvent': isRecurringEvent,
      'archivedAt': archivedAt?.toIso8601String(),
    };
  }

  factory TimeNote.fromJson(Map<String, dynamic> json) {
    final recurrenceName = json['recurrence'] as String? ?? 'once';
    final typeName = json['type'] as String? ?? 'timed';
    final startDateString = json['startDateTime'] as String?;
    final endDateString = json['endDateTime'] as String?;
    final endActionName = json['endAction'] as String? ?? 'delete';
    final preOffset = (json['preOffsetMinutes'] as num?)?.toInt() ?? 10;
    final postOffset = (json['postOffsetMinutes'] as num?)?.toInt() ?? 10;

    return TimeNote(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      type: typeName == 'general' ? TimeNoteType.general : TimeNoteType.timed,
      recurrence: recurrenceName == 'weekly'
          ? TimeNoteRecurrence.weekly
          : TimeNoteRecurrence.once,
      endAction: endActionName == 'archive'
          ? TimeNoteEndAction.archive
          : TimeNoteEndAction.delete,
      preOffsetMinutes: preOffset,
      postOffsetMinutes: postOffset,
      startMinutes: (json['startMinutes'] as num?)?.toInt() ?? 0,
      endMinutes: (json['endMinutes'] as num?)?.toInt() ?? 0,
      startDateTime: startDateString != null ? DateTime.parse(startDateString) : null,
      endDateTime: endDateString != null ? DateTime.parse(endDateString) : null,
      weekdays: (json['weekdays'] as List<dynamic>? ?? []).map((e) => (e as num).toInt()).toList(),
      calendarEventId: json['calendarEventId'] as String?,
      calendarId: json['calendarId'] as String?,
      calendarStart: (json['calendarStart'] as String?) != null
          ? DateTime.tryParse(json['calendarStart'] as String)
          : null,
      calendarEnd: (json['calendarEnd'] as String?) != null
          ? DateTime.tryParse(json['calendarEnd'] as String)
          : null,
      calendarTitle: json['calendarTitle'] as String?,
      calendarLocation: json['calendarLocation'] as String?,
      attachToAllOccurrences: json['attachToAllOccurrences'] as bool? ?? false,
      isRecurringEvent: json['isRecurringEvent'] as bool? ?? false,
      archivedAt: (json['archivedAt'] as String?) != null
          ? DateTime.tryParse(json['archivedAt'] as String)
          : null,
    );
  }
}
