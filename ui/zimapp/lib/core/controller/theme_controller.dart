import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

/// Theme mode controller
class ThemeController extends GetxController with WidgetsBindingObserver {
  final _themeMode = Rx<ThemeMode>(ThemeMode.system);

  ThemeMode get themeMode => _themeMode.value;

  @override
  void onInit() {
    super.onInit();
    _loadThemeMode();
    // Add app lifecycle observer to detect system theme changes
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    // Refresh theme when system brightness changes
    if (_themeMode.value == ThemeMode.system) {
      _themeMode.refresh();
    }
  }

  /// Load theme mode from storage
  void _loadThemeMode() {
    final mode = DataSp.getThemeMode();

    switch (mode) {
      case 1:
        _themeMode.value = ThemeMode.light;
        break;
      case 2:
        _themeMode.value = ThemeMode.dark;
        break;
      default:
        _themeMode.value = ThemeMode.system;
    }
  }

  /// Switch to light mode
  void setLightMode() {
    _themeMode.value = ThemeMode.light;
    DataSp.putThemeMode(1);
    Get.changeThemeMode(ThemeMode.light);
  }

  /// Switch to dark mode
  void setDarkMode() {
    _themeMode.value = ThemeMode.dark;
    DataSp.putThemeMode(2);
    Get.changeThemeMode(ThemeMode.dark);
  }

  /// Switch to system mode
  void setSystemMode() {
    _themeMode.value = ThemeMode.system;
    DataSp.putThemeMode(0);
    Get.changeThemeMode(ThemeMode.system);
  }

  /// Toggle between light and dark
  void toggleTheme() {
    if (_themeMode.value == ThemeMode.dark) {
      setLightMode();
    } else {
      setDarkMode();
    }
  }

  /// Check if current theme is dark
  bool get isDarkMode {
    if (_themeMode.value == ThemeMode.system) {
      final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      return brightness == Brightness.dark;
    }

    return _themeMode.value == ThemeMode.dark;
  }

  /// Check if current theme is light
  bool get isLightMode {
    if (_themeMode.value == ThemeMode.system) {
      final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      return brightness == Brightness.light;
    }

    return _themeMode.value == ThemeMode.light;
  }
}
