import 'package:shared_preferences/shared_preferences.dart';

class WorldTimeService {
  WorldTimeService._();
  static final WorldTimeService instance = WorldTimeService._();

  static const _enabledKey = 'worldtime_enabled';
  static const _labelKey = 'worldtime_label';
  static const _offsetKey = 'worldtime_offset_hours';

  SharedPreferences? _prefs;
  bool _enabled = false;
  String _label = 'Home';
  int _offsetHours = 0;

  Future<void> ensureReady() async {
    if (_prefs != null) return;
    _prefs = await SharedPreferences.getInstance();
    _enabled = _prefs?.getBool(_enabledKey) ?? false;
    _label = _prefs?.getString(_labelKey) ?? 'Home';
    _offsetHours = _prefs?.getInt(_offsetKey) ?? 0;
  }

  bool get enabled => _enabled;
  String get label => _label;
  int get offsetHours => _offsetHours;

  Future<void> setEnabled(bool value) async {
    await ensureReady();
    _enabled = value;
    await _prefs?.setBool(_enabledKey, value);
  }

  Future<void> setLabel(String value) async {
    await ensureReady();
    _label = value.trim().isEmpty ? 'Home' : value.trim();
    await _prefs?.setString(_labelKey, _label);
  }

  Future<void> setOffsetHours(int value) async {
    await ensureReady();
    _offsetHours = value;
    await _prefs?.setInt(_offsetKey, value);
  }

  DateTime worldTimeNow() {
    // Convert device local to UTC, then add offset hours.
    final utcNow = DateTime.now().toUtc();
    return utcNow.add(Duration(hours: _offsetHours));
  }

  String formattedTime({bool includeDay = false}) {
    final dt = worldTimeNow();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final day = includeDay ? ' ${_weekday(dt.weekday)}' : '';
    return '${_label.isEmpty ? 'Home' : _label} $hh:$mm$day';
  }

  String _weekday(int weekday) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (weekday < 1 || weekday > 7) return '';
    return names[weekday - 1];
  }
}
