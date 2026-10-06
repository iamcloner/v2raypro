import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:v2raypro/providers/app_providers.dart';
import 'package:v2raypro/services/cloudflare_scanner_service.dart';

void main() {
  group('Cloudflare Scanner Strategy Tests', () {
    test('generateCandidateIps produces expected count and unique IPs', () {
      final customCidrs = ['104.18.0.0/16', '104.17.0.0/16'];
      final candidates = CloudflareScannerService.generateCandidateIps(
        count: 25,
        cidrs: customCidrs,
        rng: Random(123),
      );

      expect(candidates.length, equals(25));
      // All items must be unique
      expect(candidates.toSet().length, equals(25));

      // Each candidate must belong to Cloudflare CIDR
      for (final ip in candidates) {
        expect(CloudflareScannerService.isCloudflareIp(ip, customCidrs), isTrue);
      }
    });

    test('generateCandidateIps works with threshold slider range 5 to 100', () {
      for (final threshold in [5, 10, 50, 100]) {
        final candidates = CloudflareScannerService.generateCandidateIps(
          count: threshold,
          rng: Random(42),
        );
        expect(candidates.length, equals(threshold));
        expect(candidates.toSet().length, equals(threshold));
      }
    });

    test('ScannerState manages radar logs and strategies correctly', () {
      final state = ScannerState(
        strategy: ScannerStrategy.radar,
        threshold: 40,
      );

      expect(state.strategy, equals(ScannerStrategy.radar));
      expect(state.threshold, equals(40));
      expect(state.radarLogs, isEmpty);

      // Add Radar log improvement
      final log1 = RadarLogEntry(
        ip: '104.18.1.1',
        latencyMs: 180,
        timestamp: DateTime.now(),
      );
      final log2 = RadarLogEntry(
        ip: '104.18.2.2',
        latencyMs: 95,
        timestamp: DateTime.now(),
        improvementMs: 85,
      );

      final updated = state.copyWith(
        radarLogs: [log2, log1],
        connectedIp: '104.18.2.2',
        currentBestLatency: 95,
      );

      expect(updated.radarLogs.length, equals(2));
      expect(updated.radarLogs.first.improvementMs, equals(85));
      expect(updated.connectedIp, equals('104.18.2.2'));
      expect(updated.currentBestLatency, equals(95));
    });

    test('ScannerState manages targetTotalCandidates slider range 200 to 10000', () {
      final state = ScannerState(
        strategy: ScannerStrategy.target,
        workers: 30,
        targetTotalCandidates: 1000,
      );

      expect(state.strategy, equals(ScannerStrategy.target));
      expect(state.workers, equals(30));
      expect(state.targetTotalCandidates, equals(1000));

      final updated = state.copyWith(targetTotalCandidates: 5000);
      expect(updated.targetTotalCandidates, equals(5000));
    });
  });
}

