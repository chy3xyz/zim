import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zim_sdk/zim_sdk.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/api_service.dart';
import 'package:path_provider/path_provider.dart';

/// Config for Volo-OpenIM Backend
/// This configuration points to the local volo-openim Rust backend
class Config {
  Config._();

  static const double uiWidth = 375.0;
  static const double uiHeight = 812.0;
  static const double textScaleFactor = 1.0;

  static const String discoverPageUrl = 'https://docs.openim.io/';
  static const String allowSendMsgNotFriend = '1';
  static const String webKey = '75a0da9ec836d573102999e99abf4650';
  static const String webServerKey = '835638634b8f9b4bba386eeec94aa7df';
  static const String locationHost = 'http://location.xxx.xx';

  static String get githubClientId => 'Ov23liElEK8rfHLPScaY';
  static String get githubRedirectUri => '$githubCustomScheme://oauth/callback';
  static String get githubCustomScheme => 'io.github.login';
  static String get githubServerTokenEndpoint => appAuthUrl;

  static String get googleAndroidClientId => '276390714151-s3oi687vd73ctgnagkakgu21io03g028.apps.googleusercontent.com';
  static String get googleIosClientId => '276390714151-ngdgghc57iih8j88p7a0eb5vbe5s1ipp.apps.googleusercontent.com';
  static String get googleAndroidRedirectUri =>
      'com.googleusercontent.apps.276390714151-s3oi687vd73ctgnagkakgu21io03g028:/oauth2redirect';
  static String get googleIosRedirectUri =>
      'com.googleusercontent.apps.276390714151-ngdgghc57iih8j88p7a0eb5vbe5s1ipp:/oauth2redirect';

  static const String friendScheme = 'io.openim.app/addFriend/';
  static const String groupScheme = 'io.openim.app/joinGroup/';

  static final OfflinePushInfo offlinePushInfo = OfflinePushInfo(
    title: 'OpenIM',
    desc: StrRes.offlineMessage,
    iOSBadgeCount: true,
    iOSPushSound: 'default',
  );

  static const PushType pushType = PushType.fcm;
  static const PushConfig pushConfig = PushConfig(
    appID: '',
    appKey: '',
    appSecret: '',
  );

  // ============================================
  // Volo-OpenIM Backend Configuration
  // ============================================
  
  // Default to localhost for development
  // For Android Emulator: use 10.0.2.2
  // For iOS Simulator: use localhost
  // For Real Device: use your computer's IP
  
  static String get _defaultHost {
    if (Platform.isAndroid) {
      // Android Emulator
      return '10.0.2.2';
    } else if (Platform.isIOS) {
      // iOS Simulator or Device
      // For real device, change this to your computer's IP
      return 'localhost';
    }
    return 'localhost';
  }

  static const String _ipRegex = r'((2[0-4]\d|25[0-5]|[01]?\d\d?)\.){3}(2[0-4]\d|25[0-5]|[01]?\d\d?)';
  static late String cachePath;

  static Future<void> init(VoidCallback runApp) async {
    WidgetsFlutterBinding.ensureInitialized();
    await _initializeServices();
    runApp();
    await _configureSystemUI();
  }

  static Future<void> _initializeServices() async {
    try {
      cachePath = '${(await getApplicationDocumentsDirectory()).path}/';

      await Future.wait<void>([
        DataSp.init(),
        Hive.initFlutter(cachePath),
      ]);

      MediaKit.ensureInitialized();
      HttpUtil.init();
      ApiService().setBaseUrl(imApiUrl);
    } catch (e, stackTrace) {
      Logger.print('Initialization error: $e\n$stackTrace');
    }
  }

  static Future<void> _configureSystemUI() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    final brightness = Platform.isAndroid ? Brightness.dark : Brightness.light;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: brightness,
      statusBarIconBrightness: brightness,
    ));
  }

  static bool get _isIp => RegExp(_ipRegex).hasMatch(_defaultHost);

  static Map<String, dynamic>? _getServerConfig() {
    final server = DataSp.getServerConfig() as Map<String, dynamic>?;
    if (server != null) {
      Logger.print('Server config loaded: $server');
    }
    return server;
  }

  static String get serverIp => _getServerConfig()?['serverIP'] ?? _defaultHost;

  // ============================================
  // Volo-OpenIM uses unified API on port 10002
  // ============================================
  
  /// Auth URL - Volo-OpenIM uses the same port for auth
  static String get chatTokenUrl {
    final url = _getServerConfig()?['chatTokenUrl'];
    // Volo-OpenIM: auth is on port 10002 (same as API)
    return url ?? 'http://$serverIp:10000';
  }

  /// App Auth URL - Volo-OpenIM uses the same port
  static String get appAuthUrl {
    final url = _getServerConfig()?['authUrl'];
    return url ?? 'http://$serverIp:10000';
  }

  /// IM API URL - Main API endpoint
  static String get imApiUrl {
    final url = _getServerConfig()?['apiUrl'];
    return url ?? 'http://$serverIp:10000';
  }

  /// IM WebSocket URL
  static String get imWsUrl {
    final url = _getServerConfig()?['wsUrl'];
    return url ?? 'ws://$serverIp:10001';
  }

  static int get logLevel {
    final level = _getServerConfig()?['logLevel'];
    return level != null ? int.parse(level) : 5;
  }

  /// Robot API URL - Volo-OpenIM uses the same port
  static String get robotApiUrl {
    final url = _getServerConfig()?['robotApiUrl'];
    return url ?? 'http://$serverIp:10000';
  }
}
