import 'dart:io';

import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import 'robot_list_controller.dart';

class RobotListView extends GetView<RobotListController> {
  const RobotListView({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TitleBar.back(title: StrRes.robotList),
      backgroundColor: Styles.c_F8F9FA,
      body: SmartRefresher(
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
          )),
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

  Widget _buildItemView(Agent info) => GestureDetector(
        onTap: () => controller.onTap(info),
        child: Container(
          color: Styles.c_FFFFFF,
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10),
          child: Row(
            spacing: 8,
            children: [
              AvatarView(
                url: info.faceURL ?? ImageRes.myRobots,
                text: info.nickname,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  info.nickname.toText..style = Styles.ts_0C1C33_17sp,
                  info.model.toText..style = Styles.ts_8E9AB0_14sp,
                ],
              ),
            ],
          ),
        ),
      );
}
