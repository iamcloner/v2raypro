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

  static const String _defaultFallbackVersion = "v1.6.1";
  static String? _cachedCurrentVersion;

  /// Read current app version dynamically from version.ini
  static String getCurrentAppVersion() {
    if (_cachedCurrentVersion != null) return _cachedCurrentVersion!;

    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        "$exeDir/version.ini",
        "version.ini",
        "$exeDir/build/windows/version.ini",
        "build/windows/version.ini",
        "../version.ini",
      ];
      for (final p in candidates) {
        final f = File(p);
        if (f.existsSync()) {
          final lines = f.readAsLinesSync();
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.startsWith('version=')) {
              final v = trimmed.substring('version='.length).trim().replaceAll('"', '').replaceAll("'", "");
              if (v.isNotEmpty) {
                _cachedCurrentVersion = v.startsWith('v') ? v : 'v$v';
                return _cachedCurrentVersion!;
              }
            }
          }
        }
      }
    } catch (_) {}

    _cachedCurrentVersion = _defaultFallbackVersion;
    return _cachedCurrentVersion!;
  }

  static String get currentAppVersion => getCurrentAppVersion();

  static void invalidateVersionCache() {
    _cachedCurrentVersion = null;
  }

  static const String defaultAppRepoUrl = "https://github.com/iamcloner/v2raypro/releases";
  static const String defaultAppTestUrl = defaultAppRepoUrl;

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

  /// Check if version [latest] is strictly newer than [current] (semver-aware)
  static bool isVersionNewer(String latest, String current) {
    final cleanLatest = latest.replaceAll(RegExp(r'[^0-9\.]'), '').trim();
    final cleanCurrent = current.replaceAll(RegExp(r'[^0-9\.]'), '').trim();
    if (cleanLatest.isEmpty) return false;
    if (cleanCurrent.isEmpty) return true;

    final latestParts = cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final currentParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLen = latestParts.length > currentParts.length ? latestParts.length : currentParts.length;
    for (int i = 0; i < maxLen; i++) {
      final l = i < latestParts.length ? latestParts[i] : 0;
      final c = i < currentParts.length ? currentParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  /// Locate the release zip asset corresponding to the current host operating system
  static String? findOsSpecificZipAsset(List<dynamic> assets) {
    final isWindows = Platform.isWindows;
    final isMacOS = Platform.isMacOS;
    final isLinux = Platform.isLinux;

    // 1. Primary: OS-specific match
    for (final a in assets) {
      final name = (a["name"] as String? ?? "").toLowerCase();
      if (!name.endsWith(".zip")) continue;

      if (isWindows) {
        if (name.contains("windows") || name.contains("win64") || name.contains("win32") || name.contains("win")) {
          return a["browser_download_url"] as String?;
        }
      } else if (isMacOS) {
        if (name.contains("macos") || name.contains("darwin") || name.contains("mac") || name.contains("osx")) {
          return a["browser_download_url"] as String?;
        }
      } else if (isLinux) {
        if (name.contains("linux")) {
          return a["browser_download_url"] as String?;
        }
      }
    }

    // 2. Secondary: Zip matching app name
    for (final a in assets) {
      final name = (a["name"] as String? ?? "").toLowerCase();
      if (name.endsWith(".zip") && name.contains("v2raypro")) {
        return a["browser_download_url"] as String?;
      }
    }

    // 3. Fallback: Any zip file in release assets
    for (final a in assets) {
      final name = (a["name"] as String? ?? "").toLowerCase();
      if (name.endsWith(".zip")) {
        return a["browser_download_url"] as String?;
      }
    }

    return null;
  }

  UpdateInfo _parseReleaseJson(Map<String, dynamic> json, {String? targetTag}) {
    final tagName = (json["tag_name"] as String? ?? targetTag ?? currentAppVersion).trim();
    final bodyNotes = json["body"] as String? ?? "";
    final assets = (json["assets"] as List<dynamic>? ?? []);

    String? zipDownloadUrl = findOsSpecificZipAsset(assets);
    zipDownloadUrl ??= json["zipball_url"] as String?;
    zipDownloadUrl ??= "https://github.com/iamcloner/v2raypro/releases/download/$tagName/v2raypro-$tagName-windows.zip";

    final hasUpdate = isVersionNewer(tagName, currentAppVersion);

    return UpdateInfo(
      currentVersion: currentAppVersion,
      latestVersion: tagName.isNotEmpty ? tagName : currentAppVersion,
      hasUpdate: hasUpdate,
      downloadUrl: zipDownloadUrl,
      releaseNotes: bodyNotes,
    );
  }

  /// Check for app updates via GitHub repository releases or custom URL
  Future<UpdateInfo> checkAppUpdate({String? customUrl}) async {
    final client = _createHttpClient();

    // 1. If custom URL provided, inspect it
    if (customUrl != null && customUrl.trim().isNotEmpty) {
      final trimmed = customUrl.trim();

      // Direct zip download link
      if (trimmed.toLowerCase().endsWith('.zip')) {
        return UpdateInfo(
          currentVersion: currentAppVersion,
          latestVersion: currentAppVersion,
          hasUpdate: true,
          downloadUrl: trimmed,
        );
      }

      // Check if it's a GitHub release tag URL (e.g. https://github.com/iamcloner/v2raypro/releases/tag/v1.2.0)
      final tagMatch = RegExp(r'github\.com/([^/]+)/([^/]+)/releases/tag/([^/?#]+)').firstMatch(trimmed);
      if (tagMatch != null) {
        final owner = tagMatch.group(1);
        final repo = tagMatch.group(2);
        final tag = tagMatch.group(3);
        try {
          final req = await client.getUrl(Uri.parse("https://api.github.com/repos/$owner/$repo/releases/tags/$tag"));
          req.headers.set(HttpHeaders.userAgentHeader, "V2RayPro-Client/1.2.0");
          req.headers.set(HttpHeaders.acceptHeader, "application/vnd.github.v3+json");
          final res = await req.close().timeout(const Duration(seconds: 10));
          if (res.statusCode == 200) {
            final body = await res.transform(utf8.decoder).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            return _parseReleaseJson(json, targetTag: tag);
          }
        } catch (e) {
          debugPrint("checkAppUpdate tag URL check error: $e");
        }
      }

      // Check if it's a GitHub repo/releases URL (e.g. https://github.com/iamcloner/v2raypro/releases or https://github.com/iamcloner/v2raypro)
      final repoMatch = RegExp(r'github\.com/([^/]+)/([^/?#]+)').firstMatch(trimmed);
      if (repoMatch != null) {
        final owner = repoMatch.group(1);
        final repo = repoMatch.group(2);
        try {
          // Try /releases/latest first
          final reqLatest = await client.getUrl(Uri.parse("https://api.github.com/repos/$owner/$repo/releases/latest"));
          reqLatest.headers.set(HttpHeaders.userAgentHeader, "V2RayPro-Client/1.2.0");
          reqLatest.headers.set(HttpHeaders.acceptHeader, "application/vnd.github.v3+json");
          final resLatest = await reqLatest.close().timeout(const Duration(seconds: 10));
          if (resLatest.statusCode == 200) {
            final body = await resLatest.transform(utf8.decoder).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            return _parseReleaseJson(json);
          }

          // Fallback to releases list
          final req = await client.getUrl(Uri.parse("https://api.github.com/repos/$owner/$repo/releases?per_page=5"));
          req.headers.set(HttpHeaders.userAgentHeader, "V2RayPro-Client/1.2.0");
          req.headers.set(HttpHeaders.acceptHeader, "application/vnd.github.v3+json");
          final res = await req.close().timeout(const Duration(seconds: 10));
          if (res.statusCode == 200) {
            final body = await res.transform(utf8.decoder).join();
            final list = jsonDecode(body) as List<dynamic>;
            if (list.isNotEmpty) {
              return _parseReleaseJson(list.first as Map<String, dynamic>);
            }
          }
        } catch (e) {
          debugPrint("checkAppUpdate repo URL check error: $e");
        }
      }

      // Custom JSON endpoint (e.g., version.json)
      try {
        final req = await client.getUrl(Uri.parse(trimmed));
        req.headers.set(HttpHeaders.userAgentHeader, "V2RayPro-Client/1.2.0");
        final res = await req.close().timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final body = await res.transform(utf8.decoder).join();
          final json = jsonDecode(body) as Map<String, dynamic>;
          final latest = (json["version"] as String? ?? currentAppVersion).trim();
          final dlUrl = json["download_url"] as String?;
          final notes = json["changelog"] as String?;
          final hasUp = isVersionNewer(latest, currentAppVersion);
          return UpdateInfo(
            currentVersion: currentAppVersion,
            latestVersion: latest,
            hasUpdate: hasUp,
            downloadUrl: dlUrl,
            releaseNotes: notes,
          );
        }
      } catch (e) {
        debugPrint("checkAppUpdate custom JSON check: $e");
      }
    }

    // 2. Default: Query GitHub API for latest release on iamcloner/v2raypro
    final repos = [
      "iamcloner/v2raypro",
    ];

    for (final repo in repos) {
      try {
        // First try /releases/latest
        final reqLatest = await client.getUrl(Uri.parse("https://api.github.com/repos/$repo/releases/latest"));
        reqLatest.headers.set(HttpHeaders.userAgentHeader, "V2RayPro-Client/1.2.0");
        reqLatest.headers.set(HttpHeaders.acceptHeader, "application/vnd.github.v3+json");
        final resLatest = await reqLatest.close().timeout(const Duration(seconds: 10));
        if (resLatest.statusCode == 200) {
          final body = await resLatest.transform(utf8.decoder).join();
          final json = jsonDecode(body) as Map<String, dynamic>;
          return _parseReleaseJson(json);
        }

        // Fallback to releases list
        final req = await client.getUrl(Uri.parse("https://api.github.com/repos/$repo/releases?per_page=5"));
        req.headers.set(HttpHeaders.userAgentHeader, "V2RayPro-Client/1.2.0");
        req.headers.set(HttpHeaders.acceptHeader, "application/vnd.github.v3+json");
        final res = await req.close().timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final body = await res.transform(utf8.decoder).join();
          final list = jsonDecode(body) as List<dynamic>;
          if (list.isNotEmpty) {
            return _parseReleaseJson(list.first as Map<String, dynamic>);
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
      downloadUrl: "https://github.com/iamcloner/v2raypro/releases/download/v1.6.1/v2raypro-windows-v1.6.1.zip",
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

      // If URL is not direct zip, resolve it
      String targetUrl = downloadUrl.trim();
      if (!targetUrl.toLowerCase().endsWith('.zip') && !targetUrl.contains('/download/')) {
        final resolved = await checkAppUpdate(customUrl: targetUrl);
        if (resolved.downloadUrl != null) {
          targetUrl = resolved.downloadUrl!;
        }
      }

      onProgress?.call("downloading", 0.05);

      // Handle HTTP redirects (GitHub Releases redirect to Azure/AWS storage)
      HttpClientResponse? res;
      for (int i = 0; i < 6; i++) {
        final req = await client.getUrl(Uri.parse(targetUrl));
        req.headers.set(HttpHeaders.userAgentHeader, "V2RayPro-Client/1.2.0");
        req.followRedirects = false;
        final candidate = await req.close();
        if (candidate.statusCode == 301 || candidate.statusCode == 302 || candidate.statusCode == 303 || candidate.statusCode == 307) {
          final loc = candidate.headers.value(HttpHeaders.locationHeader);
          await candidate.drain(); // drain socket
          if (loc != null) {
            targetUrl = loc;
            continue;
          }
        }
        res = candidate;
        break;
      }

      if (res == null || res.statusCode != 200) {
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

      // Identify root folder containing v2raypro release files
      Directory payloadDir = extractDir;
      final nestedV2raypro = Directory("${extractDir.path}\\v2raypro");
      if (nestedV2raypro.existsSync() && File("${nestedV2raypro.path}\\v2raypro.exe").existsSync()) {
        payloadDir = nestedV2raypro;
      } else {
        for (final entity in extractDir.listSync(recursive: true)) {
          if (entity is File && entity.path.toLowerCase().endsWith('v2raypro.exe')) {
            payloadDir = entity.parent;
            break;
          }
        }
      }

      final currentExeDir = File(Platform.resolvedExecutable).parent.path;
      final updaterScript = File("${tempDir.path}\\apply_v2raypro_update_$timestamp.bat");

      final currentPid = pid;
      final scriptContent = '''
@echo off
timeout /t 2 /nobreak > nul
taskkill /F /PID $currentPid > nul 2>&1
taskkill /F /IM v2raypro.exe > nul 2>&1
timeout /t 1 /nobreak > nul

:: Safety backup for user nodes and subscriptions
if exist "$currentExeDir\\config\\v2raypro_nodes.json" (
    copy /Y "$currentExeDir\\config\\v2raypro_nodes.json" "%temp%\\v2raypro_nodes_backup.json" > nul 2>&1
)
if exist "$currentExeDir\\config\\v2raypro_subs.json" (
    copy /Y "$currentExeDir\\config\\v2raypro_subs.json" "%temp%\\v2raypro_subs_backup.json" > nul 2>&1
)

:: Replace updated release files
xcopy /E /Y /I /H /R "${payloadDir.path}\\*" "$currentExeDir\\" > nul 2>&1

:: Restore backup if somehow overwritten
if exist "%temp%\\v2raypro_nodes_backup.json" (
    copy /Y "%temp%\\v2raypro_nodes_backup.json" "$currentExeDir\\config\\v2raypro_nodes.json" > nul 2>&1
    del /F "%temp%\\v2raypro_nodes_backup.json" > nul 2>&1
)
if exist "%temp%\\v2raypro_subs_backup.json" (
    copy /Y "%temp%\\v2raypro_subs_backup.json" "$currentExeDir\\config\\v2raypro_subs.json" > nul 2>&1
    del /F "%temp%\\v2raypro_subs_backup.json" > nul 2>&1
)

start "" "${Platform.resolvedExecutable}"
del "%~f0" > nul 2>&1
exit
''';
      await updaterScript.writeAsString(scriptContent);

      onProgress?.call("complete", 1.0);

      // In testing environments, don't kill test runner
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        await Process.start("cmd", ["/c", updaterScript.path], mode: ProcessStartMode.detached);
        exit(0);
      }
      return true;
    } catch (e) {
      debugPrint("downloadAndApplyAppUpdate failed: $e");
      return false;
    } finally {
      client.close();
    }
  }
}
