import 'dart:async';
import 'package:dio/dio.dart';
import '../models/bahn_journey.dart';
import '../services/iris_service.dart';

/// Service for interacting with the db-rest API (Deutsche Bahn)
/// API Documentation: https://v6.db.transport.rest/
class BahnService {
  static const String _baseUrl = 'https://v6.db.transport.rest';

  late Dio _dio;

  static BahnService? _instance;
  static BahnService get instance => _instance ??= BahnService._();

  BahnService._() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      headers: {'Content-Type': 'application/json'},
      receiveTimeout: Duration(seconds: 20),
      sendTimeout: Duration(seconds: 10),
      validateStatus: (status) => status != null && status < 500,
    ));

    print('[BahnService] Initialized with base URL: $_baseUrl');
  }

  /// Search for stations by name
  /// Returns list of stations matching the query
  Future<List<BahnStation>> searchStations(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }

    try {
      print('[BahnService] Searching stations: "$query"');

      final response = await _dio.get(
        '/locations',
        queryParameters: {
          'query': query.trim(),
          'poi': 'false',
          'addresses': 'false',
          'results': '10',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> results = response.data as List<dynamic>;
        final stations = results
            .where((item) => item['type'] == 'stop' || item['type'] == 'station')
            .map((item) => BahnStation.fromJson(item))
            .toList();

        print('[BahnService] Found ${stations.length} stations');
        return stations;
      } else if (response.statusCode == 429) {
        print('[BahnService] Rate limit exceeded (429)');
        throw BahnServiceException(
          'Too many requests. Please wait a moment and try again.',
          type: BahnErrorType.rateLimit,
        );
      } else {
        print('[BahnService] Station search failed: ${response.statusCode}');
        throw BahnServiceException(
          'Failed to search stations. Status: ${response.statusCode}',
          type: BahnErrorType.apiError,
        );
      }
    } on DioException catch (e) {
      print('[BahnService] Network error during station search: $e');
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw BahnServiceException(
          'Request timed out. Check your internet connection.',
          type: BahnErrorType.timeout,
        );
      } else if (e.type == DioExceptionType.connectionError) {
        throw BahnServiceException(
          'No internet connection. Please check your network.',
          type: BahnErrorType.network,
        );
      } else {
        throw BahnServiceException(
          'Network error: ${e.message}',
          type: BahnErrorType.network,
        );
      }
    } catch (e) {
      print('[BahnService] Unexpected error during station search: $e');
      throw BahnServiceException(
        'Unexpected error: $e',
        type: BahnErrorType.unknown,
      );
    }
  }

  /// Find journeys from one station to another
  /// Returns list of journey options
  Future<List<BahnJourney>> findJourneys({
    required String fromStationId,
    required String toStationId,
    required DateTime departure,
    int results = 6,
  }) async {
    try {
      print('[BahnService] Finding journeys: $fromStationId -> $toStationId at ${departure.toIso8601String()}');

      final response = await _dio.get(
        '/journeys',
        queryParameters: {
          'from': fromStationId,
          'to': toStationId,
          'departure': departure.toIso8601String(),
          'results': results.toString(),
        },
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final List<dynamic> journeysList = data['journeys'] as List<dynamic>? ?? [];

        final journeys = journeysList
            .map((item) {
              try {
                return BahnJourney.fromJson(item as Map<String, dynamic>);
              } catch (e) {
                print('[BahnService] Failed to parse journey: $e');
                return null;
              }
            })
            .where((j) => j != null)
            .cast<BahnJourney>()
            .toList();

        print('[BahnService] Found ${journeys.length} journeys');
        return journeys;
      } else if (response.statusCode == 429) {
        print('[BahnService] Rate limit exceeded (429)');
        throw BahnServiceException(
          'Too many requests. Please wait a moment and try again.',
          type: BahnErrorType.rateLimit,
        );
      } else if (response.statusCode == 404) {
        print('[BahnService] No journeys found (404)');
        return []; // Return empty list instead of throwing
      } else {
        print('[BahnService] Journey search failed: ${response.statusCode}');
        throw BahnServiceException(
          'Failed to find journeys. Status: ${response.statusCode}',
          type: BahnErrorType.apiError,
        );
      }
    } on DioException catch (e) {
      print('[BahnService] Network error during journey search: $e');
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw BahnServiceException(
          'Request timed out. Check your internet connection.',
          type: BahnErrorType.timeout,
        );
      } else if (e.type == DioExceptionType.connectionError) {
        throw BahnServiceException(
          'No internet connection. Please check your network.',
          type: BahnErrorType.network,
        );
      } else {
        throw BahnServiceException(
          'Network error: ${e.message}',
          type: BahnErrorType.network,
        );
      }
    } catch (e) {
      if (e is BahnServiceException) rethrow;
      print('[BahnService] Unexpected error during journey search: $e');
      throw BahnServiceException(
        'Unexpected error: $e',
        type: BahnErrorType.unknown,
      );
    }
  }

  /// Get real-time updates for a specific journey
  /// This re-fetches journey data to get latest delays and platform changes
  Future<BahnJourney> getRealtimeInfo(BahnJourney journey) async {
    try {
      if (_isFlixJourney(journey)) {
        return _getFlixRealtimeInfo(journey);
      }

      print('[BahnService] Fetching real-time info for journey: ${journey.id}');

      // Re-search for journeys around the same time to get updated info
      final updatedJourneys = await findJourneys(
        fromStationId: journey.origin.id,
        toStationId: journey.destination.id,
        departure: journey.plannedDeparture.subtract(Duration(minutes: 5)),
        results: 10,
      );

      // Try to find the same journey by matching trip IDs
      for (final updated in updatedJourneys) {
        // Match if first leg's tripId matches
        if (updated.legs.isNotEmpty &&
            journey.legs.isNotEmpty &&
            updated.legs.first.tripId == journey.legs.first.tripId) {
          print('[BahnService] Found updated journey with matching tripId');
          return updated;
        }

        // Fallback: match by departure time (within 2 minutes)
        final timeDiff = updated.plannedDeparture
            .difference(journey.plannedDeparture)
            .abs();
        if (timeDiff.inMinutes <= 2 && updated.trainName == journey.trainName) {
          print('[BahnService] Found updated journey by time/train match');
          return updated;
        }
      }

      // If no exact match found, return the original journey
      print('[BahnService] No matching updated journey found, returning original');
      return journey;
    } catch (e) {
      print('[BahnService] Error fetching real-time info: $e');
      // On error, return the original journey (graceful degradation)
      return journey;
    }
  }

  bool _isFlixJourney(BahnJourney journey) {
    final firstLeg = journey.legs.first;
    final lineProduct = firstLeg.lineProduct.toUpperCase();
    final lineName = firstLeg.lineName.toUpperCase();
    return journey.id.startsWith('flix_') ||
        lineProduct == 'FLX' ||
        lineName.startsWith('FLX');
  }

  Future<BahnJourney> _getFlixRealtimeInfo(BahnJourney journey) async {
    try {
      if (journey.origin.id.isEmpty) {
        return journey;
      }

      final referenceTime = journey.plannedDeparture.subtract(Duration(hours: 1));
      final flixJourneys = await IrisService.instance.getFlixTrainDepartures(
        evaNumber: journey.origin.id,
        departureTime: referenceTime,
      );

      BahnJourney? match;
      final tripId = journey.legs.first.tripId;
      if (tripId.isNotEmpty) {
        for (final candidate in flixJourneys) {
          if (candidate.legs.first.tripId == tripId) {
            match = candidate;
            break;
          }
        }
      }

      if (match == null) {
        final targetTime = journey.plannedDeparture;
        for (final candidate in flixJourneys) {
          final lineMatch = candidate.trainName == journey.trainName;
          final diff = candidate.plannedDeparture.difference(targetTime).abs();
          if (lineMatch && diff.inMinutes <= 5) {
            match = candidate;
            break;
          }
        }
      }

      if (match == null) {
        return journey;
      }

      final originalLeg = journey.legs.first;
      final matchLeg = match.legs.first;

      final mergedLeg = BahnLeg(
        tripId: originalLeg.tripId,
        lineName: originalLeg.lineName,
        lineProduct: originalLeg.lineProduct,
        direction: matchLeg.direction.isNotEmpty ? matchLeg.direction : originalLeg.direction,
        origin: originalLeg.origin,
        destination: originalLeg.destination,
        plannedDeparture: originalLeg.plannedDeparture,
        actualDeparture: matchLeg.actualDeparture,
        plannedArrival: originalLeg.plannedArrival,
        actualArrival: matchLeg.actualArrival ?? originalLeg.actualArrival,
        plannedPlatform: matchLeg.plannedPlatform ?? originalLeg.plannedPlatform,
        actualPlatform: matchLeg.actualPlatform ?? originalLeg.actualPlatform,
        departureDelay: matchLeg.departureDelay,
        arrivalDelay: matchLeg.arrivalDelay ?? originalLeg.arrivalDelay,
        stops: matchLeg.stops.isNotEmpty ? matchLeg.stops : originalLeg.stops,
        realtimeNote: matchLeg.realtimeNote ?? originalLeg.realtimeNote,
      );

      return BahnJourney(
        id: journey.id,
        legs: [mergedLeg],
        plannedDeparture: journey.plannedDeparture,
        plannedArrival: journey.plannedArrival,
        duration: journey.duration,
        changes: journey.changes,
      );
    } catch (e) {
      print('[BahnService] Flix real-time fetch error: $e');
      return journey;
    }
  }

  /// Get departures from a specific station
  /// Useful for checking real-time status of a specific train
  Future<List<Map<String, dynamic>>> getDepartures({
    required String stationId,
    DateTime? when,
    int results = 20,
  }) async {
    try {
      print('[BahnService] Getting departures for station: $stationId');

      final response = await _dio.get(
        '/stops/$stationId/departures',
        queryParameters: {
          if (when != null) 'when': when.toIso8601String(),
          'results': results.toString(),
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> departures = response.data as List<dynamic>;
        print('[BahnService] Found ${departures.length} departures');
        return departures.cast<Map<String, dynamic>>();
      } else {
        print('[BahnService] Failed to get departures: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('[BahnService] Error getting departures: $e');
      return [];
    }
  }
}

/// Custom exception for Bahn service errors
class BahnServiceException implements Exception {
  final String message;
  final BahnErrorType type;

  BahnServiceException(this.message, {required this.type});

  @override
  String toString() => 'BahnServiceException: $message';
}

/// Types of errors that can occur
enum BahnErrorType {
  network,
  timeout,
  rateLimit,
  apiError,
  parseError,
  unknown,
}
