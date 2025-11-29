import 'dart:async';

import 'package:get/get.dart';

import '../models/time_note.dart';
import '../services/time_notes_service.dart';

class TimeNotesController extends GetxController {
  final notes = <TimeNote>[].obs;
  final activeNotes = <TimeNote>[].obs;
  final generalNotes = <TimeNote>[].obs;

  Timer? _ticker;

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  @override
  void onClose() {
    _ticker?.cancel();
    super.onClose();
  }

  Future<void> _load() async {
    final loaded = await TimeNotesService.instance.loadNotes();
    notes.assignAll(loaded);
    _startTicker();
    _recomputeActive();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      _recomputeActive();
    });
  }

  Future<void> addOrUpdate(TimeNote note) async {
    final idx = notes.indexWhere((n) => n.id == note.id);
    if (idx >= 0) {
      notes[idx] = note;
    } else {
      notes.add(note);
    }
    await TimeNotesService.instance.saveNotes(notes);
    _recomputeActive();
  }

  Future<void> deleteNote(String id) async {
    notes.removeWhere((n) => n.id == id);
    await TimeNotesService.instance.saveNotes(notes);
    _recomputeActive();
  }

  void _recomputeActive() {
    final now = DateTime.now();
    final active = notes.where((n) => n.isActiveAt(now)).toList();
    activeNotes.assignAll(active);
    generalNotes.assignAll(notes.where((n) => n.type == TimeNoteType.general));
  }
}
