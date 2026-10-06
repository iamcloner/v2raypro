import "dart:convert";
import "dart:io";
import "package:shared_preferences/shared_preferences.dart";
import "../models/proxy_node.dart";
import "../models/subscription_item.dart";

class StorageService {
  static final StorageService instance = StorageService._internal();
  StorageService._internal();

  static const _nodesKey = "v2raypro_saved_nodes";
  static const _subsKey = "v2raypro_saved_subs";
  static const _sysProxyKey = "v2raypro_sys_proxy";
  static const _tunKey = "v2raypro_tun_mode";
  static const _httpPortKey = "v2raypro_http_port";
  static const _socksPortKey = "v2raypro_socks_port";

  File _getBackupFile(String filename) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final primary = File("$exeDir/$filename");
    try {
      if (!primary.existsSync()) {
        primary.createSync(recursive: true);
      }
      return primary;
    } catch (_) {
      final tmp = Directory.systemTemp.path;
      return File("$tmp/$filename");
    }
  }

  Future<void> saveNodes(List<ProxyNode> nodes) async {
    try {
      final jsonList = nodes.map((n) => n.toJson()).toList();
      final str = jsonEncode(jsonList);
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_nodesKey, str);

      final file = _getBackupFile("v2raypro_nodes.json");
      await file.writeAsString(str);
    } catch (_) {}
  }

  Future<List<ProxyNode>> loadNodes() async {
    try {
      String? content;
      final sp = await SharedPreferences.getInstance();
      content = sp.getString(_nodesKey);

      if (content == null || content.isEmpty) {
        final file = _getBackupFile("v2raypro_nodes.json");
        if (await file.exists()) {
          content = await file.readAsString();
        }
      }

      if (content != null && content.isNotEmpty) {
        final decoded = jsonDecode(content) as List;
        return decoded.map((e) => ProxyNode.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveSubscriptions(List<SubscriptionItem> subs) async {
    try {
      final jsonList = subs.map((s) => s.toJson()).toList();
      final str = jsonEncode(jsonList);
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_subsKey, str);

      final file = _getBackupFile("v2raypro_subs.json");
      await file.writeAsString(str);
    } catch (_) {}
  }

  Future<List<SubscriptionItem>> loadSubscriptions() async {
    try {
      String? content;
      final sp = await SharedPreferences.getInstance();
      content = sp.getString(_subsKey);

      if (content == null || content.isEmpty) {
        final file = _getBackupFile("v2raypro_subs.json");
        if (await file.exists()) {
          content = await file.readAsString();
        }
      }

      if (content != null && content.isNotEmpty) {
        final decoded = jsonDecode(content) as List;
        return decoded.map((e) => SubscriptionItem.fromJson(e as Map<String, dynamic>)).toList();
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
}
