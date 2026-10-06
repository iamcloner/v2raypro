import "dart:io";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:local_notifier/local_notifier.dart";
import "package:tray_manager/legacy.dart";
import "package:window_manager/window_manager.dart";
import "../core/l10n/translations.dart";
import "../providers/app_providers.dart";
import "xray_process_service.dart";

class AppTrayService with TrayListener, WindowListener {
  static final AppTrayService instance = AppTrayService._();
  AppTrayService._();

  ProviderContainer? _container;

  Future<void> init(ProviderContainer container) async {
    _container = container;
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    try {
      await localNotifier.setup(
        appName: 'V2RayPro',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
    } catch (_) {}

    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    await windowManager.setTitle("V2RayPro");

    trayManager.addListener(this);
    try {
      String iconPath = "assets/app_icon.png";
      if (Platform.isWindows) {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final candidates = [
          "$exeDir\\data\\flutter_assets\\assets\\app_icon.png",
          "$exeDir\\app_icon.png",
          "$exeDir\\data\\flutter_assets\\assets\\app_icon.ico",
          "$exeDir\\app_icon.ico",
          "assets/app_icon.png",
          "assets/app_icon.ico",
        ];
        for (final p in candidates) {
          if (File(p).existsSync()) {
            iconPath = p;
            break;
          }
        }
      }
      await trayManager.setIcon(iconPath);
    } catch (_) {}
    await updateTrayMenu();
  }

  Future<void> updateTrayMenu() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    final locale = _container?.read(currentLocaleProvider) ?? "en";
    final connState = _container?.read(connectionStatusProvider) ?? ConnectionStateEnum.disconnected;
    final isConnected = connState == ConnectionStateEnum.connected;

    try {
      await trayManager.setToolTip(
        "V2RayPro - ${AppStrings.get(isConnected ? "connected" : "disconnected", locale: locale)}",
      );

      final menu = Menu(
        items: [
          MenuItem(
            key: "show_window",
            label: AppStrings.get("show_window", locale: locale),
          ),
          MenuItem.separator(),
          MenuItem(
            key: "toggle_connect",
            label: isConnected
                ? AppStrings.get("disconnect", locale: locale)
                : AppStrings.get("connect", locale: locale),
          ),
          MenuItem.separator(),
          MenuItem(
            key: "exit_app",
            label: AppStrings.get("exit", locale: locale),
          ),
        ],
      );
      await trayManager.setContextMenu(menu);
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case "show_window":
        await windowManager.show();
        await windowManager.focus();
        break;
      case "toggle_connect":
        _container?.read(connectionStatusProvider.notifier).toggleConnect();
        break;
      case "exit_app":
        await exitApp();
        break;
    }
  }

  @override
  void onWindowClose() async {
    // Hide to tray instead of quitting
    await windowManager.hide();

    // Show native Windows notification regarding background status
    try {
      final locale = _container?.read(currentLocaleProvider) ?? "en";
      final connState = _container?.read(connectionStatusProvider) ?? ConnectionStateEnum.disconnected;
      final isConnected = connState == ConnectionStateEnum.connected;

      final body = isConnected
          ? AppStrings.get("background_active_connected", locale: locale)
          : AppStrings.get("background_active_disconnected", locale: locale);

      final notification = LocalNotification(
        title: "V2RayPro",
        body: body,
        silent: true,
      );
      await notification.show();
    } catch (_) {}
  }

  Future<void> exitApp() async {
    try {
      // Disconnect if connected and completely clean system settings
      await XrayProcessService.instance.stop();
      XrayProcessService.instance.cleanupSystemAndXray();
    } catch (_) {}
    try {
      await trayManager.destroy();
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }
}
