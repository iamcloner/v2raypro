enum LogLevel {
  info,
  warning,
  error,
  access,
}

class LogEntry {
  final String id;
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String source;

  LogEntry({
    String? id,
    DateTime? timestamp,
    this.level = LogLevel.info,
    required this.message,
    this.source = "xray",
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp = timestamp ?? DateTime.now();

  String formattedTime() {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return "$h:$m:$s.$ms";
  }

  static LogLevel parseLevel(String line) {
    final lower = line.toLowerCase();
    if (lower.contains("[warning]") || lower.contains("warning:") || lower.contains("warn:")) {
      return LogLevel.warning;
    }
    if (lower.contains("[error]") ||
        lower.contains("error:") ||
        lower.contains("panic:") ||
        lower.contains("fatal:") ||
        lower.contains("failed to start") ||
        lower.contains("failed to listen") ||
        lower.contains("exited with code") && !lower.contains("code 0")) {
      return LogLevel.error;
    }
    if (lower.contains("accepted") || lower.contains("[access]") || lower.contains("proxy/socks") || lower.contains("proxy/http")) {
      return LogLevel.access;
    }
    return LogLevel.info;
  }
}
