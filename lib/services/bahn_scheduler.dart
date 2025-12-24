import 'dart:async';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/bahn_controller.dart';
import '../models/bahn_journey.dart';
import '../services/bahn_service.dart';
import '../services/dashboard_note_service.dart';
import '../ble_manager.dart';

/// Background scheduler for Bahn addon
/// Handles smart refresh and automatic dashboard updates
class BahnScheduler extends GetxService {
  Timer? _mainTick;
  final Map<String, DateTime> _lastRefresh = {};
  final Map<String, String> _sentTokens = {}; // Track sent content to avoid duplicates

  @override
  void onInit() {
    super.onInit();
    print('[BahnScheduler] Starting scheduler');
    _startScheduler();
  }

  @override
  void onClose() {
    _stopScheduler();
    super.onClose();
  }

  void _startScheduler() {
    _mainTick = Timer.periodic(Duration(minutes: 1), (_) => _tick());
    // Also run immediately
    Future.delayed(Duration(seconds: 2), () => _tick());
  }

  void _stopScheduler() {
    _mainTick?.cancel();
    _mainTick = null;
    print('[BahnScheduler] Scheduler stopped');
  }

  Future<void> _tick() async {
    try {
      final controller = Get.find<BahnController>();
      final now = DateTime.now();

      final activeBookmarks = controller.activeBookmarks;

      if (activeBookmarks.isEmpty) {
        // No active bookmarks - nothing to do
        return;
      }

      print('[BahnScheduler] Tick: ${activeBookmarks.length} active bookmarks');

      for (final bookmark in activeBookmarks) {
        final shouldRefresh = _shouldRefresh(bookmark, now);

        if (shouldRefresh) {
          await _refreshAndSend(bookmark, now, controller);
        }
      }

      // Clean up completed journeys
      await _cleanupCompleted(controller, now);
    } catch (e) {
      print('[BahnScheduler] Error in tick: $e');
    }
  }

  bool _shouldRefresh(BookmarkedJourney bookmark, DateTime now) {
    final departure = bookmark.journey.plannedDeparture;
    final minutesUntilDeparture = departure.difference(now).inMinutes;
    final arrival = bookmark.journey.actualArrival;
    final isDuringTravel = now.isAfter(departure) && now.isBefore(arrival);

    // Refresh intervals based on time until departure
    Duration refreshInterval;
    if (minutesUntilDeparture > 120) {
      refreshInterval = Duration(minutes: 10); // >2h: every 10min
    } else if (minutesUntilDeparture > 30) {
      refreshInterval = Duration(minutes: 5); // 30min-2h: every 5min
    } else if (minutesUntilDeparture >= 0 || isDuringTravel) {
      refreshInterval = Duration(minutes: 2); // <30min or traveling: every 2min
    } else {
      return false; // After arrival: don't refresh
    }

    final lastRefresh = _lastRefresh[bookmark.id];
    if (lastRefresh == null) return true;

    final shouldRefresh = now.difference(lastRefresh) >= refreshInterval;

    if (shouldRefresh) {
      print('[BahnScheduler] Should refresh ${bookmark.id}: ${minutesUntilDeparture}min until departure');
    }

    return shouldRefresh;
  }

  Future<void> _refreshAndSend(
    BookmarkedJourney bookmark,
    DateTime now,
    BahnController controller,
  ) async {
    try {
      print('[BahnScheduler] Refreshing ${bookmark.id}');

      // Fetch real-time updates
      final updated = await BahnService.instance.getRealtimeInfo(bookmark.journey);

      // Update the controller's bookmark with fresh data
      await controller.updateBookmarkJourney(bookmark.id, updated);

      // Format for dashboard
      final title = _formatTitle(updated);
      final text = _formatForDashboard(updated);

      // Check if content changed (avoid redundant sends)
      final contentHash = (title + text).hashCode.toString();
      if (_sentTokens[bookmark.id] == contentHash) {
        _lastRefresh[bookmark.id] = now;
        print('[BahnScheduler] Content unchanged, skipping send');
        return; // Same content, skip send
      }

      // Send to dashboard slot
      if (BleManager.get().isConnected) {
        final success = await _sendToDashboard(
          title: title,
          text: text,
          slot: bookmark.dashboardSlot,
        );

        if (success) {
          _sentTokens[bookmark.id] = contentHash;
          _lastRefresh[bookmark.id] = now;
          print('[BahnScheduler] Sent to dashboard slot ${bookmark.dashboardSlot}');
        } else {
          print('[BahnScheduler] Failed to send to dashboard');
        }
      } else {
        print('[BahnScheduler] BLE not connected, skipping send');
      }
    } catch (e) {
      print('[BahnScheduler] Error refreshing ${bookmark.id}: $e');
    }
  }

  String _formatTitle(BahnJourney journey) {
    return journey.trainName;
  }

  String _formatForDashboard(BahnJourney journey) {
    final firstLeg = journey.legs.first;
    final lastLeg = journey.legs.last;

    // Format: "Dep: Berlin Hbf 14:30 Gl.7 +5"
    //         "Arr: München Hbf 18:45 Gl.3 +3"
    final depTime = _formatTime(firstLeg.effectiveDeparture);
    final depPlatform = firstLeg.platformDisplay;
    final depDelay = firstLeg.departureDelayText;

    final arrTime = _formatTime(lastLeg.effectiveArrival);
    final arrPlatform = lastLeg.platformDisplay;
    final arrDelay = lastLeg.arrivalDelayText;

    // Shorten station names if too long
    final depStation = _shortenStationName(firstLeg.origin.name);
    final arrStation = _shortenStationName(lastLeg.destination.name);

    final hasRealtime = _hasRealtimeData(journey);
    final delayReason = _getDelayReason(journey);
    final extraLine = hasRealtime
        ? (delayReason != null ? '\nDelay: $delayReason' : '')
        : '\nNo realtime data available';

    return 'Dep: $depStation $depTime Gl.$depPlatform $depDelay\n'
        'Arr: $arrStation $arrTime Gl.$arrPlatform $arrDelay'
        '$extraLine';
  }

  String _formatTime(DateTime dt) {
    return DateFormat('HH:mm').format(dt);
  }

  String _shortenStationName(String name) {
    // Remove common suffixes
    name = name.replaceAll(' Hbf', '').replaceAll(' (Saale)', '');
    name = name.replaceAll(' Bahnhof', '');

    // If still too long, truncate
    if (name.length > 15) {
      return name.substring(0, 15);
    }
    return name;
  }

  bool _hasRealtimeData(BahnJourney journey) {
    final isFlix = _isFlixJourney(journey);
    for (final leg in journey.legs) {
      final hasDelay =
          leg.departureDelay != null || leg.arrivalDelay != null;
      final hasPlatform = leg.actualPlatform != null;
      final hasRealtimeNote = leg.realtimeNote != null;
      final hasTimeDiff =
          (leg.actualDeparture != null &&
              leg.actualDeparture != leg.plannedDeparture) ||
          (leg.actualArrival != null &&
              leg.actualArrival != leg.plannedArrival);
      final hasFlixActual = isFlix &&
          (leg.actualDeparture != null || leg.actualArrival != null);

      if (hasDelay || hasPlatform || hasRealtimeNote || hasTimeDiff || hasFlixActual) {
        return true;
      }
    }
    return false;
  }

  bool _isFlixJourney(BahnJourney journey) {
    final firstLeg = journey.legs.first;
    final lineProduct = firstLeg.lineProduct.toUpperCase();
    final lineName = firstLeg.lineName.toUpperCase();
    return journey.id.startsWith('flix_') ||
        lineProduct == 'FLX' ||
        lineName.startsWith('FLX');
  }

  String? _getDelayReason(BahnJourney journey) {
    for (final leg in journey.legs) {
      if (leg.realtimeNote != null && leg.realtimeNote!.trim().isNotEmpty) {
        return leg.realtimeNote!.trim();
      }
    }
    return null;
  }

  Future<bool> _sendToDashboard({
    required String title,
    required String text,
    required int slot,
  }) async {
    try {
      return await DashboardNoteService.instance.sendDashboardNote(
        title: title,
        text: text,
        noteNumber: slot,
      );
    } catch (e) {
      print('[BahnScheduler] Error sending to dashboard: $e');
      return false;
    }
  }

  Future<void> _cleanupCompleted(BahnController controller, DateTime now) async {
    final completed = controller.bookmarkedJourneys
        .where((b) => b.isCompleted(now))
        .toList();

    for (final bookmark in completed) {
      print('[BahnScheduler] Cleaning up completed journey: ${bookmark.id}');

      // Clear dashboard slot
      if (BleManager.get().isConnected) {
        try {
          await DashboardNoteService.instance.clearNote(
            noteNumber: bookmark.dashboardSlot,
          );
          print('[BahnScheduler] Cleared dashboard slot ${bookmark.dashboardSlot}');
        } catch (e) {
          print('[BahnScheduler] Error clearing slot: $e');
        }
      }

      // Remove from bookmarks
      await controller.removeBookmark(bookmark.id);

      // Clean up tracking maps
      _lastRefresh.remove(bookmark.id);
      _sentTokens.remove(bookmark.id);
    }

    if (completed.isNotEmpty) {
      print('[BahnScheduler] Cleaned up ${completed.length} completed journeys');
    }
  }

  /// Manual trigger for immediate refresh (for testing)
  Future<void> forceRefresh() async {
    print('[BahnScheduler] Force refresh triggered');
    await _tick();
  }
}
