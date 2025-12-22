import 'dart:async';
import 'dart:convert';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/bahn_journey.dart';
import '../services/bahn_service.dart';

class BahnController extends GetxController {
  final BahnService _bahnService = BahnService.instance;
  final Uuid _uuid = Uuid();

  // Search state
  var isSearching = false.obs;
  var searchResults = <BahnJourney>[].obs;
  var searchError = Rxn<String>();
  var stationSearchResults = <BahnStation>[].obs;
  var selectedFromStation = Rxn<BahnStation>();
  var selectedToStation = Rxn<BahnStation>();
  var isSearchingStations = false.obs;

  // Bookmark state
  var bookmarkedJourneys = <BookmarkedJourney>[].obs;

  // Preferences
  var defaultSlot = 2.obs; // Default to slot 2
  var defaultTiming = BahnDisplayTiming.twoHours.obs;

  // SharedPreferences keys
  static const String _prefKeyBookmarks = 'bahn_bookmarks';
  static const String _prefKeyDefaultSlot = 'bahn_default_slot';
  static const String _prefKeyDefaultTiming = 'bahn_default_timing';

  @override
  void onInit() {
    super.onInit();
    _loadPreferences();
    _loadBookmarks();
  }

  /// Load user preferences
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final savedSlot = prefs.getInt(_prefKeyDefaultSlot);
      if (savedSlot != null && savedSlot >= 1 && savedSlot <= 4) {
        defaultSlot.value = savedSlot;
        print('[BahnController] Loaded default slot: $savedSlot');
      }

      final savedTiming = prefs.getString(_prefKeyDefaultTiming);
      if (savedTiming != null) {
        defaultTiming.value = BahnDisplayTiming.fromString(savedTiming);
        print('[BahnController] Loaded default timing: $savedTiming');
      }
    } catch (e) {
      print('[BahnController] Error loading preferences: $e');
    }
  }

  /// Save user preferences
  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefKeyDefaultSlot, defaultSlot.value);
      await prefs.setString(_prefKeyDefaultTiming, defaultTiming.value.name);
      print('[BahnController] Saved preferences');
    } catch (e) {
      print('[BahnController] Error saving preferences: $e');
    }
  }

  /// Update default slot
  Future<void> setDefaultSlot(int slot) async {
    if (slot < 1 || slot > 4) {
      print('[BahnController] Invalid slot: $slot');
      return;
    }
    defaultSlot.value = slot;
    await _savePreferences();
  }

  /// Update default timing
  Future<void> setDefaultTiming(BahnDisplayTiming timing) async {
    defaultTiming.value = timing;
    await _savePreferences();
  }

  /// Load bookmarks from storage
  Future<void> _loadBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_prefKeyBookmarks);

      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> jsonList = json.decode(jsonString);
        final bookmarks = jsonList
            .map((item) {
              try {
                return BookmarkedJourney.fromJson(item as Map<String, dynamic>);
              } catch (e) {
                print('[BahnController] Failed to parse bookmark: $e');
                return null;
              }
            })
            .where((b) => b != null)
            .cast<BookmarkedJourney>()
            .toList();

        bookmarkedJourneys.value = bookmarks;
        print('[BahnController] Loaded ${bookmarks.length} bookmarks');

        // Clean up old completed journeys
        await _cleanupOldBookmarks();
      }
    } catch (e) {
      print('[BahnController] Error loading bookmarks: $e');
      bookmarkedJourneys.value = [];
    }
  }

  /// Save bookmarks to storage
  Future<void> _saveBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = bookmarkedJourneys.map((b) => b.toJson()).toList();
      final jsonString = json.encode(jsonList);
      await prefs.setString(_prefKeyBookmarks, jsonString);
      print('[BahnController] Saved ${bookmarkedJourneys.length} bookmarks');
    } catch (e) {
      print('[BahnController] Error saving bookmarks: $e');
    }
  }

  /// Clean up old completed bookmarks (older than 24 hours)
  Future<void> _cleanupOldBookmarks() async {
    final now = DateTime.now();
    final before = bookmarkedJourneys.length;

    bookmarkedJourneys.removeWhere((b) {
      final oldThreshold = b.displayEndTime.add(Duration(hours: 24));
      return now.isAfter(oldThreshold);
    });

    if (bookmarkedJourneys.length < before) {
      print('[BahnController] Cleaned up ${before - bookmarkedJourneys.length} old bookmarks');
      await _saveBookmarks();
    }
  }

  /// Search for stations by name
  Future<void> searchStations(String query) async {
    if (query.trim().isEmpty) {
      stationSearchResults.clear();
      update();
      return;
    }

    isSearchingStations.value = true;
    update();
    try {
      final stations = await _bahnService.searchStations(query);
      stationSearchResults.value = stations;
    } catch (e) {
      print('[BahnController] Station search error: $e');
      stationSearchResults.clear();
    } finally {
      isSearchingStations.value = false;
      update();
    }
  }

  /// Search for journeys
  Future<void> searchJourneys({
    required DateTime departure,
    int results = 6,
  }) async {
    if (selectedFromStation.value == null || selectedToStation.value == null) {
      searchError.value = 'Please select both origin and destination stations';
      return;
    }

    if (selectedFromStation.value!.id == selectedToStation.value!.id) {
      searchError.value = 'Origin and destination must be different';
      return;
    }

    if (departure.isBefore(DateTime.now())) {
      searchError.value = 'Departure time must be in the future';
      return;
    }

    isSearching.value = true;
    searchError.value = null;
    searchResults.clear();
    update();

    try {
      final journeys = await _bahnService.findJourneys(
        fromStationId: selectedFromStation.value!.id,
        toStationId: selectedToStation.value!.id,
        departure: departure,
        results: results,
      );

      searchResults.value = journeys;

      if (journeys.isEmpty) {
        searchError.value = 'No connections found. Try a different time.';
      }
    } on BahnServiceException catch (e) {
      searchError.value = e.message;
    } catch (e) {
      searchError.value = 'Unexpected error: $e';
    } finally {
      isSearching.value = false;
      update();
    }
  }

  /// Add a journey to bookmarks
  Future<void> addBookmark(
    BahnJourney journey, {
    DateTime? travelDate,
    int? slot,
    BahnDisplayTiming? timing,
  }) async {
    final bookmarkId = _uuid.v4();
    final bookmark = BookmarkedJourney(
      id: bookmarkId,
      journey: journey,
      travelDate: travelDate ?? journey.plannedDeparture,
      dashboardSlot: slot ?? defaultSlot.value,
      displayTiming: timing ?? defaultTiming.value,
      bookmarkedAt: DateTime.now(),
    );

    bookmarkedJourneys.add(bookmark);
    await _saveBookmarks();

    print('[BahnController] Added bookmark: ${journey.trainName} on ${bookmark.travelDate}');

    Get.snackbar(
      'Bookmark Added',
      '${journey.trainName}: ${journey.origin.name} → ${journey.destination.name}',
      snackPosition: SnackPosition.BOTTOM,
      duration: Duration(seconds: 2),
    );
  }

  /// Remove a bookmark
  Future<void> removeBookmark(String bookmarkId) async {
    final removed = bookmarkedJourneys.firstWhereOrNull((b) => b.id == bookmarkId);
    if (removed != null) {
      bookmarkedJourneys.removeWhere((b) => b.id == bookmarkId);
      await _saveBookmarks();
      print('[BahnController] Removed bookmark: $bookmarkId');

      Get.snackbar(
        'Bookmark Removed',
        '${removed.journey.trainName} removed from bookmarks',
        snackPosition: SnackPosition.BOTTOM,
        duration: Duration(seconds: 2),
      );
    }
  }

  /// Update bookmark settings
  Future<void> updateBookmarkSettings(
    String bookmarkId, {
    int? slot,
    BahnDisplayTiming? timing,
  }) async {
    final index = bookmarkedJourneys.indexWhere((b) => b.id == bookmarkId);
    if (index != -1) {
      final updated = bookmarkedJourneys[index].copyWithSettings(
        dashboardSlot: slot,
        displayTiming: timing,
      );
      bookmarkedJourneys[index] = updated;
      await _saveBookmarks();
      print('[BahnController] Updated bookmark settings: $bookmarkId');
    }
  }

  /// Update a bookmark with fresh journey data (for real-time info)
  Future<void> updateBookmarkJourney(String bookmarkId, BahnJourney updatedJourney) async {
    final index = bookmarkedJourneys.indexWhere((b) => b.id == bookmarkId);
    if (index != -1) {
      final updated = bookmarkedJourneys[index].copyWithJourney(updatedJourney);
      bookmarkedJourneys[index] = updated;
      // Don't save to storage here - this is temporary real-time data
      print('[BahnController] Updated bookmark journey: $bookmarkId');
    }
  }

  /// Get active bookmarks (currently showing on dashboard)
  List<BookmarkedJourney> get activeBookmarks {
    final now = DateTime.now();
    return bookmarkedJourneys
        .where((b) => b.isActiveNow(now))
        .toList()
      ..sort((a, b) => a.journey.plannedDeparture.compareTo(b.journey.plannedDeparture));
  }

  /// Get upcoming bookmarks (not yet active)
  List<BookmarkedJourney> get upcomingBookmarks {
    final now = DateTime.now();
    return bookmarkedJourneys
        .where((b) => b.isUpcoming(now))
        .toList()
      ..sort((a, b) => a.journey.plannedDeparture.compareTo(b.journey.plannedDeparture));
  }

  /// Get completed bookmarks
  List<BookmarkedJourney> get completedBookmarks {
    final now = DateTime.now();
    return bookmarkedJourneys
        .where((b) => b.isCompleted(now))
        .toList()
      ..sort((a, b) => b.journey.plannedDeparture.compareTo(a.journey.plannedDeparture));
  }

  /// Clear search results and selections
  void clearSearch() {
    searchResults.clear();
    searchError.value = null;
    selectedFromStation.value = null;
    selectedToStation.value = null;
    stationSearchResults.clear();
  }
}
