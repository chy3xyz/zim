import 'dart:async';

import 'package:zim_sdk/zim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim_common/openim_common.dart';

import '../../core/controller/im_controller.dart';
import '../../routes/app_navigator.dart';
import '../mine/server_config/server_config_binding.dart';
import '../mine/server_config/server_config_view.dart';

class SplashLogic extends GetxController {
  final imLogic = Get.find<IMController>();
  final pushLogic = Get.find<PushController>();

  String? get userID => DataSp.userID;

  String? get token => DataSp.imToken;

  void _firstLaunchServerConfig() {
    Get.to(
      () => ServerConfigPage(),
      binding: ServerConfigBinding(),
    );
  }

  late StreamSubscription initializedSub;

  @override
  void onInit() {
    // First launch (no server config saved): guide to server setup before
    // initializing the SDK so the app targets the right backend.
    final savedServer = DataSp.getServerConfig();
    if (savedServer == null || (savedServer['serverIP'] ?? '').isEmpty) {
      _firstLaunchServerConfig();
      return;
    }
    initializedSub = imLogic.initializedSubject.listen((value) {
      Logger.print('---------------------initialized---------------------');
      if (null != userID && null != token) {
        _login();
      } else {
        AppNavigator.startLogin();
      }
    });
    super.onInit();
  }

  _login() async {
    try {
      Logger.print('---------login---------- userID: $userID, token: $token');
      await imLogic.login(userID!, token!);
      Logger.print('---------im login success-------');
      pushLogic.login(
        userID!,
        onTokenRefresh: (token) {
          OpenIM.iMManager.updateFcmToken(
              fcmToken: token,
              expireTime: DateTime.now().add(Duration(days: 90)).millisecondsSinceEpoch);
        },
      );
      Logger.print('---------push login success----');
      final result = await ConversationLogic.getConversationFirstPage();

      AppNavigator.startSplashToMain(isAutoLogin: true, conversations: result);
    } catch (e, s) {
      IMViews.showToast('$e $s');
      await DataSp.removeLoginCertificate();
      AppNavigator.startLogin();
    }
  }

  @override
  void onClose() {
    initializedSub.cancel();
    super.onClose();
  }
}
