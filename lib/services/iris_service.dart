import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import '../models/bahn_journey.dart';

/// Service for fetching FlixTrain data from IRIS API
/// IRIS only provides station boards, not full journey planning
class IrisService {
  static final IrisService instance = IrisService._internal();
  factory IrisService() => instance;
  IrisService._internal();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://iris.noncd.db.de/iris-tts',
    connectTimeout: Duration(seconds: 10),
    receiveTimeout: Duration(seconds: 15),
  ));

  /// Get FlixTrain departures from a station
  /// Returns list of FlixTrain journeys departing within the next 12 hours
  Future<List<BahnJourney>> getFlixTrainDepartures({
    required String evaNumber,
    required DateTime departureTime,
  }) async {
    try {
      print('[IrisService] Fetching FlixTrains from EVA $evaNumber at $departureTime');

      final journeys = <BahnJourney>[];

      // Fetch current hour and next 11 hours to cover 12-hour window
      for (int hourOffset = 0; hourOffset < 12; hourOffset++) {
        final queryTime = departureTime.add(Duration(hours: hourOffset));
        final dateStr = _formatDate(queryTime); // YYMMDD
        final hourStr = _formatHour(queryTime); // HH

        try {
          final response = await _dio.get(
            '/timetable/plan/$evaNumber/$dateStr/$hourStr',
          );

          if (response.statusCode == 200) {
            final flixJourneys = _parseFlixTrainsFromXml(response.data, departureTime);
            journeys.addAll(flixJourneys);
          }
        } catch (e) {
          print('[IrisService] Failed to fetch hour $hourOffset: $e');
          // Continue to next hour
        }
      }

      print('[IrisService] Found ${journeys.length} FlixTrain departures');
      return journeys;
    } catch (e) {
      print('[IrisService] Error fetching FlixTrains: $e');
      return [];
    }
  }

  /// Parse FlixTrain entries from IRIS XML
  List<BahnJourney> _parseFlixTrainsFromXml(String xmlData, DateTime referenceTime) {
    try {
      final document = XmlDocument.parse(xmlData);
      final stops = document.findAllElements('s');

      final journeys = <BahnJourney>[];

      for (final stop in stops) {
        try {
          // Check if this is a FlixTrain (c="FLX")
          final tl = stop.findElements('tl').firstOrNull;
          if (tl == null) continue;

          final category = tl.getAttribute('c');
          if (category != 'FLX') continue; // Only FlixTrains

          // Get departure info
          final dp = stop.findElements('dp').firstOrNull;
          if (dp == null) continue; // Only interested in departures

          final plannedTime = _parseTime(dp.getAttribute('pt') ?? '');
          final actualTime = _parseTime(dp.getAttribute('ct') ?? '');
          if (plannedTime == null) continue;

          // Skip if departure is in the past or more than 12 hours away
          final diff = plannedTime.difference(referenceTime);
          if (diff.isNegative || diff.inHours > 12) continue;

          final platform = dp.getAttribute('pp') ?? '?';
          final actualPlatform = dp.getAttribute('cp');
          final rawLineName = tl.getAttribute('fb') ?? dp.getAttribute('l') ?? 'FlixTrain';
          final lineName = rawLineName.startsWith('FLX') ? rawLineName : 'FLX $rawLineName';
          final tripId = stop.getAttribute('id') ?? '';

          // Get path (stations)
          final pathAttr = dp.getAttribute('ppth') ?? '';
          final stations = pathAttr.split('|').where((s) => s.isNotEmpty).toList();

          if (stations.isEmpty) continue; // No destination info

          // Create a simplified journey with single leg
          // We don't have full journey details, just departure info
          final leg = BahnLeg(
            tripId: tripId,
            lineName: lineName,
            lineProduct: 'FLX',
            direction: stations.last,
            origin: BahnStation(id: '', name: ''), // Will be filled by caller
            destination: BahnStation(id: '', name: stations.last),
            plannedDeparture: plannedTime,
            actualDeparture: actualTime,
            plannedArrival: plannedTime.add(Duration(hours: 2)), // Estimate
            actualArrival: null,
            plannedPlatform: platform,
            actualPlatform: actualPlatform,
            departureDelay: _calculateDelaySeconds(plannedTime, actualTime),
            arrivalDelay: null,
            stops: stations,
          );

          final journey = BahnJourney(
            id: 'flix_$tripId',
            legs: [leg],
            plannedDeparture: plannedTime,
            plannedArrival: plannedTime.add(Duration(hours: 2)), // Estimate
            duration: Duration(hours: 2), // Estimate
            changes: 0,
          );

          journeys.add(journey);
        } catch (e) {
          print('[IrisService] Error parsing FlixTrain stop: $e');
          continue;
        }
      }

      return journeys;
    } catch (e) {
      print('[IrisService] Error parsing XML: $e');
      return [];
    }
  }

  /// Parse IRIS time format (YYMMDDHHMM) to DateTime
  DateTime? _parseTime(String irisTime) {
    try {
      // IRIS usually returns YYMMDDHHMM (10 digits). Some feeds include seconds (12 digits).
      if (irisTime.length != 10 && irisTime.length != 12) return null;

      final year = 2000 + int.parse(irisTime.substring(0, 2));
      final month = int.parse(irisTime.substring(2, 4));
      final day = int.parse(irisTime.substring(4, 6));
      final hour = int.parse(irisTime.substring(6, 8));
      final minute = int.parse(irisTime.substring(8, 10));

      return DateTime(year, month, day, hour, minute);
    } catch (e) {
      return null;
    }
  }

  int? _calculateDelaySeconds(DateTime? planned, DateTime? actual) {
    if (planned == null || actual == null) return null;
    return actual.difference(planned).inSeconds;
  }

  /// Format DateTime to YYMMDD
  String _formatDate(DateTime dt) {
    final year = (dt.year % 100).toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$year$month$day';
  }

  /// Format DateTime to HH
  String _formatHour(DateTime dt) {
    return dt.hour.toString().padLeft(2, '0');
  }
}
