import 'package:flutter/material.dart';
import 'package:zim_sdk/zim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/mine/mine_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/im_controller.dart';
import '../../../core/controller/theme_controller.dart';

class AccountSetupLogic extends GetxController {
  final imLogic = Get.find<IMController>();
  final themeController = Get.find<ThemeController>();
  final curLanguage = "".obs;
  final curTheme = "".obs;

  @override
  void onReady() {
    _updateLanguage();
    _updateTheme();
    super.onReady();
  }

  @override
  void onInit() {
    _queryMyFullInfo();
    super.onInit();
  }

  /// 全局免打扰 0：正常；1：不接受消息；2：接受在线消息不接受离线消息；
  bool get isGlobalNotDisturb => imLogic.userInfo.value.globalRecvMsgOpt == 2;

  bool get isAllowAddFriend => imLogic.userInfo.value.allowAddFriend == 1;

  bool get isAllowBeep => imLogic.userInfo.value.allowBeep == 1;

  bool get isAllowVibration => imLogic.userInfo.value.allowVibration == 1;

  void _queryMyFullInfo() async {
    final data = await Apis.queryMyFullInfo();

    if (data is UserFullInfo) {
      final userInfo = UserFullInfo.fromJson(data.toJson());
      imLogic.userInfo.update((val) {
        val?.allowAddFriend = userInfo.allowAddFriend;
        val?.allowBeep = userInfo.allowBeep;
        val?.allowVibration = userInfo.allowVibration;
      });
    }
  }

  void toggleNotDisturbMode() async {
    var status = isGlobalNotDisturb ? 0 : 2;
    await LoadingView.singleton
        .wrap(asyncFunction: () => OpenIM.iMManager.userManager.setGlobalRecvMessageOpt(status: status));
    imLogic.userInfo.update((val) {
      val?.globalRecvMsgOpt = status;
    });

    // When enabling Do Not Disturb, automatically disable beep and vibration
    if (status == 2) {
      if (isAllowBeep) {
        await _updateBeep(2); // 2 means disabled
      }
      if (isAllowVibration) {
        await _updateVibration(2); // 2 means disabled
      }
    }
  }

  Future<void> _updateBeep(int allowBeep) async {
    await Apis.updateUserInfo(
      allowBeep: allowBeep,
      userID: OpenIM.iMManager.userID,
    );
    imLogic.userInfo.update((val) {
      val?.allowBeep = allowBeep;
    });
  }

  void toggleBeep() async {
    // Cannot toggle if Do Not Disturb mode is enabled
    if (isGlobalNotDisturb) return;

    final allowBeep = !isAllowBeep ? 1 : 2;
    await LoadingView.singleton.wrap(
      asyncFunction: () => _updateBeep(allowBeep),
    );
  }

  Future<void> _updateVibration(int allowVibration) async {
    await Apis.updateUserInfo(
      allowVibration: allowVibration,
      userID: OpenIM.iMManager.userID,
    );
    imLogic.userInfo.update((val) {
      val?.allowVibration = allowVibration;
    });
  }

  void toggleVibration() async {
    // Cannot toggle if Do Not Disturb mode is enabled
    if (isGlobalNotDisturb) return;

    final allowVibration = !isAllowVibration ? 1 : 2;
    await LoadingView.singleton.wrap(
      asyncFunction: () => _updateVibration(allowVibration),
    );
  }

  void toggleForbidAddMeToFriend() async {
    final allowAddFriend = !isAllowAddFriend ? 1 : 2;
    // 1关闭 2开启
    final data = await LoadingView.singleton.wrap(
      asyncFunction: () => Apis.updateUserInfo(
        allowAddFriend: allowAddFriend,
        userID: OpenIM.iMManager.userID,
      ),
    );
    imLogic.userInfo.update((val) {
      val?.allowAddFriend = allowAddFriend;
    });
  }

  void blacklist() => AppNavigator.startBlacklist();

  void clearChatHistory() async {
    var confirm = await Get.dialog(CustomDialog(
      title: StrRes.confirmClearChatHistory,
    ));
    if (confirm == true) {
      LoadingView.singleton.wrap(asyncFunction: () async {
        await OpenIM.iMManager.messageManager.deleteAllMsgFromLocalAndSvr();
      });
    }
  }

  void deleteAccount() async {
    var confirm = await Get.dialog(CustomDialog(
      alignment: Alignment.centerLeft,
      title: StrRes.confirmDeleteAccount,
      content: StrRes.confirmDeleteAccountHint,
    ));
    if (confirm == true) {
      try {
        await LoadingView.singleton.wrap(asyncFunction: () => Apis.deleteAccount([OpenIM.iMManager.userID]));
        Get.find<MineLogic>().logoutHelper();
      } catch (e) {
        Logger.print('Failed to delete account: $e');
        IMViews.showToast('Failed to delete account: $e');
      }
    }
  }

  void languageSetting() => AppNavigator.startLanguageSetup();

  void _updateLanguage() {
    var index = DataSp.getLanguage() ?? 0;
    switch (index) {
      case 1:
        curLanguage.value = StrRes.chinese;
        break;
      case 2:
        curLanguage.value = StrRes.english;
        break;
      default:
        curLanguage.value = StrRes.followSystem;
        break;
    }
  }

  void _updateTheme() {
    var index = DataSp.getThemeMode();
    switch (index) {
      case 1:
        curTheme.value = StrRes.lightMode;
        break;
      case 2:
        curTheme.value = StrRes.darkMode;
        break;
      default:
        curTheme.value = StrRes.followSystem;
        break;
    }
  }

  void themeSetting() async {
    final index = await Get.bottomSheet(
      BottomSheetView(
        items: [
          SheetItem(
            label: StrRes.followSystem,
            result: 0,
          ),
          SheetItem(
            label: StrRes.lightMode,
            result: 1,
          ),
          SheetItem(
            label: StrRes.darkMode,
            result: 2,
          ),
        ],
      ),
    );
    if (null != index) {
      switch (index) {
        case 0:
          themeController.setSystemMode();
          break;
        case 1:
          themeController.setLightMode();
          break;
        case 2:
          themeController.setDarkMode();
          break;
      }
      _updateTheme();
    }
  }

  void unlockSetup() => AppNavigator.startUnlockSetup();

  void changePwd() => AppNavigator.startChangePassword();
}
