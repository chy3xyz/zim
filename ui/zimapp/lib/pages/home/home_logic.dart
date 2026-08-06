
import 'package:flutter/material.dart';
import 'package:zim_sdk/zim_sdk.dart';
import 'package:flutter_screen_lock/flutter_screen_lock.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_working_circle/openim_working_circle.dart';
import 'package:rxdart/rxdart.dart';

import '../../core/controller/app_controller.dart';
import '../../core/controller/im_controller.dart';
import '../../routes/app_navigator.dart';
import '../../widgets/screen_lock_title.dart';

class HomeLogic extends SuperController {
  final pushLogic = Get.find<PushController>();
  final imLogic = Get.find<IMController>();
  final cacheLogic = Get.find<CacheController>();
  final initLogic = Get.find<AppController>();
  final index = 0.obs;
  final unreadMsgCount = 0.obs;
  final unhandledFriendApplicationCount = 0.obs;
  final unhandledGroupApplicationCount = 0.obs;
  final unreadMomentsCount = 0.obs;
  final unhandledCount = 0.obs;
  String? _lockScreenPwd;
  bool _isShowScreenLock = false;
  bool? _isAutoLogin;
  final auth = LocalAuthentication();
  final _errorController = PublishSubject<String>();
  var conversationsAtFirstPage = <ConversationInfo>[];

  Function()? onScrollToUnreadMessage;

  void switchTab(index) {
    this.index.value = index;
  }

  void scrollToUnreadMessage() {
    onScrollToUnreadMessage?.call();
  }

  /// 获取消息未读数
  void _getUnreadMsgCount() {
    OpenIM.iMManager.conversationManager.getTotalUnreadMsgCount().then((count) {
      unreadMsgCount.value = int.tryParse(count) ?? 0;
      initLogic.showBadge(unreadMsgCount.value);
    });
  }

  /// 获取好友申请未处理数
  /// 浏览过得不再计入红点
  void getUnhandledFriendApplicationCount() async {
    final lastReadTime = DataSp.getHaveReadUnHandleFriendApplicationTime();
    if (lastReadTime == null) {
      var i = 0;
      var list = await OpenIM.iMManager.friendshipManager.getFriendApplicationListAsRecipient();
      var haveReadList = DataSp.getHaveReadUnHandleFriendApplication();
      haveReadList ??= <String>[];
      for (var info in list) {
        var id = IMUtils.buildFriendApplicationID(info);
        if (!haveReadList.contains(id)) {
          if (info.handleResult == 0) i++;
        }
      }
      unhandledFriendApplicationCount.value = i;
      unhandledCount.value = unhandledGroupApplicationCount.value + i;
    } else {
      final req = GetFriendApplicationUnhandledCountReq(
        time: lastReadTime,
      );

      final count = await OpenIM.iMManager.friendshipManager.getFriendApplicationUnhandledCount(req);

      unhandledFriendApplicationCount.value = count;
      unhandledCount.value = unhandledGroupApplicationCount.value + count;
    }
  }

  /// 获取群申请未处理数
  void getUnhandledGroupApplicationCount() async {
    final lastReadTime = DataSp.getHaveReadUnHandleGroupApplicationTime();

    if (lastReadTime == null) {
      var i = 0;
      var list = await OpenIM.iMManager.groupManager.getGroupApplicationListAsRecipient();
      var haveReadList = DataSp.getHaveReadUnHandleGroupApplication();
      haveReadList ??= <String>[];
      for (var info in list) {
        var id = IMUtils.buildGroupApplicationID(info);
        if (!haveReadList.contains(id)) {
          if (info.handleResult == 0) i++;
        }
      }
      unhandledGroupApplicationCount.value = i;
      unhandledCount.value = unhandledFriendApplicationCount.value + i;
    } else {
      final req = GetGroupApplicationUnhandledCountReq(
        time: lastReadTime,
      );

      final count = await OpenIM.iMManager.groupManager.getGroupApplicationUnhandledCount(req);

      unhandledGroupApplicationCount.value = count;
      unhandledCount.value = unhandledFriendApplicationCount.value + count;
    }
  }

  @override
  void onInit() {
    _isAutoLogin = Get.arguments != null ? Get.arguments['isAutoLogin'] : false;
    if (_isAutoLogin == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showLockScreenPwd());
    }
    if (Get.arguments != null) {
      conversationsAtFirstPage = Get.arguments['conversations'] ?? [];
    }
    imLogic.unreadMsgCountEventSubject.listen((value) {
      unreadMsgCount.value = value;
    });
    imLogic.friendApplicationChangedSubject.listen((value) {
      getUnhandledFriendApplicationCount();
    });
    imLogic.groupApplicationChangedSubject.listen((value) {
      getUnhandledGroupApplicationCount();
    });
    imLogic.momentsSubject.listen((value) async {
      unreadMomentsCount.value = await WApis.getUnreadCount();
    });

    unreadMomentsCount.listen((value) {
      unhandledCount.value = value + unhandledFriendApplicationCount.value + unhandledGroupApplicationCount.value;
    });

    Apis.kickoffController.stream.listen((event) {
      DataSp.removeLoginCertificate();
      pushLogic.logout();
      AppNavigator.startLogin();
    });
    super.onInit();
  }

  @override
  void onReady() {
    initLogic.autoCheckVersionUpgrade();
    _getUnreadMsgCount();
    getUnhandledFriendApplicationCount();
    getUnhandledGroupApplicationCount();
    cacheLogic.initCallRecords();
    cacheLogic.initFavoriteEmoji();
    super.onReady();
  }

  @override
  void onClose() {
    _errorController.close();
    super.onClose();
  }

  void clearMomentsCount() {
    final temp = unreadMomentsCount.value;
    unreadMomentsCount.value = 0;
    unhandledCount.value -= temp;
  }

  Future<void> _localAuth() async {
    final didAuthenticate = await IMUtils.checkingBiometric(auth);
    if (didAuthenticate) {
      Get.back();
    }
  }

  Future<void> _showLockScreenPwd() async {
    if (_isShowScreenLock) return;
    _lockScreenPwd = DataSp.getLockScreenPassword();
    if (null != _lockScreenPwd) {
      final isEnabledBiometric = DataSp.isEnabledBiometric() == true;
      bool enabled = false;
      if (isEnabledBiometric) {
        final isSupportedBiometrics = await auth.isDeviceSupported();
        final canCheckBiometrics = await auth.canCheckBiometrics;
        enabled = isSupportedBiometrics && canCheckBiometrics;
      }
      _isShowScreenLock = true;
      screenLock(
        context: Get.context!,
        correctString: _lockScreenPwd!,
        maxRetries: 3,
        title: ScreenLockTitle(stream: _errorController.stream),
        canCancel: false,
        customizedButtonChild: enabled ? const Icon(Icons.fingerprint) : null,
        customizedButtonTap: enabled ? () async => await _localAuth() : null,
        // onOpened: enabled ? () async => await _localAuth() : null,
        onUnlocked: () {
          _isShowScreenLock = false;
          Get.back();
        },
        onMaxRetries: (_) async {
          Get.back();
          try {
            await LoadingView.singleton.wrap(asyncFunction: () async {
              await imLogic.logout();
              await DataSp.removeLoginCertificate();
              await DataSp.clearLockScreenPassword();
              await DataSp.closeBiometric();
              pushLogic.logout();
            });
          } catch (e) {
            Logger.print(e);
          } finally {
            AppNavigator.startLogin();
          }
        },
        onError: (retries) {
          _errorController.sink.add(
            retries.toString(),
          );
        },
      );
    }
  }

  @override
  void onDetached() {
  }

  @override
  void onInactive() {}

  @override
  void onPaused() {
  }

  @override
  void onResumed() {
  }

  @override
  void onHidden() {
    // TODO: implement onHidden
  }
}
