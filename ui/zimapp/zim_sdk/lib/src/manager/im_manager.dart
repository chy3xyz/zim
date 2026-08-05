import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:zim_sdk/src/client/method_channel.dart';
import 'package:zim_sdk/src/enum/login_status.dart';
import 'package:zim_sdk/src/listener/connect_listener.dart';
import 'package:zim_sdk/src/listener/listener_for_service.dart';
import 'package:zim_sdk/src/listener/upload_file_listener.dart';
import 'package:zim_sdk/src/logger.dart';
import 'package:zim_sdk/src/models/init_config.dart';
import 'package:zim_sdk/src/models/user_info.dart';
import 'package:zim_sdk/src/utils.dart';

import 'im_conversation_manager.dart';
import 'im_friendship_manager.dart';
import 'im_group_manager.dart';
import 'im_message_manager.dart';
import 'im_user_manager.dart';

class IMManager {
  final ZimSdkMethodChannel _channel;
  late ConversationManager conversationManager;
  late FriendshipManager friendshipManager;
  late MessageManager messageManager;
  late GroupManager groupManager;
  late UserManager userManager;

  late OnConnectListener _connectListener;
  OnListenerForService? _listenerForService;
  OnUploadFileListener? _uploadFileListener;
  OnUploadLogsListener? _uploadLogsListener;

  late String userID;
  late UserInfo userInfo;
  bool isLogined = false;
  String? token;

  IMManager(this._channel) {
    conversationManager = ConversationManager(_channel);
    friendshipManager = FriendshipManager(_channel);
    messageManager = MessageManager(_channel);
    groupManager = GroupManager(_channel);
    userManager = UserManager(_channel);
  }

  Future<bool?> init(
    InitConfig config,
    OnConnectListener listener, {
    String? operationID,
  }) {
    _connectListener = listener;
    config.logFilePath ??= config.dataDir;
    return _channel.invokeMethod(
      'initSDK',
      _buildParam(
        {
          ...config.toMap(),
          "operationID": Utils.checkOperationID(operationID),
        },
      ),
    );
  }

  /// Initialize the SDK
  /// [platform] Platform ID [IMPlatform]
  /// [apiAddr] SDK API address
  /// [wsAddr] SDK WebSocket address
  /// [dataDir] SDK database storage directory
  /// [logLevel] Log level, 1: no printing
  /// [enabledEncryption] true: encryption
  /// [enabledCompression] true: compression
  Future<dynamic> initSDK({
    required int platformID,
    required String apiAddr,
    required String wsAddr,
    required String dataDir,
    required OnConnectListener listener,
    int logLevel = 6,
    bool isNeedEncryption = false,
    bool isCompression = true,
    bool isLogStandardOutput = true,
    String? logFilePath,
    String? operationID,
  }) {
    _connectListener = listener;
    return _channel.invokeMethod(
      'initSDK',
      _buildParam(
        {
          "platformID": platformID,
          "apiAddr": apiAddr,
          "wsAddr": wsAddr,
          "dataDir": dataDir,
          "logLevel": logLevel,
          "isCompression": isCompression,
          'isNeedEncryption': isNeedEncryption,
          "isLogStandardOutput": isLogStandardOutput,
          "logFilePath": logFilePath,
          'systemType': 'flutter',
          "operationID": Utils.checkOperationID(operationID),
        },
      ),
    );
  }

  /// Deinitialize the SDK
  Future<dynamic> unInitSDK() {
    return _channel.invokeMethod('unInitSDK', _buildParam({}));
  }

  /// Login
  /// [userID] User ID
  /// [token] Login token obtained from the business server
  /// [defaultValue] Default value to use if login fails
  Future<UserInfo> login({
    required String userID,
    required String token,
    String? operationID,
    Future<UserInfo> Function()? defaultValue,
    bool checkLoginStatus = true,
  }) async {
    int? status;
    if (checkLoginStatus) {
      // 1: logout 2: logging  3: logged
      status = await getLoginStatus();
    }
    if (status != LoginStatus.logging && status != LoginStatus.logged) {
      await _channel.invokeMethod(
        'login',
        _buildParam({
          'userID': userID,
          'token': token,
          'operationID': Utils.checkOperationID(operationID),
        }),
      );
    }
    this.isLogined = true;
    this.userID = userID;
    this.token = token;
    try {
      return this.userInfo = await userManager.getSelfUserInfo();
    } catch (error, stackTrace) {
      log('login e: $error  s: $stackTrace');
      if (null != defaultValue) {
        return this.userInfo = await (defaultValue.call());
      }
      return Future.error(error, stackTrace);
    }
  }

  /// Logout
  Future<dynamic> logout({String? operationID}) async {
    var value = await _channel.invokeMethod(
      'logout',
      _buildParam({
        'operationID': Utils.checkOperationID(operationID),
      }),
    );
    this.isLogined = false;
    this.token = null;
    return value;
  }

  /// Get login status
  /// 1: logout 2: logging  3: logged
  Future<int?> getLoginStatus({
    String? operationID,
  }) =>
      _channel.invokeMethod<int>(
        'getLoginStatus',
        _buildParam({
          'operationID': Utils.checkOperationID(operationID),
        }),
      );

  /// Get the current logged-in user ID
  Future<String> getLoginUserID() async => userID;

  /// Get the current logged-in user information
  Future<UserInfo> getLoginUserInfo() async => userInfo;

  /// [id] Same as [OnUploadFileListener] ID, to distinguish which file callback it is
  Future uploadFile({
    required String id,
    required String filePath,
    required String fileName,
    String? contentType,
    String? cause,
    String? cancelID,
    String? operationID,
  }) =>
      _channel.invokeMethod(
        'uploadFile',
        _buildParam({
          'id': id,
          'filePath': filePath,
          'name': fileName,
          'contentType': contentType,
          'cause': cause,
          'cancelID': cancelID,
          'operationID': Utils.checkOperationID(operationID),
        }),
      );

  Future cancelUpload(String cancelID, {String? operationID}) {
    return _channel.invokeMethod(
      'cancelUpload',
      _buildParam({
        'cancelID': cancelID,
        'operationID': Utils.checkOperationID(operationID),
      }),
    );
  }

  /// Update the Firebase client registration token
  /// [fcmToken] Firebase token
  Future updateFcmToken({
    required String fcmToken,
    required int expireTime,
    String? operationID,
  }) =>
      _channel.invokeMethod(
          'updateFcmToken',
          _buildParam({
            'fcmToken': fcmToken,
            'expireTime': expireTime,
            'operationID': Utils.checkOperationID(operationID),
          }));

  /// 上传日志
  ///
  Future uploadLogs({
    String? ex,
    int line = 0,
    String? operationID,
  }) =>
      _channel.invokeMethod(
          'uploadLogs',
          _buildParam({
            'ex': ex,
            'line': line,
            'operationID': Utils.checkOperationID(operationID),
          }));

  Future logs({
    int logLevel = 5,
    String? file,
    int line = 0,
    String? msgs,
    String? err,
    List<dynamic>? keyAndValues,
    String? operationID,
  }) =>
      _channel.invokeMethod(
          'logs',
          _buildParam({
            'line': line,
            'logLevel': logLevel,
            'file': file,
            'msgs': msgs,
            'err': err,
            if (keyAndValues != null) 'keyAndValue': jsonEncode(keyAndValues),
            'operationID': Utils.checkOperationID(operationID),
          }));

  void setUploadLogsListener(OnUploadLogsListener listener) {
    _uploadLogsListener = listener;
  }

  void setUploadFileListener(OnUploadFileListener listener) {
    _uploadFileListener = listener;
  }

  ///
  Future setListenerForService(OnListenerForService listener) {
    if (Platform.isAndroid) {
      this._listenerForService = listener;
      return _channel.invokeMethod('setListenerForService', _buildParam({}));
    } else {
      throw UnsupportedError("only supprot android platform");
    }
  }

  ZimSdkMethodChannel get channel => _channel;

  static Map<String, dynamic> _buildParam(Map<String, dynamic> param) {
    param["ManagerName"] = "imManager";
    param = Utils.cleanMap(param);
    return param;
  }
}
