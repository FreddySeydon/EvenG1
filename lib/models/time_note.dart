enum TimeNoteRecurrence { once, weekly }

class TimeNote {
  final String id;
  final String title;
  final String content;
  final TimeNoteRecurrence recurrence;
  final DateTime? startDateTime; // Used for one-time notes
  final DateTime? endDateTime;   // Used for one-time notes
  final List<int> weekdays;      // 1 = Monday, 7 = Sunday for weekly recurrence
  final int startMinutes;        // Minutes from midnight (00:00)
  final int endMinutes;          // Minutes from midnight (00:00)

  const TimeNote({
    required this.id,
    required this.title,
    required this.content,
    required this.recurrence,
    required this.startMinutes,
    required this.endMinutes,
    this.startDateTime,
    this.endDateTime,
    this.weekdays = const [],
  });

  bool isActiveAt(DateTime now) {
    if (recurrence == TimeNoteRecurrence.once) {
      if (startDateTime == null || endDateTime == null) return false;
      return !now.isBefore(startDateTime!) && now.isBefore(endDateTime!);
    }

    // Weekly recurrence: match weekday and time window
    if (weekdays.isEmpty || !weekdays.contains(now.weekday)) return false;

    final minutesNow = now.hour * 60 + now.minute;
    // Assume same-day window; if end <= start, treat as inactive to avoid cross-midnight complexity
    if (endMinutes <= startMinutes) return false;
    return minutesNow >= startMinutes && minutesNow < endMinutes;
  }

  TimeNote copyWith({
    String? id,
    String? title,
    String? content,
    TimeNoteRecurrence? recurrence,
    DateTime? startDateTime,
    DateTime? endDateTime,
    List<int>? weekdays,
    int? startMinutes,
    int? endMinutes,
  }) {
    return TimeNote(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      recurrence: recurrence ?? this.recurrence,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
      weekdays: weekdays ?? List<int>.from(this.weekdays),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'recurrence': recurrence.name,
      'startDateTime': startDateTime?.toIso8601String(),
      'endDateTime': endDateTime?.toIso8601String(),
      'weekdays': weekdays,
      'startMinutes': startMinutes,
      'endMinutes': endMinutes,
    };
  }

  factory TimeNote.fromJson(Map<String, dynamic> json) {
    final recurrenceName = json['recurrence'] as String? ?? 'once';
    final startDateString = json['startDateTime'] as String?;
    final endDateString = json['endDateTime'] as String?;

    return TimeNote(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      recurrence: recurrenceName == 'weekly'
          ? TimeNoteRecurrence.weekly
          : TimeNoteRecurrence.once,
      startMinutes: (json['startMinutes'] as num?)?.toInt() ?? 0,
      endMinutes: (json['endMinutes'] as num?)?.toInt() ?? 0,
      startDateTime: startDateString != null ? DateTime.parse(startDateString) : null,
      endDateTime: endDateString != null ? DateTime.parse(endDateString) : null,
      weekdays: (json['weekdays'] as List<dynamic>? ?? []).map((e) => (e as num).toInt()).toList(),
    );
  }
}
