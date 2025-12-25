import 'dart:convert';

import 'package:flutter/services.dart';

class TeleprompterFontMetrics {
  static const String _assetPath = 'assets/g1_fonts.json';
  static Future<Map<String, int>>? _cached;

  static Future<Map<String, int>> load() {
    _cached ??= _loadInternal();
    return _cached!;
  }

  static Future<Map<String, int>> _loadInternal() async {
    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['glyphs'] is! List) {
      return <String, int>{};
    }

    final glyphs = decoded['glyphs'] as List;
    final map = <String, int>{};
    for (final glyph in glyphs) {
      if (glyph is Map) {
        final char = glyph['char'];
        final width = glyph['width'];
        if (char is String && width is int) {
          map[char] = width;
        }
      }
    }

    return map;
  }
}
