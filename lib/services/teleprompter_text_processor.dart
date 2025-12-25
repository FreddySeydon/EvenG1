import 'dart:convert';

import 'package:flutter/material.dart';

class TeleprompterTextSplit {
  final String visible;
  final String next;

  const TeleprompterTextSplit({
    required this.visible,
    required this.next,
  });
}

class TeleprompterTextProcessor {
  static const int _byteLimit = 112;
  static const int _defaultMaxWidth = 180;

  static String addLineBreaks(String text, {int maxWidth = _defaultMaxWidth}) {
    return addLineBreaksWithMetrics(text, null, maxWidth: maxWidth);
  }

  static String addLineBreaksWithMetrics(
    String text,
    Map<String, int>? charWidths, {
    int maxWidth = _defaultMaxWidth,
  }) {
    if (charWidths != null && charWidths.isNotEmpty) {
      return _addLineBreaksByWidth(text, charWidths, maxWidth);
    }

    final normalized = text.replaceAll('\r\n', '\n');
    final paragraphs = normalized.split('\n');
    final lines = <String>[];

    for (final paragraph in paragraphs) {
      if (paragraph.trim().isEmpty) {
        lines.add('');
        continue;
      }
      lines.addAll(_wrapParagraph(paragraph, maxWidth));
    }

    return lines.join('\n');
  }

  static String _addLineBreaksByWidth(
    String text,
    Map<String, int> charWidths,
    int maxWidth,
  ) {
    final normalized = text.replaceAll('\r\n', '\n');
    final paragraphs = normalized.split('\n');
    final lines = <String>[];

    for (final paragraph in paragraphs) {
      if (paragraph.trim().isEmpty) {
        lines.add('');
        continue;
      }

      final words = paragraph.trim().split(RegExp(r'\s+'));
      var currentLine = '';
      var currentWidth = 0;

      for (final word in words) {
        final wordWidth = _measureWord(word, charWidths);
        final spaceWidth = charWidths[' '] ?? 2;
        final needsSpace = currentLine.isNotEmpty;
        final nextWidth =
            currentWidth + (needsSpace ? spaceWidth : 0) + wordWidth;

        if (currentLine.isEmpty || nextWidth <= maxWidth) {
          currentLine = currentLine.isEmpty ? word : '$currentLine $word';
          currentWidth = nextWidth;
        } else {
          lines.add(currentLine);
          currentLine = word;
          currentWidth = wordWidth;
        }
      }

      if (currentLine.isNotEmpty) {
        lines.add(currentLine);
      }
    }

    return lines.join('\n');
  }

  static int _measureWord(String word, Map<String, int> charWidths) {
    var width = 0;
    for (final rune in word.runes) {
      final char = String.fromCharCode(rune);
      width += charWidths[char] ?? 5;
    }
    return width;
  }

  static List<String> _wrapParagraph(String paragraph, int maxWidth) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: paragraph,
        style: const TextStyle(fontSize: 21),
      ),
      textDirection: TextDirection.ltr,
      maxLines: null,
    );

    textPainter.layout(maxWidth: maxWidth.toDouble());
    final metrics = textPainter.computeLineMetrics();
    if (metrics.isEmpty) {
      return [paragraph.trim()];
    }

    final lines = <String>[];
    var start = 0;
    for (final _ in metrics) {
      final boundary =
          textPainter.getLineBoundary(TextPosition(offset: start));
      lines.add(paragraph.substring(boundary.start, boundary.end).trim());
      start = boundary.end;
    }

    return lines;
  }

  static int getUtf8ByteLength(String text) {
    return utf8.encode(text).length;
  }

  static int findSafeCutPosition(String text, int byteLimit) {
    var bytesUsed = 0;
    var codeUnitIndex = 0;

    for (final rune in text.runes) {
      final bytesNeeded = rune <= 0x7F
          ? 1
          : rune <= 0x7FF
              ? 2
              : rune <= 0xFFFF
                  ? 3
                  : 4;

      if (bytesUsed + bytesNeeded > byteLimit) {
        break;
      }

      bytesUsed += bytesNeeded;
      codeUnitIndex += rune > 0xFFFF ? 2 : 1;
    }

    return codeUnitIndex;
  }

  static int findSafeCutPositionAtOffset(String text, int byteOffset) {
    var bytesUsed = 0;
    var codeUnitIndex = 0;

    for (final rune in text.runes) {
      final bytesNeeded = rune <= 0x7F
          ? 1
          : rune <= 0x7FF
              ? 2
              : rune <= 0xFFFF
                  ? 3
                  : 4;

      if (bytesUsed + bytesNeeded >= byteOffset) {
        return codeUnitIndex;
      }

      bytesUsed += bytesNeeded;
      codeUnitIndex += rune > 0xFFFF ? 2 : 1;
    }

    return text.length;
  }

  static int findReadableBreakPoint(String text, int maxPos) {
    final safeMax = maxPos.clamp(0, text.length);
    final searchStart = (safeMax - 50).clamp(0, safeMax);

    for (var i = safeMax; i >= searchStart; i--) {
      if (i == 0) continue;
      final charBefore = text[i - 1];

      if (charBefore == ' ' && i > 1) {
        final punctuationBefore = text[i - 2];
        if ('.:;,!?'.contains(punctuationBefore)) {
          return i;
        }
      }

      if (charBefore == '\n') {
        return i;
      }

      if (charBefore == ' ') {
        return i;
      }
    }

    return safeMax;
  }

  static String sliceFormattedTextAtPercent(String text, int percent) {
    final totalBytes = getUtf8ByteLength(text);
    if (totalBytes == 0) return text;
    final clampedPercent = percent.clamp(0, 100);
    final targetBytes = (totalBytes * clampedPercent / 100).round();
    final safeIndex = findSafeCutPositionAtOffset(text, targetBytes);
    final lineStart = _lineStartIndex(text, safeIndex);
    if (lineStart >= text.length) return text;
    return text.substring(lineStart);
  }

  static int _lineStartIndex(String text, int index) {
    if (index <= 0) return 0;
    final prevNewline = text.lastIndexOf('\n', index - 1);
    if (prevNewline == -1) return 0;
    return prevNewline + 1;
  }

  static TeleprompterTextSplit splitTextForTeleprompter(String text) {
    final cutPosition = findReadableBreakPoint(
      text,
      findSafeCutPosition(text, _byteLimit),
    );

    final visibleText = text.substring(0, cutPosition);
    final remaining = text.substring(cutPosition).trimLeft();

    if (remaining.isEmpty) {
      return TeleprompterTextSplit(visible: visibleText, next: '');
    }

    final nextCut = findReadableBreakPoint(
      remaining,
      findSafeCutPosition(remaining, _byteLimit),
    );
    final nextVisible = remaining.substring(0, nextCut).trimRight();
    final nextText = nextVisible.isEmpty ? '' : '$nextVisible\n        ';

    return TeleprompterTextSplit(
      visible: visibleText,
      next: nextText,
    );
  }
}
