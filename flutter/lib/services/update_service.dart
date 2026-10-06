import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'xray_process_service.dart';

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;
  final String? downloadUrl;
  final String? releaseNotes;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.hasUpdate,
    this.downloadUrl,
    this.releaseNotes,
  });
}

class UpdateService {
  static final UpdateService instance = UpdateService._internal();
  UpdateService._internal();

  static const String currentAppVersion = "v1.2.0";
  static const String defaultAppTestUrl = "https://raw.githubusercontent.com/v2raypro/v2raypro/main/version.json";

  HttpClient _createHttpClient() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    // If proxy is active, route through local proxy fallback
    if (XrayProcessService.instance.state == EngineState.running) {
      client.findProxy = (uri) => "PROXY 127.0.0.1:${XrayProcessService.instance.httpPort}; DIRECT";
    }
    return client;
  }

  /// Get currently installed Xray core version
  Future<String> getCurrentXrayVersion() async {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        "$exeDir/xray/xray.exe",
        "xray/xray.exe",
        "xray.exe",
        "assets/bin/xray.exe",
        "$exeDir/xray.exe",
        "$exeDir/assets/bin/xray.exe",
        "$exeDir/data/flutter_assets/assets/bin/xray.exe",
        "flutter/assets/bin/xray.exe",
      ];
      String? binary;
      for (final c in candidates) {
        if (File(c).existsSync()) {
          binary = c;
          break;
        }
      }
      if (binary == null) return "Unknown";

      final res = await Process.run(binary, ["version"]);
      final out = res.stdout.toString();
      final match = RegExp(r"Xray\s+([\d\.]+)").firstMatch(out);
      if (match != null) {
        return "v${match.group(1)}";
      }
      return out.split('\n').first.trim();
    } catch (_) {
      return "v26.6.1";
    }
  }

  /// Check for Xray Core updates from official GitHub repository
  Future<UpdateInfo> checkXrayUpdate() async {
    final current = await getCurrentXrayVersion();
    final client = _createHttpClient();

    try {
      final req = await client.getUrl(Uri.parse("https://api.github.com/repos/XTLS/Xray-core/releases?per_page=10"));
      req.headers.set(HttpHeaders.userAgentHeader, "V2RayPro-Client/1.2.0");
      req.headers.set(HttpHeaders.acceptHeader, "application/vnd.github.v3+json");

      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final list = jsonDecode(body) as List<dynamic>;
        if (list.isNotEmpty) {
          final json = list.first as Map<String, dynamic>;
          final tagName = (json["tag_name"] as String? ?? "").trim();
          final bodyNotes = json["body"] as String? ?? "";
          final assets = (json["assets"] as List<dynamic>? ?? []);

          String? downloadUrl;
          for (final a in assets) {
            final name = (a["name"] as String? ?? "").toLowerCase();
            if (name.contains("windows-64.zip") || name.contains("windows-amd64.zip")) {
              downloadUrl = a["browser_download_url"] as String?;
              break;
            }
          }

          final cleanCurrent = current.replaceAll('v', '').trim();
          final cleanLatest = tagName.replaceAll('v', '').trim();
          final hasUpdate = cleanLatest.isNotEmpty && cleanLatest != cleanCurrent;

          return UpdateInfo(
            currentVersion: current,
            latestVersion: tagName.isNotEmpty ? tagName : current,
            hasUpdate: hasUpdate,
            downloadUrl: downloadUrl,
            releaseNotes: bodyNotes,
          );
        }
      }
    } catch (e) {
      debugPrint("checkXrayUpdate error: $e");
    } finally {
      client.close();
    }

    return UpdateInfo(
      currentVersion: current,
      latestVersion: current,
      hasUpdate: false,
    );
  }

  /// Download and update Xray core binary
  Future<bool> updateXray(String downloadUrl, {void Function(double progress)? onProgress}) async {
    final client = _createHttpClient();
    try {
      final tempDir = await getTemporaryDirectory();
      final zipFile = File("${tempDir.path}\\xray_update_${DateTime.now().millisecondsSinceEpoch}.zip");
      final extractDir = Directory("${tempDir.path}\\xray_extracted_${DateTime.now().millisecondsSinceEpoch}");

      final req = await client.getUrl(Uri.parse(downloadUrl));
      req.headers.set(HttpHeaders.userAgentHeader, "V2RayPro-Client/1.2.0");
      final res = await req.close();
      if (res.statusCode != 200) return false;

      final totalBytes = res.contentLength;
      int receivedBytes = 0;
      final sink = zipFile.openWrite();

      await for (final chunk in res) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0 && onProgress != null) {
          onProgress(receivedBytes / totalBytes);
        }
      }
      await sink.flush();
      await sink.close();

      // Extract zip using PowerShell
      await extractDir.create(recursive: true);
      final psCmd = 'Expand-Archive -Path "${zipFile.path}" -DestinationPath "${extractDir.path}" -Force';
      final extRes = await Process.run('powershell', ['-NoProfile', '-Command', psCmd]);
      if (extRes.exitCode != 0) return false;

      // Locate extracted xray.exe
      File? newXray;
      for (final f in extractDir.listSync(recursive: true)) {
        if (f is File && f.path.toLowerCase().endsWith('xray.exe')) {
          newXray = f;
          break;
        }
      }
      if (newXray == null) return false;

      // Overwrite target binaries
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final targets = [
        "$exeDir/xray/xray.exe",
        "xray/xray.exe",
        "$exeDir/xray.exe",
        "$exeDir/data/flutter_assets/assets/bin/xray.exe",
        "flutter/assets/bin/xray.exe",
        "assets/bin/xray.exe",
      ];

      for (final t in targets) {
        final f = File(t);
        if (f.existsSync()) {
          try {
            await newXray.copy(t);
          } catch (_) {}
        }
      }

      // Cleanup
      try {
        await zipFile.delete();
        await extractDir.delete(recursive: true);
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint("updateXray failed: $e");
      return false;
    } finally {
      client.close();
    }
  }

  /// Check Geo files status
  Future<UpdateInfo> checkGeoUpdate() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final geoipCandidates = [
      File("$exeDir/xray/geoip.dat"),
      File("xray/geoip.dat"),
      File("$exeDir/geoip.dat"),
    ];
    String current = "Installed";
    for (final geoip in geoipCandidates) {
      if (geoip.existsSync()) {
        final modified = geoip.lastModifiedSync();
        current = "${modified.year}-${modified.month.toString().padLeft(2, '0')}-${modified.day.toString().padLeft(2, '0')}";
        break;
      }
    }

    final client = _createHttpClient();
    try {
      final req = await client.getUrl(Uri.parse("https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases/latest"));
      req.headers.set(HttpHeaders.userAgentHeader, "V2RayPro-Client/1.2.0");
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final tagName = (json["tag_name"] as String? ?? "").trim();
        return UpdateInfo(
          currentVersion: current,
          latestVersion: tagName.isNotEmpty ? tagName : "Latest Release",
          hasUpdate: true,
          downloadUrl: "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download",
        );
      }
    } catch (e) {
      debugPrint("checkGeoUpdate error: $e");
    } finally {
      client.close();
    }

    return UpdateInfo(
      currentVersion: current,
      latestVersion: "Available on GitHub",
      hasUpdate: true,
      downloadUrl: "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download",
    );
  }

  /// Download and update geoip.dat and geosite.dat
  Future<bool> updateGeoFiles({void Function(double progress)? onProgress}) async {
    final client = _createHttpClient();
    try {
      final tempDir = await getTemporaryDirectory();
      final geoipUrl = "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat";
      final geositeUrl = "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat";

      final tempGeoip = File("${tempDir.path}\\geoip_temp.dat");
      final tempGeosite = File("${tempDir.path}\\geosite_temp.dat");

      // Download geoip
      final req1 = await client.getUrl(Uri.parse(geoipUrl));
      final res1 = await req1.close();
      if (res1.statusCode != 200 && res1.statusCode != 302) return false;
      final sink1 = tempGeoip.openWrite();
      await res1.pipe(sink1);
      if (onProgress != null) onProgress(0.5);

      // Download geosite
      final req2 = await client.getUrl(Uri.parse(geositeUrl));
      final res2 = await req2.close();
      if (res2.statusCode != 200 && res2.statusCode != 302) return false;
      final sink2 = tempGeosite.openWrite();
      await res2.pipe(sink2);
      if (onProgress != null) onProgress(1.0);

      // Overwrite targets
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final geoipTargets = [
        "$exeDir/xray/geoip.dat",
        "xray/geoip.dat",
        "$exeDir/geoip.dat",
        "$exeDir/data/flutter_assets/assets/bin/geoip.dat",
        "flutter/assets/bin/geoip.dat",
        "assets/bin/geoip.dat",
      ];
      final geositeTargets = [
        "$exeDir/xray/geosite.dat",
        "xray/geosite.dat",
        "$exeDir/geosite.dat",
        "$exeDir/data/flutter_assets/assets/bin/geosite.dat",
        "flutter/assets/bin/geosite.dat",
        "assets/bin/geosite.dat",
      ];

      for (final t in geoipTargets) {
        if (File(t).existsSync()) {
          try { await tempGeoip.copy(t); } catch (_) {}
        }
      }
      for (final t in geositeTargets) {
        if (File(t).existsSync()) {
          try { await tempGeosite.copy(t); } catch (_) {}
        }
      }

      try {
        await tempGeoip.delete();
        await tempGeosite.delete();
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint("updateGeoFiles failed: $e");
      return false;
    } finally {
      client.close();
    }
  }

  /// Check for app updates via GitHub repository releases or custom URL
  Future<UpdateInfo> checkAppUpdate({String? customUrl}) async {
    final client = _createHttpClient();

    // 1. If custom URL provided, try that first
    if (customUrl != null && customUrl.trim().isNotEmpty) {
      try {
        final req = await client.getUrl(Uri.parse(customUrl.trim()));
        req.headers.set(HttpHeaders.userAgentHeader, "V2RayPro-Client/1.2.0");
        final res = await req.close().timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final body = await res.transform(utf8.decoder).join();
          final json = jsonDecode(body) as Map<String, dynamic>;
          final latest = (json["version"] as String? ?? "v1.2.0").trim();
          final dlUrl = json["download_url"] as String?;
          final notes = json["changelog"] as String?;
          final hasUp = latest.isNotEmpty && latest != currentAppVersion;
          return UpdateInfo(
            currentVersion: currentAppVersion,
            latestVersion: latest,
            hasUpdate: hasUp,
            downloadUrl: dlUrl,
            releaseNotes: notes,
          );
        }
      } catch (e) {
        debugPrint("checkAppUpdate customUrl check: $e");
      }
    }

    // 2. Query GitHub API for latest release on iamcloner/v2raypro
    final repos = [
      "iamcloner/v2raypro",
      "v2raypro/v2raypro",
    ];

    for (final repo in repos) {
      try {
        final req = await client.getUrl(Uri.parse("https://api.github.com/repos/$repo/releases?per_page=5"));
        req.headers.set(HttpHeaders.userAgentHeader, "V2RayPro-Client/1.2.0");
        req.headers.set(HttpHeaders.acceptHeader, "application/vnd.github.v3+json");

        final res = await req.close().timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final body = await res.transform(utf8.decoder).join();
          final list = jsonDecode(body) as List<dynamic>;
          if (list.isNotEmpty) {
            final json = list.first as Map<String, dynamic>;
            final tagName = (json["tag_name"] as String? ?? "").trim();
            final bodyNotes = json["body"] as String? ?? "";
            final assets = (json["assets"] as List<dynamic>? ?? []);

            String? zipDownloadUrl;
            // First look for windows zip or any zip
            for (final a in assets) {
              final name = (a["name"] as String? ?? "").toLowerCase();
              if (name.endsWith(".zip") && (name.contains("windows") || name.contains("v2raypro") || name.contains("win"))) {
                zipDownloadUrl = a["browser_download_url"] as String?;
                break;
              }
            }
            // Fallback to any zip asset
            if (zipDownloadUrl == null) {
              for (final a in assets) {
                final name = (a["name"] as String? ?? "").toLowerCase();
                if (name.endsWith(".zip")) {
                  zipDownloadUrl = a["browser_download_url"] as String?;
                  break;
                }
              }
            }
            // Fallback to GitHub zipball
            zipDownloadUrl ??= json["zipball_url"] as String?;

            final cleanCurrent = currentAppVersion.replaceAll('v', '').trim();
            final cleanLatest = tagName.replaceAll('v', '').trim();
            final hasUpdate = cleanLatest.isNotEmpty && cleanLatest != cleanCurrent;

            return UpdateInfo(
              currentVersion: currentAppVersion,
              latestVersion: tagName.isNotEmpty ? tagName : currentAppVersion,
              hasUpdate: hasUpdate,
              downloadUrl: zipDownloadUrl,
              releaseNotes: bodyNotes,
            );
          }
        }
      } catch (e) {
        debugPrint("checkAppUpdate github check ($repo): $e");
      }
    }

    return UpdateInfo(
      currentVersion: currentAppVersion,
      latestVersion: currentAppVersion,
      hasUpdate: false,
    );
  }

  /// Download latest release zip from GitHub, extract it, and apply updates to the application
  Future<bool> downloadAndApplyAppUpdate(
    String downloadUrl, {
    void Function(String status, double progress)? onProgress,
  }) async {
    final client = _createHttpClient();
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final zipFile = File("${tempDir.path}\\v2raypro_release_$timestamp.zip");
      final extractDir = Directory("${tempDir.path}\\v2raypro_extracted_$timestamp");

      onProgress?.call("downloading", 0.05);

      final req = await client.getUrl(Uri.parse(downloadUrl));
      req.headers.set(HttpHeaders.userAgentHeader, "V2RayPro-Client/1.2.0");
      final res = await req.close();
      if (res.statusCode != 200 && res.statusCode != 302) {
        return false;
      }

      final totalBytes = res.contentLength;
      int receivedBytes = 0;
      final sink = zipFile.openWrite();

      await for (final chunk in res) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final p = 0.05 + (receivedBytes / totalBytes) * 0.65; // 5% to 70%
          onProgress?.call("downloading", p.clamp(0.0, 0.70));
        }
      }
      await sink.flush();
      await sink.close();

      onProgress?.call("extracting", 0.75);

      // Extract zip using PowerShell
      await extractDir.create(recursive: true);
      final psCmd = 'Expand-Archive -Path "${zipFile.path}" -DestinationPath "${extractDir.path}" -Force';
      final extRes = await Process.run('powershell', ['-NoProfile', '-Command', psCmd]);
      if (extRes.exitCode != 0) {
        return false;
      }

      onProgress?.call("applying", 0.85);

      // Identify root of extracted release (might be root or nested folder)
      Directory payloadDir = extractDir;
      final entries = extractDir.listSync();
      if (entries.length == 1 && entries.first is Directory) {
        payloadDir = entries.first as Directory;
      }

      // Check for v2raypro.exe or Release build inside
      final currentExeDir = File(Platform.resolvedExecutable).parent.path;
      final updaterScript = File("${tempDir.path}\\apply_v2raypro_update_$timestamp.bat");

      final currentPid = pid;
      final scriptContent = '''
@echo off
timeout /t 2 /nobreak > nul
taskkill /F /PID $currentPid > nul 2>&1
timeout /t 1 /nobreak > nul

xcopy /E /Y /I "${payloadDir.path}\\*" "$currentExeDir" > nul 2>&1

start "" "${Platform.resolvedExecutable}"
del "%~f0" > nul 2>&1
exit
''';
      await updaterScript.writeAsString(scriptContent);

      onProgress?.call("complete", 1.0);

      // Launch updater batch script and close current process
      await Process.start("cmd", ["/c", updaterScript.path], mode: ProcessStartMode.detached);
      exit(0);
    } catch (e) {
      debugPrint("downloadAndApplyAppUpdate failed: $e");
      return false;
    } finally {
      client.close();
    }
  }
}
