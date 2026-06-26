import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LogLevel { info, ok, warn, error }

class LogEntry {
  LogEntry(this.time, this.level, this.tag, this.message);

  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;

  Map<String, dynamic> toJson() => {
        't': time.toIso8601String(),
        'l': level.name,
        'g': tag,
        'm': message,
      };

  static LogEntry fromJson(Map<String, dynamic> j) => LogEntry(
        DateTime.tryParse(j['t']?.toString() ?? '') ?? DateTime.now(),
        LogLevel.values.firstWhere((e) => e.name == j['l'], orElse: () => LogLevel.info),
        (j['g'] ?? '').toString(),
        (j['m'] ?? '').toString(),
      );
}

/// Log do app (eventos de conexão, autorização, sincronização e erros).
/// Singleton com persistência local, para o vendedor/suporte ver o que houve.
class AppLog extends ChangeNotifier {
  AppLog._();

  static final AppLog instance = AppLog._();

  static const _key = 'unitec_fv_log';
  static const _max = 400;

  final List<LogEntry> _entries = [];

  /// Mais recentes primeiro.
  List<LogEntry> get entries => _entries.reversed.toList(growable: false);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        _entries
          ..clear()
          ..addAll(list.map((e) => LogEntry.fromJson(Map<String, dynamic>.from(e as Map))));
      }
    } catch (_) {}
    notifyListeners();
  }

  void info(String tag, String m) => _add(LogLevel.info, tag, m);
  void ok(String tag, String m) => _add(LogLevel.ok, tag, m);
  void warn(String tag, String m) => _add(LogLevel.warn, tag, m);
  void error(String tag, String m) => _add(LogLevel.error, tag, m);

  void _add(LogLevel level, String tag, String message) {
    _entries.add(LogEntry(DateTime.now(), level, tag, message));
    if (_entries.length > _max) {
      _entries.removeRange(0, _entries.length - _max);
    }
    notifyListeners();
    _scheduleSave();
  }

  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  String exportText() {
    return _entries.map((e) {
      final t = e.time.toIso8601String();
      return '[$t] ${e.level.name.toUpperCase()} ${e.tag}: ${e.message}';
    }).join('\n');
  }

  bool _saveScheduled = false;

  void _scheduleSave() {
    if (_saveScheduled) return;
    _saveScheduled = true;
    // Agrupa gravações em rajada (ex.: várias entradas numa sincronização).
    Future<void>.delayed(const Duration(milliseconds: 400), () async {
      _saveScheduled = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        final data = _entries.map((e) => e.toJson()).toList();
        await prefs.setString(_key, jsonEncode(data));
      } catch (_) {}
    });
  }
}
