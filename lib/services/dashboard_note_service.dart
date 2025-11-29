import 'dart:convert';
import 'dart:typed_data';

import '../ble_manager.dart';
import 'proto.dart';

class DashboardNoteService {
  static DashboardNoteService? _instance;
  static DashboardNoteService get instance =>
      _instance ??= DashboardNoteService._();

  DashboardNoteService._();

  /// Send a dashboard note into a numbered quick-note slot (1-4).
  /// Uses the Quick Note Add (0x1E) command observed in the Fahrplan app.
  Future<bool> sendDashboardNote({
    required String title,
    required String text,
    int noteNumber = 1,
  }) async {
    if (!BleManager.get().isConnected) {
      return false;
    }

    final packet = _buildAddCommand(
      noteNumber: noteNumber,
      title: title,
      text: text,
    );

    return await _sendToBoth(packet);
  }

  /// Clear a numbered note slot by sending the delete command.
  Future<void> clearNote({int noteNumber = 1}) async {
    if (!BleManager.get().isConnected) return;
    final packet = _buildDeleteCommand(noteNumber);
    await _sendToBoth(packet);
  }

  Future<bool> _sendToBoth(Uint8List data) async {
    // Send to left with a best-effort ack check.
    final left = await BleManager.request(data, lr: "L", timeoutMs: 1500);
    final leftOk = !left.isTimeout;

    // Send to right; if it times out, fall back to a raw send.
    final right = await BleManager.request(data, lr: "R", timeoutMs: 1500);
    bool rightOk = !right.isTimeout;
    if (!rightOk) {
      await BleManager.sendData(data, lr: "R");
      rightOk = true; // best-effort fire-and-forget
    }

    return leftOk && rightOk;
  }

  Uint8List _buildAddCommand({
    required int noteNumber,
    required String title,
    required String text,
  }) {
    if (noteNumber < 1 || noteNumber > 4) {
      throw ArgumentError('Note number must be between 1 and 4');
    }

    final nameBytes = Uint8List.fromList(utf8.encode(title));
    final textBytes = Uint8List.fromList(utf8.encode(text));
    final fixedBytes = Uint8List.fromList([0x03, 0x01, 0x00, 0x01, 0x00]);
    final versioningByte = DateTime.now().millisecondsSinceEpoch ~/ 1000 % 256;

    // Compute payload length matching Fahrplan format
    final payloadLength = [
      1, // fixed byte
      1, // versioning byte
      fixedBytes.length,
      1, // note number
      1, // fixed byte 2
      1, // title length
      nameBytes.length,
      1, // text length
      1, // fixed byte after text length
      textBytes.length,
      2, // final bytes
    ].reduce((a, b) => a + b);

    final command = <int>[
      0x1E, // QUICK_NOTE_ADD
      payloadLength & 0xFF,
      0x00, // fixed byte
      versioningByte,
      ...fixedBytes,
      noteNumber,
      0x01, // fixed byte 2
      nameBytes.length & 0xFF,
      ...nameBytes,
      textBytes.length & 0xFF,
      0x00, // fixed byte after text length
      ...textBytes,
    ];

    return Uint8List.fromList(command);
  }

  Uint8List _buildDeleteCommand(int noteNumber) {
    return Uint8List.fromList([
      0x1E,
      0x10,
      0x00,
      0xE0,
      0x03,
      0x01,
      0x00,
      0x01,
      0x00,
      noteNumber,
      0x00,
      0x01,
      0x00,
      0x01,
      0x00,
      0x00,
    ]);
  }
}
