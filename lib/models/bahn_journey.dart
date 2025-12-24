import 'package:flutter/foundation.dart';

/// Represents a train station
class BahnStation {
  final String id;
  final String name;
  final double? latitude;
  final double? longitude;

  const BahnStation({
    required this.id,
    required this.name,
    this.latitude,
    this.longitude,
  });

  factory BahnStation.fromJson(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>?;
    return BahnStation(
      id: json['id'] as String,
      name: json['name'] as String,
      latitude: location?['latitude'] as double?,
      longitude: location?['longitude'] as double?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (latitude != null && longitude != null)
          'location': {
            'latitude': latitude,
            'longitude': longitude,
          },
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BahnStation &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Represents a single leg of a journey (one train)
class BahnLeg {
  final String tripId;
  final String lineName;
  final String lineProduct;
  final String direction;
  final BahnStation origin;
  final BahnStation destination;
  final DateTime plannedDeparture;
  final DateTime? actualDeparture;
  final DateTime plannedArrival;
  final DateTime? actualArrival;
  final String? plannedPlatform;
  final String? actualPlatform;
  final int? departureDelay; // In seconds
  final int? arrivalDelay; // In seconds
  final List<String> stops;
  final String? realtimeNote;

  const BahnLeg({
    required this.tripId,
    required this.lineName,
    required this.lineProduct,
    required this.direction,
    required this.origin,
    required this.destination,
    required this.plannedDeparture,
    this.actualDeparture,
    required this.plannedArrival,
    this.actualArrival,
    this.plannedPlatform,
    this.actualPlatform,
    this.departureDelay,
    this.arrivalDelay,
    this.stops = const [],
    this.realtimeNote,
  });

  factory BahnLeg.fromJson(Map<String, dynamic> json) {
    final line = json['line'] as Map<String, dynamic>?;
    final remarks = json['remarks'] as List<dynamic>?;

    return BahnLeg(
      tripId: json['tripId'] as String,
      lineName: line?['name'] as String? ?? 'Unknown',
      lineProduct: line?['product'] as String? ?? 'train',
      direction: json['direction'] as String? ?? '',
      origin: BahnStation.fromJson(json['origin'] as Map<String, dynamic>),
      destination: BahnStation.fromJson(json['destination'] as Map<String, dynamic>),
      plannedDeparture: DateTime.parse(json['plannedDeparture'] as String),
      actualDeparture: json['departure'] != null
          ? DateTime.parse(json['departure'] as String)
          : null,
      plannedArrival: DateTime.parse(json['plannedArrival'] as String),
      actualArrival: json['arrival'] != null
          ? DateTime.parse(json['arrival'] as String)
          : null,
      plannedPlatform: json['plannedPlatform'] as String?,
      actualPlatform: json['platform'] as String?,
      departureDelay: json['departureDelay'] as int?,
      arrivalDelay: json['arrivalDelay'] as int?,
      stops: (json['stops'] as List<dynamic>?)
              ?.map((stop) => stop.toString())
              .toList() ??
          const [],
      realtimeNote: _extractRealtimeNote(remarks),
    );
  }

  Map<String, dynamic> toJson() => {
        'tripId': tripId,
        'line': {
          'name': lineName,
          'product': lineProduct,
        },
        'direction': direction,
        'origin': origin.toJson(),
        'destination': destination.toJson(),
        'plannedDeparture': plannedDeparture.toIso8601String(),
        if (actualDeparture != null)
          'departure': actualDeparture!.toIso8601String(),
        'plannedArrival': plannedArrival.toIso8601String(),
        if (actualArrival != null) 'arrival': actualArrival!.toIso8601String(),
        if (plannedPlatform != null) 'plannedPlatform': plannedPlatform,
        if (actualPlatform != null) 'platform': actualPlatform,
        if (departureDelay != null) 'departureDelay': departureDelay,
        if (arrivalDelay != null) 'arrivalDelay': arrivalDelay,
        if (stops.isNotEmpty) 'stops': stops,
        if (realtimeNote != null) 'realtimeNote': realtimeNote,
      };

  // Computed properties
  String get departureDelayText {
    if (departureDelay == null || departureDelay == 0) return '';
    final minutes = (departureDelay! / 60).round();
    return minutes > 0 ? '+$minutes' : '';
  }

  String get arrivalDelayText {
    if (arrivalDelay == null || arrivalDelay == 0) return '';
    final minutes = (arrivalDelay! / 60).round();
    return minutes > 0 ? '+$minutes' : '';
  }

  String get platformDisplay {
    return actualPlatform ?? plannedPlatform ?? '?';
  }

  DateTime get effectiveDeparture {
    return actualDeparture ?? plannedDeparture;
  }

  DateTime get effectiveArrival {
    return actualArrival ?? plannedArrival;
  }

  static String? _extractRealtimeNote(List<dynamic>? remarks) {
    if (remarks == null || remarks.isEmpty) return null;

    for (final remark in remarks) {
      if (remark is! Map) continue;

      final type = (remark['type'] as String?)?.toLowerCase();
      if (type == 'hint') continue;

      final code = (remark['code'] as String?)?.toLowerCase();
      final summary = (remark['summary'] as String?)?.trim();
      final text = (remark['text'] as String?)?.trim();
      final candidate = summary?.isNotEmpty == true ? summary : text;
      if (candidate == null || candidate.isEmpty) continue;

      final lower = candidate.toLowerCase();
      final looksLikeDelay = lower.contains('delay') ||
          lower.contains('delayed') ||
          lower.contains('versp') ||
          (code?.contains('delay') ?? false) ||
          (code?.contains('late') ?? false);

      if (looksLikeDelay || type == 'warning') {
        return candidate;
      }
    }

    return null;
  }
}

/// Represents a complete journey (may have multiple legs)
class BahnJourney {
  final String id;
  final List<BahnLeg> legs;
  final DateTime plannedDeparture;
  final DateTime plannedArrival;
  final Duration duration;
  final int changes;

  const BahnJourney({
    required this.id,
    required this.legs,
    required this.plannedDeparture,
    required this.plannedArrival,
    required this.duration,
    required this.changes,
  });

  factory BahnJourney.fromJson(Map<String, dynamic> json) {
    final legsList = json['legs'] as List<dynamic>? ?? [];
    final legs = legsList
        .where((e) => e['walking'] != true) // Filter out walking legs
        .map((e) => BahnLeg.fromJson(e as Map<String, dynamic>))
        .toList();

    if (legs.isEmpty) {
      throw ArgumentError('Journey must have at least one non-walking leg');
    }

    final plannedDeparture = legs.first.plannedDeparture;
    final plannedArrival = legs.last.plannedArrival;
    final duration = plannedArrival.difference(plannedDeparture);
    final changes = legs.length - 1; // Number of transfers

    return BahnJourney(
      id: json['id'] as String? ??
          '${plannedDeparture.millisecondsSinceEpoch}',
      legs: legs,
      plannedDeparture: plannedDeparture,
      plannedArrival: plannedArrival,
      duration: duration,
      changes: changes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'legs': legs.map((l) => l.toJson()).toList(),
        'plannedDeparture': plannedDeparture.toIso8601String(),
        'plannedArrival': plannedArrival.toIso8601String(),
        'durationSeconds': duration.inSeconds,
        'changes': changes,
      };

  // Computed properties
  BahnStation get origin => legs.first.origin;
  BahnStation get destination => legs.last.destination;

  DateTime get actualDeparture =>
      legs.first.actualDeparture ?? plannedDeparture;
  DateTime get actualArrival => legs.last.actualArrival ?? plannedArrival;

  int get totalDepartureDelay => legs.first.departureDelay ?? 0;
  int get totalArrivalDelay => legs.last.arrivalDelay ?? 0;

  String get trainName => legs.first.lineName;

  /// Get a summary of all trains taken (e.g., "ICE 123, RE 456")
  String get allTrains => legs.map((l) => l.lineName).join(', ');
}

/// Display timing options for dashboard notes
enum BahnDisplayTiming {
  wholeDay,
  oneHour,
  twoHours,
  thirtyMin;

  String get label {
    switch (this) {
      case BahnDisplayTiming.wholeDay:
        return 'Whole day';
      case BahnDisplayTiming.oneHour:
        return '1 hour before';
      case BahnDisplayTiming.twoHours:
        return '2 hours before';
      case BahnDisplayTiming.thirtyMin:
        return '30 min before';
    }
  }

  Duration get offsetDuration {
    switch (this) {
      case BahnDisplayTiming.wholeDay:
        return Duration(days: 1);
      case BahnDisplayTiming.oneHour:
        return Duration(hours: 1);
      case BahnDisplayTiming.twoHours:
        return Duration(hours: 2);
      case BahnDisplayTiming.thirtyMin:
        return Duration(minutes: 30);
    }
  }

  static BahnDisplayTiming fromString(String value) {
    return BahnDisplayTiming.values.firstWhere(
      (e) => e.name == value,
      orElse: () => BahnDisplayTiming.twoHours,
    );
  }
}

/// A bookmarked journey with display preferences
class BookmarkedJourney {
  final String id;
  final BahnJourney journey;
  final DateTime travelDate;
  final int dashboardSlot;
  final BahnDisplayTiming displayTiming;
  final DateTime bookmarkedAt;

  const BookmarkedJourney({
    required this.id,
    required this.journey,
    required this.travelDate,
    required this.dashboardSlot,
    required this.displayTiming,
    required this.bookmarkedAt,
  });

  factory BookmarkedJourney.fromJson(Map<String, dynamic> json) {
    return BookmarkedJourney(
      id: json['id'] as String,
      journey: BahnJourney.fromJson(json['journey'] as Map<String, dynamic>),
      travelDate: DateTime.parse(json['travelDate'] as String),
      dashboardSlot: json['dashboardSlot'] as int,
      displayTiming: BahnDisplayTiming.fromString(json['displayTiming'] as String),
      bookmarkedAt: DateTime.parse(json['bookmarkedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'journey': journey.toJson(),
        'travelDate': travelDate.toIso8601String(),
        'dashboardSlot': dashboardSlot,
        'displayTiming': displayTiming.name,
        'bookmarkedAt': bookmarkedAt.toIso8601String(),
      };

  // Computed: when to start showing on dashboard
  DateTime get displayStartTime {
    if (displayTiming == BahnDisplayTiming.wholeDay) {
      // Show from midnight on travel day
      return DateTime(travelDate.year, travelDate.month, travelDate.day);
    }
    return journey.plannedDeparture.subtract(displayTiming.offsetDuration);
  }

  // Computed: when to stop showing
  DateTime get displayEndTime {
    return journey.actualArrival;
  }

  // Computed: is this bookmark active now?
  bool isActiveNow(DateTime now) {
    return now.isAfter(displayStartTime) &&
        now.isBefore(displayEndTime.add(Duration(minutes: 5))); // 5min grace period after arrival
  }

  // Computed: has this journey already finished?
  bool isCompleted(DateTime now) {
    return now.isAfter(displayEndTime.add(Duration(hours: 1))); // 1h after arrival
  }

  // Computed: is this bookmark upcoming (not yet active)?
  bool isUpcoming(DateTime now) {
    return now.isBefore(displayStartTime);
  }

  // Create a copy with updated journey (for real-time updates)
  BookmarkedJourney copyWithJourney(BahnJourney updatedJourney) {
    return BookmarkedJourney(
      id: id,
      journey: updatedJourney,
      travelDate: travelDate,
      dashboardSlot: dashboardSlot,
      displayTiming: displayTiming,
      bookmarkedAt: bookmarkedAt,
    );
  }

  // Create a copy with updated settings
  BookmarkedJourney copyWithSettings({
    int? dashboardSlot,
    BahnDisplayTiming? displayTiming,
  }) {
    return BookmarkedJourney(
      id: id,
      journey: journey,
      travelDate: travelDate,
      dashboardSlot: dashboardSlot ?? this.dashboardSlot,
      displayTiming: displayTiming ?? this.displayTiming,
      bookmarkedAt: bookmarkedAt,
    );
  }
}
