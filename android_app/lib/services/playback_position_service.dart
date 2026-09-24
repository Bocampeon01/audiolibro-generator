import 'package:shared_preferences/shared_preferences.dart';

class PlaybackPositionService {
  static const _speedKey = 'playback_speed';

  String _key(String bookId) => 'resume_pos::$bookId';

  Future<Duration?> loadPosition(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_key(bookId));
    if (ms == null) return null;
    return Duration(milliseconds: ms);
  }

  Future<void> savePosition(String bookId, Duration position) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(bookId), position.inMilliseconds);
  }

  Future<void> clear(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(bookId));
  }

  Future<double> loadSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_speedKey) ?? 1.0;
  }

  Future<void> saveSpeed(double speed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_speedKey, speed);
  }
}
