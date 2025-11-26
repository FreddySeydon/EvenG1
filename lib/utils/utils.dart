import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class Utils {
  Utils._();

  static int getTimestampMs() {
    return DateTime.now().millisecondsSinceEpoch;
  }

  static Uint8List addPrefixToUint8List(List<int> prefix, Uint8List data) {
    var newData = Uint8List(data.length + prefix.length);
    for (var i = 0; i < prefix.length; i++) {
      newData[i] = prefix[i];
    }
    for (var i = prefix.length, j = 0;
        i < prefix.length + data.length;
        i++, j++) {
      newData[i] = data[j];
    }
    return newData;
  }

  /// Convert binary array to hexadecimal string
  static String bytesToHexStr(Uint8List data, [String join = '']) {
    List<String> hexList =
        data.map((byte) => byte.toRadixString(16).padLeft(2, '0')).toList();
    String hexResult = hexList.join(join);
    return hexResult;
  }

  static Future<Uint8List> loadBmpImage(String imageUrl) async {
    try {
      final ByteData data = await rootBundle.load(imageUrl);
      return data.buffer.asUint8List();
    } catch (e) {
      print("Error loading BMP file: $e");
      return Uint8List(0);
    }
  }

  /// Convert image file to 1-bit BMP format (576x136 pixels)
  /// Returns the BMP file data as Uint8List
  static Future<Uint8List?> convertImageToBmp(
    String imagePath, {
    int targetWidth = 576,
    int targetHeight = 136,
    double threshold = 0.5,
  }) async {
    try {
      // Read image file
      final file = File(imagePath);
      if (!await file.exists()) {
        print("Error: Image file does not exist: $imagePath");
        return null;
      }

      final imageBytes = await file.readAsBytes();
      final image = img.decodeImage(imageBytes);

      if (image == null) {
        print("Error: Could not decode image");
        return null;
      }

      // Resize image to target dimensions
      final resized = img.copyResize(
        image,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.linear,
      );

      // Convert to grayscale
      final grayscale = img.grayscale(resized);

      // Convert to 1-bit (black and white) using threshold
      final oneBit = _applyThreshold(grayscale, (threshold * 255).round());

      // Encode as 1-bit BMP
      final bmpBytes = _encode1BitBmp(oneBit, targetWidth, targetHeight);

      return bmpBytes;
    } catch (e) {
      print("Error converting image to BMP: $e");
      return null;
    }
  }

  /// Convert image bytes to 1-bit BMP format (576x136 pixels)
  /// Returns the BMP file data as Uint8List (full BMP file including headers)
  static Future<Uint8List?> convertImageBytesToBmp(
    Uint8List imageBytes, {
    int targetWidth = 576,
    int targetHeight = 136,
    double threshold = 0.5,
  }) async {
    try {
      final image = img.decodeImage(imageBytes);

      if (image == null) {
        print("Error: Could not decode image");
        return null;
      }

      // Resize image to target dimensions
      // First, resize maintaining aspect ratio to cover the target area
      final aspectRatio = image.width / image.height;
      final targetAspectRatio = targetWidth / targetHeight;

      img.Image resized;
      if (aspectRatio > targetAspectRatio) {
        // Image is wider - resize to fit height, then crop width
        resized = img.copyResize(
          image,
          height: targetHeight,
          interpolation: img.Interpolation.linear,
        );
      } else {
        // Image is taller - resize to fit width, then crop height
        resized = img.copyResize(
          image,
          width: targetWidth,
          interpolation: img.Interpolation.linear,
        );
      }

      // Crop to exact target dimensions (center crop)
      if (resized.width > targetWidth || resized.height > targetHeight) {
        final cropX = (resized.width - targetWidth) ~/ 2;
        final cropY = (resized.height - targetHeight) ~/ 2;
        resized = img.copyCrop(
          resized,
          x: cropX.clamp(0, resized.width - targetWidth),
          y: cropY.clamp(0, resized.height - targetHeight),
          width: targetWidth,
          height: targetHeight,
        );
      }

      // If still not exact size, force resize (shouldn't happen, but safety check)
      if (resized.width != targetWidth || resized.height != targetHeight) {
        resized = img.copyResize(
          resized,
          width: targetWidth,
          height: targetHeight,
          interpolation: img.Interpolation.linear,
        );
      }

      // Convert to grayscale
      final grayscale = img.grayscale(resized);

      // Convert to 1-bit (black and white) using threshold
      final oneBit = _applyThreshold(grayscale, (threshold * 255).round());

      // Encode as 1-bit BMP
      final bmpBytes = _encode1BitBmp(oneBit, targetWidth, targetHeight);

      return bmpBytes;
    } catch (e) {
      print("Error converting image bytes to BMP: $e");
      return null;
    }
  }

  /// Apply threshold to convert grayscale image to binary (1-bit)
  static img.Image _applyThreshold(img.Image image, int threshold) {
    final result = img.Image(width: image.width, height: image.height);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        // Get grayscale value (use red channel as it should be grayscale)
        final gray = pixel.r.toInt();

        // Apply threshold: above threshold = white (255), below = black (0)
        final newValue = gray > threshold ? 255 : 0;
        result.setPixel(x, y, img.ColorRgb8(newValue, newValue, newValue));
      }
    }

    return result;
  }

  /// Encode image as 1-bit BMP format
  /// BMP format structure:
  /// - BMP Header (14 bytes)
  /// - DIB Header (40 bytes)
  /// - Color Palette (8 bytes for 2 colors)
  /// - Pixel Data (1 bit per pixel, rows padded to 4-byte boundaries)
  static Uint8List _encode1BitBmp(img.Image image, int width, int height) {
    // Calculate row size (padded to 4-byte boundary)
    // For 1-bit: each byte holds 8 pixels
    int rowSize = ((width + 31) ~/ 32) * 4;
    int pixelDataSize = rowSize * height;

    // BMP Header (14 bytes)
    int fileSize =
        14 + 40 + 8 + pixelDataSize; // header + dib + palette + pixels
    int pixelDataOffset = 14 + 40 + 8;

    final bmp = ByteData(fileSize);
    int offset = 0;

    // BMP File Header (14 bytes)
    bmp.setUint8(offset++, 0x42); // 'B'
    bmp.setUint8(offset++, 0x4D); // 'M'
    bmp.setUint32(offset, fileSize, Endian.little);
    offset += 4; // File size
    bmp.setUint32(offset, 0, Endian.little);
    offset += 4; // Reserved
    bmp.setUint32(offset, pixelDataOffset, Endian.little);
    offset += 4; // Pixel data offset

    // DIB Header - BITMAPINFOHEADER (40 bytes)
    bmp.setUint32(offset, 40, Endian.little);
    offset += 4; // Header size
    bmp.setUint32(offset, width, Endian.little);
    offset += 4; // Width
    bmp.setUint32(offset, height, Endian.little);
    offset += 4; // Height
    bmp.setUint16(offset, 1, Endian.little);
    offset += 2; // Color planes
    bmp.setUint16(offset, 1, Endian.little);
    offset += 2; // Bits per pixel (1-bit)
    bmp.setUint32(offset, 0, Endian.little);
    offset += 4; // Compression (0 = none)
    bmp.setUint32(offset, pixelDataSize, Endian.little);
    offset += 4; // Image size
    bmp.setUint32(offset, 0, Endian.little);
    offset += 4; // X pixels per meter
    bmp.setUint32(offset, 0, Endian.little);
    offset += 4; // Y pixels per meter
    bmp.setUint32(offset, 2, Endian.little);
    offset += 4; // Colors in palette (2 for 1-bit)
    bmp.setUint32(offset, 0, Endian.little);
    offset += 4; // Important colors

    // Color Palette (8 bytes for 2 colors: black and white)
    // Color 0: Black (B, G, R, reserved)
    bmp.setUint8(offset++, 0x00); // B
    bmp.setUint8(offset++, 0x00); // G
    bmp.setUint8(offset++, 0x00); // R
    bmp.setUint8(offset++, 0x00); // Reserved
    // Color 1: White (B, G, R, reserved)
    bmp.setUint8(offset++, 0xFF); // B
    bmp.setUint8(offset++, 0xFF); // G
    bmp.setUint8(offset++, 0xFF); // R
    bmp.setUint8(offset++, 0x00); // Reserved

    // Pixel Data (BMP stores pixels bottom-to-top, left-to-right)
    // Each byte represents 8 pixels (1 bit per pixel)
    // BMP format: rows are stored bottom-to-top
    for (int y = height - 1; y >= 0; y--) {
      int rowStartOffset = pixelDataOffset + (height - 1 - y) * rowSize;
      int byteIndex = 0;
      int bitIndex = 7;
      int currentByte = 0;

      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        // Convert to grayscale if needed, then to binary
        final gray = (r * 0.299 + g * 0.587 + b * 0.114).round();

        // If pixel is white/light (value > 128), set bit to 1, else 0
        // For 1-bit BMP: 0 = uses palette color 0 (black), 1 = uses palette color 1 (white)
        if (gray > 128) {
          currentByte |= (1 << bitIndex);
        }

        bitIndex--;
        if (bitIndex < 0) {
          // Finished a byte, write it
          bmp.setUint8(rowStartOffset + byteIndex, currentByte);
          byteIndex++;
          bitIndex = 7;
          currentByte = 0;
        }
      }

      // Write remaining bits if width is not a multiple of 8
      if (bitIndex != 7) {
        bmp.setUint8(rowStartOffset + byteIndex, currentByte);
        byteIndex++;
      }

      // Pad row to 4-byte boundary (already calculated in rowSize)
      // Remaining bytes in row are already zero-initialized
    }

    return bmp.buffer.asUint8List();
  }

  /// Convert image bytes to full-height 1-bit BMP format (576px width, maintains aspect ratio)
  /// Returns a map with 'bmp' (Uint8List) and 'height' (int) keys.
  ///
  /// [scale] allows scaling the image down before encoding while keeping the
  /// BMP width at [targetWidth]. The actual image content is scaled by
  /// [scale] and centered horizontally in a 576px wide canvas so that the
  /// glasses still receive a full-width BMP frame.
  static Future<Map<String, dynamic>?> convertImageBytesToFullHeightBmp(
    Uint8List imageBytes, {
    int targetWidth = 576,
    double threshold = 0.5,
    double scale = 1.0,
  }) async {
    try {
      final image = img.decodeImage(imageBytes);

      if (image == null) {
        print("Error: Could not decode image");
        return null;
      }

      // Clamp scale to a sensible range to avoid invalid sizes
      if (scale <= 0) {
        scale = 0.1;
      } else if (scale > 1.0) {
        scale = 1.0;
      }

      // Calculate base size for the scaled image while maintaining aspect ratio
      final aspectRatio = image.width / image.height;
      final scaledWidth = (targetWidth * scale).round().clamp(1, targetWidth);
      final scaledHeight = (scaledWidth / aspectRatio).round().clamp(1, 100000);

      // Resize source image to scaled size
      final resized = img.copyResize(
        image,
        width: scaledWidth,
        height: scaledHeight,
        interpolation: img.Interpolation.linear,
      );

      // Create a full-width canvas so the final BMP is always targetWidth wide.
      // This keeps compatibility with the glasses' expected frame width while
      // allowing the actual content to be scaled down.
      final canvas = img.Image(width: targetWidth, height: scaledHeight);

      // Fill canvas with black (background)
      img.fill(canvas, color: img.ColorRgb8(0, 0, 0));

      // Center the scaled image horizontally by copying pixels from the
      // resized image into the canvas.
      final offsetX = ((targetWidth - scaledWidth) / 2).round();
      for (int y = 0; y < scaledHeight; y++) {
        for (int x = 0; x < scaledWidth; x++) {
          final pixel = resized.getPixel(x, y);
          canvas.setPixel(offsetX + x, y, pixel);
        }
      }

      // Convert to grayscale
      final grayscale = img.grayscale(canvas);

      // Convert to 1-bit (black and white) using threshold
      final oneBit = _applyThreshold(grayscale, (threshold * 255).round());

      // Encode as 1-bit BMP with full height
      final bmpBytes = _encode1BitBmp(oneBit, targetWidth, scaledHeight);

      return {
        'bmp': bmpBytes,
        'height': scaledHeight,
      };
    } catch (e) {
      print("Error converting image bytes to full-height BMP: $e");
      return null;
    }
  }

  /// Extract a window from a BMP file
  /// Extracts a 136-pixel-high window starting at scrollPosition
  /// Returns a new BMP file (576x136)
  static Uint8List? extractBmpWindow(
    Uint8List fullBmp,
    int fullHeight,
    int width,
    int scrollPosition,
    int windowHeight,
  ) {
    try {
      // Validate inputs
      if (scrollPosition < 0 || scrollPosition + windowHeight > fullHeight) {
        print("Error: Invalid scroll position or window height");
        return null;
      }

      // Parse the full BMP to extract pixel data
      // BMP format: header (14 bytes) + DIB header (40 bytes) + palette (8 bytes) + pixel data
      const int headerSize = 14;
      const int dibHeaderSize = 40;
      const int paletteSize = 8;
      const int pixelDataOffset = headerSize + dibHeaderSize + paletteSize;

      // Calculate row size (padded to 4-byte boundary)
      int rowSize = ((width + 31) ~/ 32) * 4;

      // Create new BMP for the window (576x136)
      int windowPixelDataSize = rowSize * windowHeight;
      int windowFileSize =
          headerSize + dibHeaderSize + paletteSize + windowPixelDataSize;

      final windowBmp = ByteData(windowFileSize);
      int offset = 0;

      // BMP File Header (14 bytes)
      windowBmp.setUint8(offset++, 0x42); // 'B'
      windowBmp.setUint8(offset++, 0x4D); // 'M'
      windowBmp.setUint32(offset, windowFileSize, Endian.little);
      offset += 4;
      windowBmp.setUint32(offset, 0, Endian.little);
      offset += 4;
      windowBmp.setUint32(offset, pixelDataOffset, Endian.little);
      offset += 4;

      // DIB Header - BITMAPINFOHEADER (40 bytes)
      windowBmp.setUint32(offset, 40, Endian.little);
      offset += 4;
      windowBmp.setUint32(offset, width, Endian.little);
      offset += 4;
      windowBmp.setUint32(offset, windowHeight, Endian.little);
      offset += 4;
      windowBmp.setUint16(offset, 1, Endian.little);
      offset += 2;
      windowBmp.setUint16(offset, 1, Endian.little);
      offset += 2;
      windowBmp.setUint32(offset, 0, Endian.little);
      offset += 4;
      windowBmp.setUint32(offset, windowPixelDataSize, Endian.little);
      offset += 4;
      windowBmp.setUint32(offset, 0, Endian.little);
      offset += 4;
      windowBmp.setUint32(offset, 0, Endian.little);
      offset += 4;
      windowBmp.setUint32(offset, 2, Endian.little);
      offset += 4;
      windowBmp.setUint32(offset, 0, Endian.little);
      offset += 4;

      // Color Palette (8 bytes)
      windowBmp.setUint8(offset++, 0x00); // Black B
      windowBmp.setUint8(offset++, 0x00); // Black G
      windowBmp.setUint8(offset++, 0x00); // Black R
      windowBmp.setUint8(offset++, 0x00); // Reserved
      windowBmp.setUint8(offset++, 0xFF); // White B
      windowBmp.setUint8(offset++, 0xFF); // White G
      windowBmp.setUint8(offset++, 0xFF); // White R
      windowBmp.setUint8(offset++, 0x00); // Reserved

      // Extract pixel data from the full BMP
      // BMP stores rows bottom-to-top in file:
      // - Visual row 0 (top) is at file offset: pixelDataOffset + (fullHeight - 1) * rowSize
      // - Visual row fullHeight-1 (bottom) is at file offset: pixelDataOffset
      //
      // We want to extract visual rows from scrollPosition to scrollPosition + windowHeight - 1
      // In the window BMP, these become visual rows 0 to windowHeight - 1
      // The window BMP also stores bottom-to-top, so:
      // - Window visual row 0 (top of window) maps to window file row windowHeight - 1
      // - Window visual row windowHeight-1 (bottom of window) maps to window file row 0

      for (int i = 0; i < windowHeight; i++) {
        // Visual row in full image: scrollPosition + i (where i=0 is top of window)
        int visualRowInFull = scrollPosition + i;

        // File row index in full BMP (BMP stores bottom-to-top, so reverse)
        int fileRowInFull = fullHeight - 1 - visualRowInFull;

        // File row index in window BMP (also bottom-to-top)
        // Window visual row i (top-to-bottom) becomes window file row (windowHeight - 1 - i)
        int fileRowInWindow = windowHeight - 1 - i;

        // Calculate byte offsets
        int sourceRowOffset = pixelDataOffset + fileRowInFull * rowSize;
        int destRowOffset = pixelDataOffset + fileRowInWindow * rowSize;

        // Copy the row data
        for (int j = 0; j < rowSize; j++) {
          if (sourceRowOffset + j < fullBmp.length &&
              destRowOffset + j < windowFileSize) {
            windowBmp.setUint8(destRowOffset + j, fullBmp[sourceRowOffset + j]);
          }
        }
      }

      return windowBmp.buffer.asUint8List();
    } catch (e) {
      print("Error extracting BMP window: $e");
      return null;
    }
  }
}
