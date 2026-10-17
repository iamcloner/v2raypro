import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/ip_mask_util.dart';

void main() {
  group('IpMaskUtil Tests', () {
    test('masks IPv4 address correctly', () {
      expect(IpMaskUtil.mask('104.28.12.34'), '104.28.***.***');
      expect(IpMaskUtil.mask('1.1.1.1'), '1.1.***.***');
    });

    test('masks IPv4 address with port correctly', () {
      expect(IpMaskUtil.mask('104.28.12.34:443'), '104.28.***.***:443');
      expect(IpMaskUtil.mask('172.67.182.1:8443'), '172.67.***.***:8443');
    });

    test('masks IPv6 address correctly', () {
      final masked = IpMaskUtil.mask('2606:4700:4700::1111');
      expect(masked.contains('***'), isTrue);
      expect(masked.startsWith('2606:4700'), isTrue);
    });

    test('masks domain names correctly', () {
      final masked = IpMaskUtil.mask('sub.example.com');
      expect(masked.contains('***'), isTrue);
    });

    test('reveals full address when showFull is true', () {
      expect(IpMaskUtil.mask('104.28.12.34', showFull: true), '104.28.12.34');
      expect(IpMaskUtil.mask('104.28.12.34:443', showFull: true), '104.28.12.34:443');
      expect(IpMaskUtil.mask('sub.example.com', showFull: true), 'sub.example.com');
    });

    test('handles empty or short inputs gracefully', () {
      expect(IpMaskUtil.mask(''), '');
      expect(IpMaskUtil.mask('   '), '   ');
    });
  });
}
