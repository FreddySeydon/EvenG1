import 'dart:async';

import 'package:get/get.dart';

import '../ble_manager.dart';
import '../controllers/time_notes_controller.dart';
import '../controllers/weather_controller.dart';
import '../models/time_note.dart';
import 'dashboard_note_service.dart';
import 'proto.dart';
import 'teleprompter_service.dart';
import 'world_time_service.dart';

/// Background helper that watches active time-aware notes and automatically
/// sends the current one to the G1 dashboard when its window starts.
class TimeNotesScheduler extends GetxService {
  late final TimeNotesController _controller;
  StreamSubscription? _activeSub;
  StreamSubscription? _notesSub;
  Timer? _tick;
  Timer? _worldTimeTick;
  Timer? _worldTimeNoteTick;
  DateTime? _activeHoldUntil;

  /// Tracks the last send token per note to avoid spamming during an active window.
  /// For weekly notes: stores YYYY-MM-DD to send once per day.
  /// For one-time notes: stores 'once' to send only once.
  final Map<String, String> _lastSent = {};
  String? _lastActiveNoteId;
  String? _lastGeneralNoteId;
  static const _placeholderId = '_placeholder_note';

  @override
  void onInit() {
    super.onInit();
    _controller = Get.find<TimeNotesController>();
    _activeSub = _controller.activeNotes.listen((_) => _handleActive());
    _notesSub = _controller.notes.listen((_) => _handleActive());
    // Periodic safety check (covers reconnection while window is active).
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _handleActive());
    // Minute ticks to keep world time fresh when enabled (aligned to minute boundary).
    _scheduleWorldTimeTicks();
    _handleActive();
  }

  @override
  void onClose() {
    _activeSub?.cancel();
    _notesSub?.cancel();
    _tick?.cancel();
    _worldTimeTick?.cancel();
    _worldTimeNoteTick?.cancel();
    super.onClose();
  }

  /// Re-run the active note send logic immediately (used after previews).
  Future<void> resendActiveNow() => _handleActive();

  Future<void> _handleActive() async {
    if (TeleprompterService.isActive) {
      return;
    }
    final now = DateTime.now();
    final actives = _controller.activeNotes;
    if (actives.isEmpty) {
      // Prefer a general note when idle.
      final general = _controller.generalNotes.isNotEmpty
          ? _controller.generalNotes.first
          : null;

      if (general != null && (_activeHoldUntil == null || now.isAfter(_activeHoldUntil!))) {
        // Hard-sync layout, then send note, then re-sync layout to avoid split dashboards.
        await _resyncDashboard();
        final payload = await _notePayload(general);
        final sent = await DashboardNoteService.instance.sendDashboardNote(
          title: payload.title,
          text: payload.text,
          noteNumber: 1,
        );
        await _resyncDashboard(withDelay: true);
        // Extra delayed resync to catch flaky arms.
        _resyncDashboard(withDelay: true);
        if (sent) {
          _lastGeneralNoteId = general.id;
        }
        _lastActiveNoteId = null;
        _lastSent.removeWhere((_, __) => true);
        return;
      }

      // No general note: if world time is enabled, show it solo.
      final world = await _worldTimeOnlyPayload();
      if (world != null) {
        await _resyncDashboard();
        await DashboardNoteService.instance.sendDashboardNote(
          title: world.title,
          text: world.text,
          noteNumber: 1,
        );
        await _resyncDashboard(withDelay: true);
        _resyncDashboard(withDelay: true);
        _lastActiveNoteId = null;
        _lastGeneralNoteId = null;
        _lastSent.removeWhere((_, __) => true);
        return;
      }

      // Placeholder only after hold window expires to avoid flicker after an active note ends.
      if (_activeHoldUntil != null && now.isBefore(_activeHoldUntil!)) {
        return;
      }

      // No notes at all: show a placeholder prompt.
      await _resyncDashboard();
      await DashboardNoteService.instance.sendDashboardNote(
        title: 'No notes yet',
        text: 'Add notes in the app to display them here.',
        noteNumber: 1,
      );
      await _resyncDashboard(withDelay: true);
      _resyncDashboard(withDelay: true);
      _lastActiveNoteId = null;
      _lastGeneralNoteId = _placeholderId;
      _lastSent.removeWhere((_, __) => true);
      return;
    }

    // Active note present: hold off general/placeholder for a few seconds after it ends.
    _activeHoldUntil = now.add(const Duration(seconds: 10));
    _lastGeneralNoteId = null;

    // Choose the first active note; could expand to priority ordering if needed.
    final note = actives.first;
    if (!_shouldSend(note, now)) return;
    if (!BleManager.get().isConnected) return;

    // Ensure consistent full dashboard layout before pushing the quick note.
    await _resyncDashboard();

    final payload = await _notePayload(note);
    final success = await DashboardNoteService.instance.sendDashboardNote(
      title: payload.title,
      text: payload.text,
      noteNumber: 1,
    );
    await _resyncDashboard(withDelay: true);
    _resyncDashboard(withDelay: true);

    if (success) {
      _markSent(note, now);
      _lastActiveNoteId = note.id;
    }
  }

  Future<void> _resyncDashboard({bool withDelay = false}) async {
    if (withDelay) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    await Proto.setDashboardMode(modeId: 0);
    await Proto.setTimeAndWeather(weatherIconId: 0x00, temperature: 0);
    await _restoreWeatherIfAvailable();
  }

  Future<void> _restoreWeatherIfAvailable() async {
    if (!Get.isRegistered<WeatherController>()) return;
    final weatherController = Get.find<WeatherController>();
    final data = weatherController.weatherData.value;
    if (data == null) return;
    final temp = data.temperature.round().clamp(-128, 127);
    await Proto.setTimeAndWeather(
      weatherIconId: data.weatherIconId,
      temperature: temp,
      useFahrenheit: weatherController.useFahrenheit.value,
      use12HourFormat: weatherController.use12HourFormat.value,
    );
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

  Future<_NotePayload> _notePayload(TimeNote note) async {
    final svc = WorldTimeService.instance;
    await svc.ensureReady();
    if (!svc.enabled) {
      return _NotePayload(
        title: note.title.isEmpty ? 'Note' : note.title,
        text: note.content,
      );
    }
    final worldTitle = svc.formattedTime();
    final titleLine = note.title.isNotEmpty ? '${note.title}\n' : '';
    final body = '$titleLine${note.content}'.trim();
    return _NotePayload(
      title: worldTitle,
      text: body.isEmpty ? note.title : body,
    );
  }

  Future<_NotePayload?> _worldTimeOnlyPayload() async {
    final svc = WorldTimeService.instance;
    await svc.ensureReady();
    if (!svc.enabled) return null;
    return _NotePayload(
      title: svc.formattedTime(),
      text: '',
    );
  }

  Future<void> _tickWorldTime() async {
    if (TeleprompterService.isActive) return;
    final svc = WorldTimeService.instance;
    await svc.ensureReady();
    if (!svc.enabled) return;
    if (!BleManager.get().isConnected) return;
    // Only refresh when no notes are displayed; otherwise _handleActive covers it.
    if (_controller.activeNotes.isNotEmpty || _controller.generalNotes.isNotEmpty) {
      return;
    }
    final payload = await _worldTimeOnlyPayload();
    if (payload == null) return;
    await Proto.setDashboardMode(modeId: 0);
    await Proto.setTimeAndWeather(weatherIconId: 0x00, temperature: 0);
    await Future.delayed(const Duration(milliseconds: 300));
    await DashboardNoteService.instance.sendDashboardNote(
      title: payload.title,
      text: payload.text,
      noteNumber: 1,
    );
    await Future.delayed(const Duration(milliseconds: 300));
    await Proto.setDashboardMode(modeId: 0);
    await Proto.setTimeAndWeather(weatherIconId: 0x00, temperature: 0);
  }

  Future<void> _tickWorldTimeWithNote() async {
    if (TeleprompterService.isActive) return;
    final svc = WorldTimeService.instance;
    await svc.ensureReady();
    if (!svc.enabled) return;
    if (!BleManager.get().isConnected) return;
    // Only refresh when a note is showing (active or general) so the clock in the title stays fresh.
    final note = _controller.activeNotes.isNotEmpty
        ? _controller.activeNotes.first
        : (_controller.generalNotes.isNotEmpty ? _controller.generalNotes.first : null);
    if (note == null) return;

    final payload = await _notePayload(note);
    await Proto.setDashboardMode(modeId: 0);
    await Proto.setTimeAndWeather(weatherIconId: 0x00, temperature: 0);
    await Future.delayed(const Duration(milliseconds: 300));
    await DashboardNoteService.instance.sendDashboardNote(
      title: payload.title,
      text: payload.text,
      noteNumber: 1,
    );
    await Future.delayed(const Duration(milliseconds: 300));
    await Proto.setDashboardMode(modeId: 0);
    await Proto.setTimeAndWeather(weatherIconId: 0x00, temperature: 0);
  }

  /// Schedule world-time refreshes aligned to the next minute boundary.
  void _scheduleWorldTimeTicks() {
    _worldTimeTick?.cancel();
    _worldTimeNoteTick?.cancel();
    final now = DateTime.now();
    final msUntilNextMinute = 60000 - (now.millisecond + now.second * 1000);
    Future.delayed(Duration(milliseconds: msUntilNextMinute), () {
      // Trigger once at the boundary, then every minute.
      _tickWorldTime();
      _tickWorldTimeWithNote();
      _worldTimeTick = Timer.periodic(const Duration(minutes: 1), (_) => _tickWorldTime());
      _worldTimeNoteTick = Timer.periodic(const Duration(minutes: 1), (_) => _tickWorldTimeWithNote());
    });
  }
}

class _NotePayload {
  final String title;
  final String text;
  _NotePayload({required this.title, required this.text});
}
