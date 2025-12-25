import 'dart:convert';
import 'dart:typed_data';

class TeleprompterProtocol {
  static const int cmdTeleprompter = 0x09;
  static const int cmdTeleprompterEnd = 0x06;
  static const int teleprompterSubCmd = 0x05;
  static const int teleprompterFinish = 0x01;

  static const int controlSize = 10;
  static const int headerSize = 2;

  static const int reserved = 0x00;
  static const int newScreenNormal = 0x01;
  static const int newScreenManual = 0x03;
  static const int newScreenContinuation = 0x07;
  static const int flagsNormal = 0x81;
  static const int flagsManual = 0x00;
  static const int countdown = 0x01;
  static const int defaultScrollPosition = 0;

  static Uint8List buildTeleprompterValue({
    required int sequence,
    required int numPackets,
    required int partIndex,
    required Uint8List payload,
    int slidePercentage = defaultScrollPosition,
    bool manualMode = false,
    int? newScreenOverride,
    int? flagsOverride,
  }) {
    final newScreen =
        newScreenOverride ?? (manualMode ? newScreenManual : newScreenNormal);
    final flags = flagsOverride ?? (manualMode ? flagsManual : flagsNormal);
    final clampedSlide = slidePercentage.clamp(0, 100);

    final control = Uint8List.fromList([
      reserved,
      sequence & 0xFF,
      newScreen & 0xFF,
      numPackets & 0xFF,
      reserved,
      partIndex & 0xFF,
      reserved,
      countdown & 0xFF,
      flags & 0xFF,
      clampedSlide & 0xFF,
    ]);

    final totalLength = headerSize + controlSize + payload.length;
    if (totalLength > 255) {
      throw ArgumentError(
        'Teleprompter value too large: $totalLength > 255 bytes',
      );
    }

    final packet = Uint8List(totalLength);
    packet[0] = cmdTeleprompter;
    packet[1] = totalLength & 0xFF;
    packet.setRange(headerSize, headerSize + controlSize, control);
    packet.setRange(
      headerSize + controlSize,
      totalLength,
      payload,
    );

    return packet;
  }

  static List<Uint8List> buildTeleprompterPackets({
    required String visibleText,
    required String nextText,
    required int sequence,
    int? slidePercentage,
    bool manualMode = false,
    bool updateMode = false,
  }) {
    final packets = <Uint8List>[];
    final visiblePayload = Uint8List.fromList(utf8.encode(visibleText));
    final nextPayload =
        nextText.trim().isEmpty ? Uint8List(0) : Uint8List.fromList(utf8.encode(nextText));

    final hasNext = nextPayload.isNotEmpty;

    final newScreenOverride = updateMode ? newScreenContinuation : null;
    final flagsOverride = updateMode ? flagsNormal : null;
    packets.add(
      buildTeleprompterValue(
        sequence: sequence,
        numPackets: hasNext ? 2 : 1,
        partIndex: 1,
        payload: visiblePayload,
        slidePercentage: slidePercentage ?? defaultScrollPosition,
        manualMode: manualMode,
        newScreenOverride: newScreenOverride,
        flagsOverride: flagsOverride,
      ),
    );

    if (hasNext) {
      packets.add(
        buildTeleprompterValue(
          sequence: (sequence + 1) & 0xFF,
          numPackets: 2,
          partIndex: 2,
          payload: nextPayload,
          slidePercentage: slidePercentage ?? defaultScrollPosition,
          manualMode: manualMode,
          newScreenOverride: newScreenOverride,
          flagsOverride: flagsOverride,
        ),
      );
    }

    return packets;
  }

  static Uint8List buildTeleprompterEndPacket(int sequence) {
    return Uint8List.fromList([
      cmdTeleprompter,
      cmdTeleprompterEnd,
      reserved,
      sequence & 0xFF,
      teleprompterSubCmd,
      teleprompterFinish,
    ]);
  }
}
