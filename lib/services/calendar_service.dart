import 'dart:typed_data';

import 'package:get/get.dart';

import '../ble_manager.dart';
import '../controllers/weather_controller.dart';
import '../models/calendar_item.dart';
import 'proto.dart';

class CalendarService {
  static CalendarService? _instance;
  static CalendarService get instance => _instance ??= CalendarService._();

  CalendarService._();

  /// Send a calendar item to the dashboard calendar pane.
  /// This uses the 0x06 subcommand observed in Fahrplan’s implementation.
  Future<bool> sendCalendarItem({
    required String name,
    required String time,
    required String location,
    String? titleOverride,
    bool fullSync = false,
  }) async {
    if (!BleManager.get().isConnected) return false;

    if (fullSync) {
      await Proto.setDashboardMode(modeId: 0);
      await Proto.setTimeAndWeather(weatherIconId: 0x00, temperature: 0);
      await Future.delayed(const Duration(milliseconds: 300));
    } else {
      await Proto.setDashboardMode(modeId: 0);
    }

    final packet = CalendarItem(
      name: name,
      time: time,
      location: location,
      titleOverride: titleOverride,
    ).buildPacket();

    // Send to both arms; no strict ACK format documented, so use best-effort.
    final left = await BleManager.request(packet, lr: "L", timeoutMs: 1500);
    final right = await BleManager.request(packet, lr: "R", timeoutMs: 1500);
    final okLeft = !left.isTimeout && left.data.isNotEmpty;
    final okRight = !right.isTimeout && right.data.isNotEmpty;

    if (fullSync) {
      await Future.delayed(const Duration(milliseconds: 300));
      await Proto.setDashboardMode(modeId: 0);
      await Proto.setTimeAndWeather(weatherIconId: 0x00, temperature: 0);
      await _restoreWeatherIfAvailable();
    }

    return okLeft && okRight;
  }

  Future<void> _restoreWeatherIfAvailable() async {
    if (!Get.isRegistered<WeatherController>()) return;
    final weatherController = Get.find<WeatherController>();
    final data = weatherController.weatherData.value;
    if (data == null) return;
    final temp = data.temperature.round().clamp(-128, 127);
    await Proto.setTimeAndWeather(
      weatherIconId: data.weatherIconId,
      temperature: temp,
      useFahrenheit: weatherController.useFahrenheit.value,
      use12HourFormat: weatherController.use12HourFormat.value,
    );
  }
}
