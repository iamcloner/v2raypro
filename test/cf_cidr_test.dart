import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:v2raypro/services/cloudflare_scanner_service.dart';

void main() {
  test('Cloudflare CIDR sampler generates valid IPv4 from CIDR', () {
    final rng = Random(42);
    
    // Sample /16
    for (int i = 0; i < 50; i++) {
      final ip = CloudflareScannerService.sampleIpFromCidr('104.18.0.0/16', rng);
      final parts = ip.split('.').map(int.parse).toList();
      expect(parts.length, equals(4));
      expect(parts[0], equals(104));
      expect(parts[1], equals(18));
      expect(parts[2], inInclusiveRange(0, 255));
      expect(parts[3], inInclusiveRange(0, 255));
    }

    // Sample /13 (e.g. 104.16.0.0/13 spans 104.16.0.0 to 104.23.255.255)
    for (int i = 0; i < 50; i++) {
      final ip = CloudflareScannerService.sampleIpFromCidr('104.16.0.0/13', rng);
      final parts = ip.split('.').map(int.parse).toList();
      expect(parts[0], equals(104));
      expect(parts[1], inInclusiveRange(16, 23));
    }
  });
}
