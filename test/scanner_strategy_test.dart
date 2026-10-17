import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:v2raypro/models/scan_result.dart';
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

    test('Radar mode accumulates all discovered responsive IPs and supports manual switch', () {
      final state = ScannerState(
        strategy: ScannerStrategy.radar,
        workers: 10,
        connectedIp: '104.18.1.1',
        currentBestLatency: 120,
      );

      final r1 = ScanResult(
        ip: '104.18.1.1',
        port: 443,
        tcpSuccess: true,
        tcpLatencyMs: 120,
        tlsSuccess: true,
        protocolSuccess: true,
        totalLatencyMs: 120,
        rankScore: 120.0,
      );
      final r2 = ScanResult(
        ip: '104.18.2.2',
        port: 443,
        tcpSuccess: true,
        tcpLatencyMs: 65,
        tlsSuccess: true,
        protocolSuccess: true,
        totalLatencyMs: 65,
        rankScore: 65.0,
      );
      final r3 = ScanResult(
        ip: '104.18.3.3',
        port: 443,
        tcpSuccess: true,
        tcpLatencyMs: 150,
        tlsSuccess: true,
        protocolSuccess: true,
        totalLatencyMs: 150,
        rankScore: 150.0,
      );

      // Radar collects all healthy IPs, sorted by latency ascending
      final List<ScanResult> allHealthy = [r2, r1, r3];
      final radarState = state.copyWith(
        results: allHealthy,
        bestIp: r2,
        connectedIp: r2.ip, // auto-connected to best
        currentBestLatency: 65,
      );

      expect(radarState.results.length, equals(3));
      expect(radarState.results[0].ip, equals('104.18.2.2'));
      expect(radarState.results[1].ip, equals('104.18.1.1'));
      expect(radarState.results[2].ip, equals('104.18.3.3'));
      expect(radarState.connectedIp, equals('104.18.2.2'));

      // Manual switch to r1 ('104.18.1.1')
      final switchedState = radarState.copyWith(connectedIp: r1.ip);
      expect(switchedState.connectedIp, equals('104.18.1.1'));
      // All 3 results still preserved
      expect(switchedState.results.length, equals(3));
    });
  });
}

