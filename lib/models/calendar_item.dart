import 'dart:convert';
import 'dart:typed_data';

/// Builds the dashboard calendar packet (0x06 subcommand) used by the G1.
/// Based on the Fahrplan implementation.
class CalendarItem {
  final String name;
  final String time;
  final String location;
  final String? titleOverride;

  CalendarItem({
    required this.name,
    required this.time,
    required this.location,
    this.titleOverride,
  });

  Uint8List buildPacket() {
    // Fixed bytes observed in Fahrplan's implementation.
    final bytes = <int>[
      0x00,
      0x6d,
      0x03,
      0x01,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x03,
      0x01,
    ];

    // Tag 0x01: event name (allows custom title formatting)
    final title = titleOverride ?? name;
    final titleBytes = utf8.encode(title);
    bytes.add(0x01);
    bytes.add(titleBytes.length);
    bytes.addAll(titleBytes);

    // Tag 0x02: time string
    if (time.isNotEmpty) {
      final timeBytes = utf8.encode(time);
      bytes.add(0x02);
      bytes.add(timeBytes.length);
      bytes.addAll(timeBytes);
    }

    // Tag 0x03: location string
    if (location.isNotEmpty) {
      final locationBytes = utf8.encode(location);
      bytes.add(0x03);
      bytes.add(locationBytes.length);
      bytes.addAll(locationBytes);
    }

    final length = bytes.length + 2;
    final header = <int>[0x06, length];
    return Uint8List.fromList(header + bytes);
  }
}
