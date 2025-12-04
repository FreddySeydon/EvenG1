import 'dart:async';

import 'package:get/get.dart';

import '../ble_manager.dart';
import '../controllers/time_notes_controller.dart';
import '../models/time_note.dart';
import 'dashboard_note_service.dart';
import 'proto.dart';

/// Background helper that watches active time-aware notes and automatically
/// sends the current one to the G1 dashboard when its window starts.
class TimeNotesScheduler extends GetxService {
  late final TimeNotesController _controller;
  StreamSubscription? _activeSub;
  StreamSubscription? _notesSub;
  Timer? _tick;

  /// Tracks the last send token per note to avoid spamming during an active window.
  /// For weekly notes: stores YYYY-MM-DD to send once per day.
  /// For one-time notes: stores 'once' to send only once.
  final Map<String, String> _lastSent = {};
  String? _lastActiveNoteId;
  String? _lastGeneralNoteId;

  @override
  void onInit() {
    super.onInit();
    _controller = Get.find<TimeNotesController>();
    _activeSub = _controller.activeNotes.listen((_) => _handleActive());
    _notesSub = _controller.notes.listen((_) => _handleActive());
    // Periodic safety check (covers reconnection while window is active).
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _handleActive());
    _handleActive();
  }

  @override
  void onClose() {
    _activeSub?.cancel();
    _notesSub?.cancel();
    _tick?.cancel();
    super.onClose();
  }

  Future<void> _handleActive() async {
    final now = DateTime.now();
    final actives = _controller.activeNotes;
    if (actives.isEmpty) {
      // Prefer a general note when idle.
      final general = _controller.generalNotes.isNotEmpty
          ? _controller.generalNotes.first
          : null;

      if (general != null) {
        // Hard-sync layout, then send note, then re-sync layout to avoid split dashboards.
        await Proto.setDashboardMode(modeId: 0);
        await Proto.setTimeAndWeather(weatherIconId: 0x00, temperature: 0);
        await Future.delayed(const Duration(milliseconds: 300));
        final sent = await DashboardNoteService.instance.sendDashboardNote(
          title: general.title.isEmpty ? 'Note' : general.title,
          text: general.content,
          noteNumber: 1,
        );
        await Future.delayed(const Duration(milliseconds: 300));
        await Proto.setDashboardMode(modeId: 0);
        await Proto.setTimeAndWeather(weatherIconId: 0x00, temperature: 0);
        if (sent) {
          _lastGeneralNoteId = general.id;
        }
        _lastActiveNoteId = null;
        _lastSent.removeWhere((_, __) => true);
        return;
      }

      // No general note to show: clear any lingering note and baseline dashboard.
      if (_lastActiveNoteId != null || _lastGeneralNoteId != null) {
        await DashboardNoteService.instance.clearNote(noteNumber: 1);
      }
      _lastActiveNoteId = null;
      _lastGeneralNoteId = null;
      _lastSent.removeWhere((_, __) => true);
      await Proto.setDashboardMode(modeId: 0); // Full layout to keep both eyes consistent
      await Proto.setTimeAndWeather(
        weatherIconId: 0x00,
        temperature: 0, // neutral temp; caller can update via WeatherController elsewhere
      );
      return;
    }

    _lastGeneralNoteId = null;

    // Choose the first active note; could expand to priority ordering if needed.
    final note = actives.first;
    if (!_shouldSend(note, now)) return;
    if (!BleManager.get().isConnected) return;

    // Ensure consistent full dashboard layout before pushing the quick note.
    await Proto.setDashboardMode(modeId: 0);
    await Proto.setTimeAndWeather(weatherIconId: 0x00, temperature: 0);
    await Future.delayed(const Duration(milliseconds: 300));

    final success = await DashboardNoteService.instance.sendDashboardNote(
      title: note.title.isEmpty ? 'Note' : note.title,
      text: note.content,
      noteNumber: 1,
    );
    await Future.delayed(const Duration(milliseconds: 300));
    await Proto.setDashboardMode(modeId: 0);
    await Proto.setTimeAndWeather(weatherIconId: 0x00, temperature: 0);

    if (success) {
      _markSent(note, now);
      _lastActiveNoteId = note.id;
    }
  }

  bool _shouldSend(TimeNote note, DateTime now) {
    if (!note.isActiveAt(now)) return false;
    final key = note.id;
    final token = _sendToken(note, now);
    if (token == null) return false;
    final last = _lastSent[key];

    return last != token;
  }

  void _markSent(TimeNote note, DateTime now) {
    final token = _sendToken(note, now) ?? 'once';
    _lastSent[note.id] = token;
  }

  String? _sendToken(TimeNote note, DateTime now) {
    if (note.isCalendarLinked && note.calendarStart != null) {
      // Use the event start timestamp to allow repeated sends for recurring events.
      return note.calendarStart!.toIso8601String();
    }
    if (note.recurrence == TimeNoteRecurrence.once) {
      return 'once';
    }
    return _todayString(now);
  }

  String _todayString(DateTime now) =>
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}
