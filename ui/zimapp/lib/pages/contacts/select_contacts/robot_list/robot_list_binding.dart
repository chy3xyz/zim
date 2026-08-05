import 'package:get/get.dart';

import 'robot_list_controller.dart';

class SelectContactsFromRobotBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SelectContactsFromRobotController>(
      () => SelectContactsFromRobotController(),
    );
  }
}
