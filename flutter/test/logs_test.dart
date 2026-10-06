import "package:flutter_test/flutter_test.dart";
import "package:v2raypro/models/log_entry.dart";
import "package:v2raypro/services/log_service.dart";

void main() {
  group("LogEntry & LogLevel Tests", () {
    test("LogEntry detects levels correctly from raw lines", () {
      expect(LogEntry.parseLevel("2026/10/06 12:00:00 [Warning] core: failed to connect"), LogLevel.warning);
      expect(LogEntry.parseLevel("2026/10/06 12:00:00 [Error] app/proxyman: failed to listen on port 10888"), LogLevel.error);
      expect(LogEntry.parseLevel("2026/10/06 12:00:00 tcp:127.0.0.1:54321 accepted tcp:google.com:443"), LogLevel.access);
      expect(LogEntry.parseLevel("2026/10/06 12:00:00 [Info] infra/conf/serial: reading config file"), LogLevel.info);
    });

    test("LogEntry formats timestamp properly", () {
      final entry = LogEntry(
        message: "Test message",
        timestamp: DateTime(2026, 10, 6, 14, 5, 9, 123),
      );
      expect(entry.formattedTime(), "14:05:09.123");
    });
  });

  group("LogService Tests", () {
    setUp(() {
      LogService.instance.clear();
    });

    test("LogService records logs and stream emits events", () async {
      final logsEmitted = <LogEntry>[];
      final sub = LogService.instance.onNewLog.listen(logsEmitted.add);

      LogService.instance.add("System initialized", level: LogLevel.info, source: "system");
      LogService.instance.addFromRawLine("tcp:127.0.0.1 accepted tcp:example.com:443");

      await Future.delayed(const Duration(milliseconds: 10));

      expect(LogService.instance.logs.length, 2);
      expect(LogService.instance.logs[0].message, "System initialized");
      expect(LogService.instance.logs[0].level, LogLevel.info);
      expect(LogService.instance.logs[0].source, "system");

      expect(LogService.instance.logs[1].level, LogLevel.access);
      expect(LogService.instance.logs[1].source, "xray");

      expect(logsEmitted.length, 2);

      await sub.cancel();
    });

    test("LogService clear removes all entries", () {
      LogService.instance.add("Log 1");
      LogService.instance.add("Log 2");
      expect(LogService.instance.logs.length, 2);

      LogService.instance.clear();
      expect(LogService.instance.logs.isEmpty, true);
    });
  });
}
