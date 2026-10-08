import "dart:async";
import "dart:convert";
import "dart:io";
import "package:shared_preferences/shared_preferences.dart";
import "../models/dns_settings.dart";
import "../models/proxy_node.dart";
import "../models/routing_rule.dart";
import "../models/subscription_item.dart";
import "cdn_scanner_service.dart";

class StorageService {
  static final StorageService instance = StorageService._internal();
  StorageService._internal();

  Timer? _nodesDebounceTimer;
  Timer? _subsDebounceTimer;

  static const _nodesKey = "v2raypro_saved_nodes";
  static const _subsKey = "v2raypro_saved_subs";
  static const _sysProxyKey = "v2raypro_sys_proxy";
  static const _tunKey = "v2raypro_tun_mode";
  static const _httpPortKey = "v2raypro_http_port";
  static const _socksPortKey = "v2raypro_socks_port";
  static const _freeConfigsKey = "v2raypro_saved_free_configs";
  static const _allowInsecureKey = "v2raypro_global_allow_insecure";
  static const _enableMuxKey = "v2raypro_global_enable_mux";
  static const _routingRulesKey = "v2raypro_routing_rules";

  File _getBackupFile(String filename) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final configDir = Directory("$exeDir/config");
    final configTarget = File("${configDir.path}/$filename");
    final legacyRoot = File("$exeDir/$filename");

    try {
      if (!configDir.existsSync()) {
        configDir.createSync(recursive: true);
      }
      // Migrate legacy file if it exists at root but not yet in config/
      if (legacyRoot.existsSync() && !configTarget.existsSync()) {
        try {
          legacyRoot.copySync(configTarget.path);
        } catch (_) {}
      }
      return configTarget;
    } catch (_) {
      // Fallback to legacy root or temp
      if (legacyRoot.existsSync()) {
        return legacyRoot;
      }
      final tmp = Directory.systemTemp.path;
      return File("$tmp/$filename");
    }
  }

  Future<void> saveNodes(List<ProxyNode> nodes, {bool immediate = false}) async {
    _nodesDebounceTimer?.cancel();
    if (immediate) {
      await _writeNodesToDisk(nodes);
    } else {
      _nodesDebounceTimer = Timer(const Duration(milliseconds: 400), () {
        _writeNodesToDisk(nodes);
      });
    }
  }

  Future<void> _writeNodesToDisk(List<ProxyNode> nodes) async {
    try {
      final jsonList = nodes.map((n) => n.toJson()).toList();
      final str = jsonEncode(jsonList);

      final file = _getBackupFile("v2raypro_nodes.json");
      await file.writeAsString(str);

      // Only sync to SharedPreferences if payload is small (<64KB) to avoid Windows Registry size limits/crashes
      if (str.length < 65536) {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_nodesKey, str);
      }
    } catch (_) {}
  }

  Future<List<ProxyNode>> loadNodes() async {
    try {
      String? content;
      final file = _getBackupFile("v2raypro_nodes.json");
      if (await file.exists()) {
        content = await file.readAsString();
      }

      if (content == null || content.isEmpty) {
        final sp = await SharedPreferences.getInstance();
        content = sp.getString(_nodesKey);
      }

      if (content != null && content.isNotEmpty) {
        final decoded = jsonDecode(content) as List;
        return decoded.map((e) => ProxyNode.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveSubscriptions(List<SubscriptionItem> subs, {bool immediate = false}) async {
    _subsDebounceTimer?.cancel();
    if (immediate) {
      await _writeSubscriptionsToDisk(subs);
    } else {
      _subsDebounceTimer = Timer(const Duration(milliseconds: 400), () {
        _writeSubscriptionsToDisk(subs);
      });
    }
  }

  Future<void> _writeSubscriptionsToDisk(List<SubscriptionItem> subs) async {
    try {
      final jsonList = subs.map((s) => s.toJson()).toList();
      final str = jsonEncode(jsonList);

      final file = _getBackupFile("v2raypro_subs.json");
      await file.writeAsString(str);

      if (str.length < 65536) {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_subsKey, str);
      }
    } catch (_) {}
  }

  Future<List<SubscriptionItem>> loadSubscriptions() async {
    try {
      String? content;
      final file = _getBackupFile("v2raypro_subs.json");
      if (await file.exists()) {
        content = await file.readAsString();
      }

      if (content == null || content.isEmpty) {
        final sp = await SharedPreferences.getInstance();
        content = sp.getString(_subsKey);
      }

      if (content != null && content.isNotEmpty) {
        final decoded = jsonDecode(content) as List;
        return decoded.map((e) => SubscriptionItem.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveFreeConfigs(List<ProxyNode> nodes) async {
    try {
      final jsonList = nodes.map((n) => n.toJson()).toList();
      final str = jsonEncode(jsonList);

      final file = _getBackupFile("v2raypro_free_configs.json");
      await file.writeAsString(str);

      if (str.length < 65536) {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_freeConfigsKey, str);
      }
    } catch (_) {}
  }

  Future<List<ProxyNode>> loadFreeConfigs() async {
    try {
      String? content;
      final file = _getBackupFile("v2raypro_free_configs.json");
      if (await file.exists()) {
        content = await file.readAsString();
      }

      if (content == null || content.isEmpty) {
        final sp = await SharedPreferences.getInstance();
        content = sp.getString(_freeConfigsKey);
      }

      if (content != null && content.isNotEmpty) {
        final decoded = jsonDecode(content) as List;
        return decoded.map((e) => ProxyNode.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveBool(String key, bool val) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(key, val);
    } catch (_) {}
  }

  Future<bool> loadBool(String key, {bool defaultValue = false}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getBool(key) ?? defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  Future<void> saveSystemProxyEnabled(bool val) => saveBool(_sysProxyKey, val);
  Future<bool> loadSystemProxyEnabled() => loadBool(_sysProxyKey, defaultValue: false);

  Future<void> saveTunEnabled(bool val) => saveBool(_tunKey, val);
  Future<bool> loadTunEnabled() => loadBool(_tunKey, defaultValue: false);

  Future<void> saveGlobalAllowInsecure(bool val) => saveBool(_allowInsecureKey, val);
  Future<bool> loadGlobalAllowInsecure() => loadBool(_allowInsecureKey, defaultValue: false);

  Future<void> saveGlobalEnableMux(bool val) => saveBool(_enableMuxKey, val);
  Future<bool> loadGlobalEnableMux() => loadBool(_enableMuxKey, defaultValue: false);

  Future<void> saveRoutingRules(List<RoutingRule> rules) async {
    try {
      final jsonList = rules.map((r) => r.toJson()).toList();
      final str = jsonEncode(jsonList);
      final file = _getBackupFile("v2raypro_routing_rules.json");
      await file.writeAsString(str);

      if (str.length < 65536) {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_routingRulesKey, str);
      }
    } catch (_) {}
  }

  Future<List<RoutingRule>> loadRoutingRules() async {
    try {
      String? content;
      final file = _getBackupFile("v2raypro_routing_rules.json");
      if (await file.exists()) {
        content = await file.readAsString();
      }

      if (content == null || content.isEmpty) {
        final sp = await SharedPreferences.getInstance();
        content = sp.getString(_routingRulesKey);
      }

      if (content != null && content.isNotEmpty) {
        final decoded = jsonDecode(content) as List;
        return decoded.map((e) => RoutingRule.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveCdnRanges(CdnProvider provider, List<String> ranges) async {
    try {
      final key = "v2raypro_${provider.id}_ranges";
      final str = jsonEncode(ranges);
      final sp = await SharedPreferences.getInstance();
      await sp.setString(key, str);

      final file = _getBackupFile("$key.json");
      await file.writeAsString(str);
    } catch (_) {}
  }

  Future<List<String>> loadCdnRanges(CdnProvider provider) async {
    try {
      final key = "v2raypro_${provider.id}_ranges";
      String? content;
      final sp = await SharedPreferences.getInstance();
      content = sp.getString(key);

      if (content == null || content.isEmpty) {
        final file = _getBackupFile("$key.json");
        if (await file.exists()) {
          content = await file.readAsString();
        }
      }

      if (content != null && content.isNotEmpty) {
        final decoded = jsonDecode(content) as List;
        return decoded.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
    } catch (_) {}
    return provider.defaultCidrs;
  }

  Future<void> saveCloudflareRanges(List<String> ranges) =>
      saveCdnRanges(CdnProvider.cloudflare, ranges);

  Future<List<String>> loadCloudflareRanges() =>
      loadCdnRanges(CdnProvider.cloudflare);

  Future<void> saveDnsSettings(DnsSettings settings) async {
    try {
      final str = jsonEncode(settings.toJson());
      final sp = await SharedPreferences.getInstance();
      await sp.setString("v2raypro_dns_settings", str);

      final file = _getBackupFile("v2raypro_dns_settings.json");
      await file.writeAsString(str);
    } catch (_) {}
  }

  Future<DnsSettings> loadDnsSettings() async {
    try {
      String? content;
      final sp = await SharedPreferences.getInstance();
      content = sp.getString("v2raypro_dns_settings");

      if (content == null || content.isEmpty) {
        final file = _getBackupFile("v2raypro_dns_settings.json");
        if (await file.exists()) {
          content = await file.readAsString();
        }
      }

      if (content != null && content.isNotEmpty) {
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        return DnsSettings.fromJson(decoded);
      }
    } catch (_) {}
    return const DnsSettings();
  }

  Future<void> saveInt(String key, int val) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(key, val);
    } catch (_) {}
  }

  Future<int> loadInt(String key, {int defaultValue = 0}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getInt(key) ?? defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }


  Future<void> saveString(String key, String val) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(key, val);
    } catch (_) {}
  }

  Future<String> loadString(String key, {String defaultValue = ""}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getString(key) ?? defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  Future<void> saveHttpPort(int val) => saveInt(_httpPortKey, val);
  Future<int> loadHttpPort() => loadInt(_httpPortKey, defaultValue: 10888);

  Future<void> saveSocksPort(int val) => saveInt(_socksPortKey, val);
  Future<int> loadSocksPort() => loadInt(_socksPortKey, defaultValue: 10999);

  // Settings: Startup, Auto-connect, Themes
  static const _startOnBootKey = "v2raypro_start_on_boot";
  static const _autoConnectKey = "v2raypro_auto_connect";
  static const _autoSysProxyKey = "v2raypro_auto_sys_proxy";
  static const _autoTunKey = "v2raypro_auto_tun";
  static const _themeModeKey = "v2raypro_theme_mode";

  Future<void> setWindowsStartup(bool enable) async {
    if (!Platform.isWindows) return;
    try {
      if (enable) {
        final exe = Platform.resolvedExecutable;
        Process.runSync("reg", [
          "add",
          r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run",
          "/v",
          "V2RayPro",
          "/t",
          "REG_SZ",
          "/d",
          "\"$exe\"",
          "/f",
        ]);
      } else {
        Process.runSync("reg", [
          "delete",
          r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run",
          "/v",
          "V2RayPro",
          "/f",
        ]);
      }
    } catch (_) {}
  }

  Future<void> saveStartOnBoot(bool val) async {
    await saveBool(_startOnBootKey, val);
    await setWindowsStartup(val);
  }

  Future<bool> loadStartOnBoot() => loadBool(_startOnBootKey, defaultValue: false);

  Future<void> saveAutoConnect(bool val) => saveBool(_autoConnectKey, val);
  Future<bool> loadAutoConnect() => loadBool(_autoConnectKey, defaultValue: false);

  Future<void> saveAutoSysProxy(bool val) => saveBool(_autoSysProxyKey, val);
  Future<bool> loadAutoSysProxy() => loadBool(_autoSysProxyKey, defaultValue: false);

  Future<void> saveAutoTun(bool val) => saveBool(_autoTunKey, val);
  Future<bool> loadAutoTun() => loadBool(_autoTunKey, defaultValue: false);

  static const _enableUdpKey = "v2raypro_enable_udp";
  Future<void> saveEnableUdp(bool val) => saveBool(_enableUdpKey, val);
  Future<bool> loadEnableUdp() => loadBool(_enableUdpKey, defaultValue: true);

  Future<void> saveThemeMode(String mode) => saveString(_themeModeKey, mode);
  Future<String> loadThemeMode() => loadString(_themeModeKey, defaultValue: "system");
}
