import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import 'robot_list_controller.dart';

class SelectContactsFromRobotView extends GetView<SelectContactsFromRobotController> {
  const SelectContactsFromRobotView({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TitleBar.back(title: StrRes.robotList),
      backgroundColor: Styles.c_F8F9FA,
      body: Column(
        children: [
          if (controller.selectContactsLogic.isMultiModel)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10.h),
              child: Ink(
                height: 64.h,
                color: Styles.c_FFFFFF,
                child: InkWell(
                  onTap: controller.selectAll,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    child: Row(
                      children: [
                        Obx(() => Padding(
                              padding: EdgeInsets.only(right: 10.w),
                              child: ChatRadio(checked: controller.isSelectAll),
                            )),
                        10.horizontalSpace,
                        StrRes.selectAll.toText..style = Styles.ts_0C1C33_17sp,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Flexible(
            child: SmartRefresher(
              controller: controller.refreshController,
              header: IMViews.buildHeader(30),
              footer: IMViews.buildFooter(),
              enablePullUp: true,
              enablePullDown: true,
              onRefresh: controller.onRefresh,
              onLoading: controller.onLoadMore,
              child: Obx(
                () => controller.agents.isEmpty && controller.isRefreshEnd
                    ? _emptyListView()
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: controller.agents.length,
                        itemBuilder: (_, index) => _buildItemView(controller.agents[index]),
                      ),
              ),
            ),
          ),
          controller.selectContactsLogic.checkedConfirmView,
        ],
      ),
    );
  }

  Widget _emptyListView() {
    return Center(
      child: Text(
        StrRes.noRobot,
        style: Styles.ts_8E9AB0_17sp,
      ),
    );
  }

  Widget _buildItemView(Agent info) {
    Widget buildChild() => Ink(
          height: 64.h,
          color: Styles.c_FFFFFF,
          child: InkWell(
            onTap: controller.selectContactsLogic.onTap(info),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Row(
                children: [
                  if (controller.selectContactsLogic.isMultiModel)
                    Padding(
                      padding: EdgeInsets.only(right: 10.w),
                      child: ChatRadio(
                        checked: controller.selectContactsLogic.isChecked(info),
                        enabled: !controller.selectContactsLogic.isDefaultChecked(info),
                      ),
                    ),
                  AvatarView(
                    url: info.faceURL,
                    text: info.nickname,
                  ),
                  10.horizontalSpace,
                  info.nickname.toText..style = Styles.ts_0C1C33_17sp,
                ],
              ),
            ),
          ),
        );
    return controller.selectContactsLogic.isMultiModel ? Obx(buildChild) : buildChild();
  }
}
