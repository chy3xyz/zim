import 'package:get/get.dart';

import 'robot_list_controller.dart';

class RobotListBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<RobotListController>(
      () => RobotListController(),
    );
  }
}
