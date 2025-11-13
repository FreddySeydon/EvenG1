import 'package:demo_ai_even/models/pin_text_model.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class PinTextController extends GetxController {
  var notes = <PinText>[].obs;
  var currentNoteIndex = 0.obs;
  var isDashboardMode = false.obs;

  static const String _storageKey = 'pin_text';
  static const String _oldStorageKey = 'quicknotes'; // For backward compatibility

  @override
  void onInit() {
    super.onInit();
    loadNotes();
  }

  void addNote(String content) {
    final note = PinText(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      createdAt: DateTime.now(),
    );
    notes.insert(0, note);
    saveNotes();
  }

  void updateNote(int index, String content) {
    if (index >= 0 && index < notes.length) {
      notes[index] = notes[index].copyWith(
        content: content,
        updatedAt: DateTime.now(),
      );
      saveNotes();
    }
  }

  /// Pin a PinText (only one can be pinned at a time)
  /// This is just a UI marker - pinning does NOT send the note to glasses
  /// Users must manually send notes using the send button
  void pinNote(int index) {
    if (index < 0 || index >= notes.length) return;
    
    // Unpin all other notes first
    for (int i = 0; i < notes.length; i++) {
      if (notes[i].isPinned) {
        notes[i] = notes[i].copyWith(isPinned: false);
      }
    }
    
    // Pin the selected note
    notes[index] = notes[index].copyWith(isPinned: true);
    saveNotes();
    
    print('${DateTime.now()} PinTextController: Note pinned (UI marker only)');
  }

  /// Unpin the currently pinned note
  void unpinNote(int index) {
    if (index < 0 || index >= notes.length) return;
    if (notes[index].isPinned) {
      notes[index] = notes[index].copyWith(isPinned: false);
      saveNotes();
    }
  }

  /// Get the pinned note if any
  PinText? getPinnedNote() {
    try {
      return notes.firstWhere((note) => note.isPinned);
    } catch (e) {
      return null;
    }
  }

  void removeNote(int index) {
    if (index >= 0 && index < notes.length) {
      notes.removeAt(index);
      if (currentNoteIndex.value >= notes.length && notes.isNotEmpty) {
        currentNoteIndex.value = notes.length - 1;
      } else if (notes.isEmpty) {
        currentNoteIndex.value = 0;
      }
      saveNotes();
    }
  }

  PinText? getCurrentNote() {
    if (notes.isEmpty || currentNoteIndex.value >= notes.length) {
      return null;
    }
    return notes[currentNoteIndex.value];
  }

  void nextNote() {
    if (notes.isEmpty) return;
    currentNoteIndex.value = (currentNoteIndex.value + 1) % notes.length;
  }

  void previousNote() {
    if (notes.isEmpty) return;
    currentNoteIndex.value = (currentNoteIndex.value - 1 + notes.length) % notes.length;
  }

  Future<void> saveNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notesJson = notes.map((note) => note.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(notesJson));
    } catch (e) {
      print('Error saving Pin Text: $e');
    }
  }

  Future<void> loadNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Try to load from new key first
      var notesJsonString = prefs.getString(_storageKey);
      bool loadedFromOldKey = false;
      
      // If not found, try old key for backward compatibility
      if (notesJsonString == null) {
        notesJsonString = prefs.getString(_oldStorageKey);
        if (notesJsonString != null) {
          loadedFromOldKey = true;
          print('Migrating data from old storage key "quicknotes" to "pin_text"');
        }
      }
      
      if (notesJsonString != null) {
        final List<dynamic> notesJson = jsonDecode(notesJsonString);
        notes.value = notesJson.map((json) => PinText.fromJson(json)).toList();
        
        // If we loaded from old key, save to new key and remove old key
        if (loadedFromOldKey) {
          await saveNotes();
          await prefs.remove(_oldStorageKey);
          print('Successfully migrated data from "quicknotes" to "pin_text"');
        }
      }
    } catch (e) {
      print('Error loading Pin Text: $e');
    }
  }
}

