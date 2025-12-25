import 'dart:typed_data';

import '../ble_manager.dart';
import 'proto.dart';
import 'teleprompter_font_metrics.dart';
import 'teleprompter_protocol.dart';
import 'teleprompter_text_processor.dart';

class TeleprompterService {
  static final TeleprompterService instance = TeleprompterService._();
  static bool isActive = false;

  TeleprompterService._();

  static const int _packetDelayMs = 10;
  int _sequence = 0;

  Future<bool> sendTeleprompterText(
    String text, {
    int? slidePercentage,
    bool exitBeforeSend = false,
    bool manualMode = false,
    bool updateMode = false,
    String? formattedText,
    int? scrollPercent,
  }) async {
    if (!BleManager.get().isConnected) {
      return false;
    }

    if (exitBeforeSend) {
      await Proto.exit();
    }

    final formatted = formattedText ??
        TeleprompterTextProcessor.addLineBreaksWithMetrics(
          text,
          await TeleprompterFontMetrics.load(),
          maxWidth: 180,
        );
    final scopedText = scrollPercent == null
        ? formatted
        : TeleprompterTextProcessor.sliceFormattedTextAtPercent(
            formatted,
            scrollPercent,
          );
    final split = TeleprompterTextProcessor.splitTextForTeleprompter(scopedText);

    final packets = TeleprompterProtocol.buildTeleprompterPackets(
      visibleText: split.visible,
      nextText: split.next,
      sequence: _sequence,
      slidePercentage: slidePercentage,
      manualMode: manualMode,
      updateMode: updateMode,
    );

    _sequence = (_sequence + packets.length) & 0xFF;

    final leftOk = await _sendPackets('L', packets);
    await Future.delayed(const Duration(milliseconds: 40));
    final rightOk = await _sendPackets('R', packets);
    if (leftOk && rightOk) {
      isActive = true;
    }
    return leftOk && rightOk;
  }

  Future<bool> exitTeleprompter() async {
    if (!BleManager.get().isConnected) {
      return false;
    }

    final packet = TeleprompterProtocol.buildTeleprompterEndPacket(_sequence);
    final leftOk = await _sendPacket('L', packet);
    final rightOk = await _sendPacket('R', packet);
    if (leftOk && rightOk) {
      isActive = false;
    }
    return leftOk && rightOk;
  }

  Future<bool> _sendPackets(String lr, List<Uint8List> packets) async {
    for (var i = 0; i < packets.length; i++) {
      final ok = await _sendPacket(lr, packets[i]);
      if (!ok) {
        return false;
      }
      if (i < packets.length - 1) {
        await Future.delayed(const Duration(milliseconds: _packetDelayMs));
      }
    }
    return true;
  }

  Future<bool> _sendPacket(String lr, Uint8List packet) async {
    final result = await BleManager.sendData(packet, lr: lr);
    if (result != false) {
      return true;
    }
    await Future.delayed(const Duration(milliseconds: 20));
    final retry = await BleManager.sendData(packet, lr: lr);
    return retry != false;
  }
}
