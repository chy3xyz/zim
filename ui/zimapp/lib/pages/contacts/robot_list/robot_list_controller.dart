import 'package:zim_sdk/zim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import '../../conversation/conversation_logic.dart';

class RobotListController extends GetxController {
  final agents = <Agent>[].obs;
  final RefreshController refreshController = RefreshController(
    initialRefresh: true,
  );
  int pageIndex = 1;
  int pageSize = 50;

  bool isRefreshEnd = false;

  @override
  void onClose() {
    super.onClose();
    refreshController.dispose();
  }

  Future onRefresh() async {
    pageIndex = 1;

    final result = await _getAgents(pageIndex: pageIndex);
    agents.assignAll(result);

    isRefreshEnd = true;
    
    if (result.length < pageSize) {
      refreshController.loadNoData();
    }
    refreshController.refreshCompleted();
  }

  void onLoadMore() {
    pageIndex++;

    _getAgents(pageIndex: pageIndex).then((value) {
      agents.addAll(value);

      if (value.length < pageSize) {
        refreshController.loadNoData();
      } else {
        refreshController.loadComplete();
      }
    });
  }

  Future<List<Agent>> _getAgents({
    int pageIndex = 1,
    int pageSize = 50,
  }) async {
    final result = await Apis.getAgents(
      showNumber: pageSize,
      pageNumber: pageIndex,
    );

    return result?.agents ?? [];
  }

  void onTap(Agent info) {
    final conversationLogic = Get.find<ConversationLogic>();

    conversationLogic.toChat(
      offUntilHome: true,
      userID: info.userID,
      nickname: info.nickname,
      faceURL: info.faceURL,
      sessionType: ConversationType.single,
      isRobot: true,
    );
  }
}
