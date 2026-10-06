import "dart:async";
import "../models/log_entry.dart";

class LogService {
  static final LogService instance = LogService._();
  LogService._();

  static const int maxCapacity = 1000;
  final List<LogEntry> _entries = [];
  final StreamController<LogEntry> _controller = StreamController<LogEntry>.broadcast();

  Stream<LogEntry> get onNewLog => _controller.stream;
  List<LogEntry> get logs => List<LogEntry>.from(_entries);

  void add(String message, {LogLevel level = LogLevel.info, String source = "system"}) {
    if (message.trim().isEmpty) return;
    final entry = LogEntry(
      message: message.trim(),
      level: level,
      source: source,
      timestamp: DateTime.now(),
    );
    _append(entry);
  }

  void addFromRawLine(String rawLine, {String source = "xray"}) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) return;
    final level = LogEntry.parseLevel(trimmed);
    final entry = LogEntry(
      message: trimmed,
      level: level,
      source: source,
      timestamp: DateTime.now(),
    );
    _append(entry);
  }

  void _append(LogEntry entry) {
    if (_entries.length >= maxCapacity) {
      _entries.removeRange(0, _entries.length - maxCapacity + 1);
    }
    _entries.add(entry);
    _controller.add(entry);
  }

  void clear() {
    _entries.clear();
    // Dispatch a dummy sentinel or state reset through provider
  }
}
