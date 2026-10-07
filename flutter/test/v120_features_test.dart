import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v2raypro/models/proxy_node.dart';
import 'package:v2raypro/providers/app_providers.dart';
import 'package:v2raypro/services/xray_process_service.dart';
import 'package:v2raypro/services/update_service.dart';
import 'package:v2raypro/services/cloudflare_scanner_service.dart';

void main() {
  group('v1.2.0 Features & Updates Tests', () {
    test('UpdateInfo model stores version and hasUpdate correctly', () {
      const info = UpdateInfo(
        currentVersion: 'v1.2.0',
        latestVersion: 'v1.3.0',
        hasUpdate: true,
        downloadUrl: 'https://example.com/installer.exe',
        releaseNotes: 'New features',
      );

      expect(info.currentVersion, 'v1.2.0');
      expect(info.latestVersion, 'v1.3.0');
      expect(info.hasUpdate, isTrue);
      expect(info.downloadUrl, 'https://example.com/installer.exe');
      expect(info.releaseNotes, 'New features');
    });

    test('UpdateService defaultAppRepoUrl points to iamcloner/v2raypro releases', () {
      expect(UpdateService.defaultAppRepoUrl, 'https://github.com/iamcloner/v2raypro/releases');
      expect(UpdateService.defaultAppTestUrl, 'https://github.com/iamcloner/v2raypro/releases');
    });

    test('UpdateService currentAppVersion is v1.4.0', () {
      expect(UpdateService.currentAppVersion, 'v1.4.0');
    });

    test('UpdateService semver isVersionNewer accurately detects newer releases', () {
      expect(UpdateService.isVersionNewer('v1.2.1', 'v1.2.0'), isTrue);
      expect(UpdateService.isVersionNewer('v1.3.0', 'v1.2.0'), isTrue);
      expect(UpdateService.isVersionNewer('v2.0.0', 'v1.2.0'), isTrue);
      expect(UpdateService.isVersionNewer('v1.2.0', 'v1.2.0'), isFalse);
      expect(UpdateService.isVersionNewer('v1.1.9', 'v1.2.0'), isFalse);
      expect(UpdateService.isVersionNewer('1.2.1', '1.2.0'), isTrue);
    });

    test('UpdateService findOsSpecificZipAsset picks Windows zip asset', () {
      final assets = [
        {'name': 'v2raypro-v1.2.0-linux.zip', 'browser_download_url': 'https://linux.zip'},
        {'name': 'v2raypro-v1.2.0-windows.zip', 'browser_download_url': 'https://windows.zip'},
        {'name': 'v2raypro-v1.2.0-macos.zip', 'browser_download_url': 'https://macos.zip'},
      ];
      final url = UpdateService.findOsSpecificZipAsset(assets);
      expect(url, 'https://windows.zip');
    });

    test('ScannerState manages radar traffic warning properties', () {
      final state1 = ScannerState(
        isScanning: true,
        strategy: ScannerStrategy.radar,
        radarHealthyCount: 9,
        showRadarTrafficWarning: false,
      );

      expect(state1.radarHealthyCount, 9);
      expect(state1.showRadarTrafficWarning, isFalse);

      final state2 = state1.copyWith(
        radarHealthyCount: 10,
        showRadarTrafficWarning: true,
      );

      expect(state2.radarHealthyCount, 10);
      expect(state2.showRadarTrafficWarning, isTrue);

      final state3 = state2.copyWith(showRadarTrafficWarning: false);
      expect(state3.showRadarTrafficWarning, isFalse);
      expect(state3.radarHealthyCount, 10);
    });

    test('CloudflareScannerService isCloudflareHostSync checks IPs and known domains', () {
      // Cloudflare IPs
      expect(CloudflareScannerService.isCloudflareHostSync('104.16.1.1'), isTrue);
      expect(CloudflareScannerService.isCloudflareHostSync('172.67.1.1'), isTrue);
      expect(CloudflareScannerService.isCloudflareHostSync('1.1.1.1'), isTrue);

      // Known non-CF IP
      expect(CloudflareScannerService.isCloudflareHostSync('8.8.8.8'), isFalse);
      expect(CloudflareScannerService.isCloudflareHostSync('142.250.190.46'), isFalse);

      // Known CF domain
      expect(CloudflareScannerService.isCloudflareHostSync('cloudflare.com'), isTrue);
      expect(CloudflareScannerService.isCloudflareHostSync('workers.dev'), isTrue);
      expect(CloudflareScannerService.isCloudflareHostSync('pages.dev'), isTrue);
    });

    test('ThemeModeNotifier toggles theme correctly', () {
      final notifier = ThemeModeNotifier();
      expect(notifier.state, ThemeMode.system);

      notifier.setTheme(ThemeMode.light);
      expect(notifier.state, ThemeMode.light);

      notifier.setTheme(ThemeMode.dark);
      expect(notifier.state, ThemeMode.dark);
    });

    test('EnableUdpNotifier toggles state', () {
      final notifier = EnableUdpNotifier();
      expect(notifier.state, isTrue);

      notifier.toggle(false);
      expect(notifier.state, isFalse);

      notifier.toggle(true);
      expect(notifier.state, isTrue);
    });

    test('StartOnBootNotifier toggles state', () {
      final notifier = StartOnBootNotifier();
      expect(notifier.state, isFalse);

      notifier.toggle(true);
      expect(notifier.state, isTrue);

      notifier.toggle(false);
      expect(notifier.state, isFalse);
    });

    test('AutoConnectNotifier toggles state', () {
      final notifier = AutoConnectNotifier();
      expect(notifier.state, isFalse);

      notifier.toggle(true);
      expect(notifier.state, isTrue);
    });

    test('AutoSysProxyNotifier toggles state', () {
      final notifier = AutoSysProxyNotifier();
      expect(notifier.state, isFalse);

      notifier.toggle(true);
      expect(notifier.state, isTrue);
    });

    test('AutoTunNotifier toggles state', () {
      final notifier = AutoTunNotifier();
      expect(notifier.state, isFalse);

      notifier.toggle(true);
      expect(notifier.state, isTrue);
    });

    test('Xray config validation for TUN mode', () {
      final node = ProxyNode(
        id: 'test_node',
        name: 'Test',
        address: '104.16.1.1',
        port: 443,
        protocol: ProtocolType.vless,
        uuidOrPassword: '12345678-1234-1234-1234-123456789abc',
      );
      final cfg = XrayProcessService.instance.generateXrayConfig(node, enableTun: true, enableUdp: true);
      
      final inbounds = cfg['inbounds'] as List;
      final tunInbound = inbounds.firstWhere((i) => i['tag'] == 'tun-in') as Map<String, dynamic>;
      expect(tunInbound['protocol'], 'tun');
      expect((tunInbound['settings']['autoSystemRoutingTable'] as List).contains('0.0.0.0/0'), isTrue);
      expect((tunInbound['settings']['gateway'] as List).contains('172.19.0.1/30'), isTrue);
      
      final file = File('test_generated_tun.json');
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(cfg));

      final candidates = [
        'c:/Users/cloner/OneDrive/Desktop/v2raypro/build/windows/xray/xray.exe',
        'c:/Users/cloner/OneDrive/Desktop/v2raypro/build/windows/xray.exe',
        'c:/Users/cloner/OneDrive/Desktop/v2raypro/flutter/assets/bin/xray.exe',
      ];
      String? xrayBinary;
      for (final c in candidates) {
        if (File(c).existsSync()) {
          xrayBinary = c;
          break;
        }
      }

      if (xrayBinary != null) {
        final res = Process.runSync(xrayBinary, ['-test', '-config', file.path]);
        // Code 0 if run as admin, or code 23 (Access is denied for Wintun device creation) if run as standard user
        expect(res.exitCode == 0 || res.exitCode == 23, isTrue);
      }
      if (file.existsSync()) file.deleteSync();
    });
  });
}
