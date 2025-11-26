import 'dart:async';

import 'package:get/get.dart';

import '../ble_manager.dart';
import '../controllers/time_notes_controller.dart';
import '../models/time_note.dart';
import 'dashboard_note_service.dart';

/// Background helper that watches active time-aware notes and automatically
/// sends the current one to the G1 dashboard when its window starts.
class TimeNotesScheduler extends GetxService {
  late final TimeNotesController _controller;
  StreamSubscription? _activeSub;
  Timer? _tick;

  /// Tracks the last send token per note to avoid spamming during an active window.
  /// For weekly notes: stores YYYY-MM-DD to send once per day.
  /// For one-time notes: stores 'once' to send only once.
  final Map<String, String> _lastSent = {};
  String? _lastActiveNoteId;

  @override
  void onInit() {
    super.onInit();
    _controller = Get.find<TimeNotesController>();
    _activeSub = _controller.activeNotes.listen((_) => _handleActive());
    // Periodic safety check (covers reconnection while window is active).
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _handleActive());
    _handleActive();
  }

  @override
  void onClose() {
    _activeSub?.cancel();
    _tick?.cancel();
    super.onClose();
  }

  Future<void> _handleActive() async {
    final now = DateTime.now();
    final actives = _controller.activeNotes;
    if (actives.isEmpty) {
      if (_lastActiveNoteId != null) {
        await DashboardNoteService.instance.clearNote(noteNumber: 1);
        _lastActiveNoteId = null;
        _lastSent.removeWhere((_, __) => true);
      }
      return;
    }

    // Choose the first active note; could expand to priority ordering if needed.
    final note = actives.first;
    if (!_shouldSend(note, now)) return;
    if (!BleManager.get().isConnected) return;

    final success = await DashboardNoteService.instance.sendDashboardNote(
      title: note.title.isEmpty ? 'Note' : note.title,
      text: note.content,
      noteNumber: 1,
    );
    if (success) {
      _markSent(note, now);
      _lastActiveNoteId = note.id;
    }
  }

  bool _shouldSend(TimeNote note, DateTime now) {
    if (!note.isActiveAt(now)) return false;
    final key = note.id;
    final today = _todayString(now);
    final last = _lastSent[key];

    if (note.recurrence == TimeNoteRecurrence.once) {
      // Send only once for one-time notes.
      return last == null;
    }

    // Weekly recurrence: send once per day when active.
    return last != today;
  }

  void _markSent(TimeNote note, DateTime now) {
    _lastSent[note.id] =
        note.recurrence == TimeNoteRecurrence.once ? 'once' : _todayString(now);
  }

  String _todayString(DateTime now) =>
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}
