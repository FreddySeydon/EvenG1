import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/time_note.dart';

class TimeNotesService {
  static const _storageKey = 'time_notes';
  static TimeNotesService? _instance;
  static TimeNotesService get instance => _instance ??= TimeNotesService._();

  TimeNotesService._();

  Future<List<TimeNote>> loadNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return [];
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded.map((e) => TimeNote.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('TimeNotesService: error loading notes: $e');
      return [];
    }
  }

  Future<void> saveNotes(List<TimeNote> notes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(notes.map((n) => n.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      print('TimeNotesService: error saving notes: $e');
    }
  }
}
