import 'package:get/get.dart';
import 'package:openim/core/controller/alert_message_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/home/home_binding.dart';
import 'package:openim_common/openim_common.dart';

/// Global dependency initialization binding
class InitBinding extends Bindings {
  @override
  void dependencies() {
    // ThemeController is initialized in ChatApp's initState
    Get.put<AlertMessageController>(AlertMessageController());
    Get.put<IMController>(IMController());
    Get.put<PushController>(PushController(pushType: Config.pushType, config: Config.pushConfig));
    Get.put<CacheController>(CacheController());
    Get.put<DownloadController>(DownloadController());
    final homeBinding = HomeBinding();
    Get.lazyPut<HomeBinding>(() => homeBinding);
    homeBinding.dependencies();
  }
}
