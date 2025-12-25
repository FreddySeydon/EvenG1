import 'dart:convert';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/teleprompter_models.dart';

class TeleprompterController extends GetxController {
  static const _storageKey = 'teleprompter_presentations_v1';

  final RxBool isLoading = true.obs;
  final RxList<TeleprompterPresentation> presentations =
      <TeleprompterPresentation>[].obs;

  @override
  void onInit() {
    super.onInit();
    loadPresentations();
  }

  Future<void> loadPresentations() async {
    isLoading.value = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      presentations.clear();
      isLoading.value = false;
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        presentations.assignAll(
          decoded
              .map((item) => TeleprompterPresentation.fromJson(
                    Map<String, dynamic>.from(item as Map),
                  ))
              .toList(),
        );
      } else {
        presentations.clear();
      }
    } catch (e) {
      presentations.clear();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final data =
        presentations.map((presentation) => presentation.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(data));
  }

  TeleprompterPresentation? getPresentation(String id) {
    return presentations.firstWhereOrNull((item) => item.id == id);
  }

  Future<TeleprompterPresentation> addPresentation(String name) async {
    final presentation = TeleprompterPresentation(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'Untitled' : name.trim(),
      slides: const [],
    );
    presentations.add(presentation);
    await _persist();
    return presentation;
  }

  Future<void> renamePresentation(String id, String name) async {
    final index = presentations.indexWhere((item) => item.id == id);
    if (index == -1) return;
    presentations[index] = presentations[index].copyWith(
      name: name.trim().isEmpty ? 'Untitled' : name.trim(),
    );
    await _persist();
  }

  Future<void> deletePresentation(String id) async {
    presentations.removeWhere((item) => item.id == id);
    await _persist();
  }

  Future<void> updatePresentation(TeleprompterPresentation updated) async {
    final index = presentations.indexWhere((item) => item.id == updated.id);
    if (index == -1) return;
    presentations[index] = updated;
    await _persist();
  }

  Future<void> addSlide(String presentationId, TeleprompterSlide slide) async {
    final presentation = getPresentation(presentationId);
    if (presentation == null) return;
    final updatedSlides = [...presentation.slides, slide];
    await updatePresentation(presentation.copyWith(slides: updatedSlides));
  }

  Future<void> updateSlide(
    String presentationId,
    TeleprompterSlide slide,
  ) async {
    final presentation = getPresentation(presentationId);
    if (presentation == null) return;
    final updatedSlides = presentation.slides
        .map((item) => item.id == slide.id ? slide : item)
        .toList();
    await updatePresentation(presentation.copyWith(slides: updatedSlides));
  }

  Future<void> deleteSlide(String presentationId, String slideId) async {
    final presentation = getPresentation(presentationId);
    if (presentation == null) return;
    final updatedSlides =
        presentation.slides.where((item) => item.id != slideId).toList();
    await updatePresentation(presentation.copyWith(slides: updatedSlides));
  }

  Future<void> moveSlide(
    String presentationId,
    int oldIndex,
    int newIndex,
  ) async {
    final presentation = getPresentation(presentationId);
    if (presentation == null) return;
    if (oldIndex < 0 ||
        oldIndex >= presentation.slides.length ||
        newIndex < 0 ||
        newIndex >= presentation.slides.length) {
      return;
    }

    final updatedSlides = [...presentation.slides];
    final slide = updatedSlides.removeAt(oldIndex);
    updatedSlides.insert(newIndex, slide);
    await updatePresentation(presentation.copyWith(slides: updatedSlides));
  }
}
