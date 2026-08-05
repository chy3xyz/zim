import 'package:flutter/material.dart';
import 'package:zim_sdk/zim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class ChatFileIconView extends StatelessWidget {
  const ChatFileIconView({
    super.key,
    required this.message,
    this.sendProgressStream,
    this.downloadProgressView,
    this.sendStatusStream,
  });
  final Message message;
  final Stream<MsgStreamEv<int>>? sendProgressStream;
  final Stream<MsgStreamEv<bool>>? sendStatusStream;
  final Widget? downloadProgressView;

  @override
  Widget build(BuildContext context) {
    final id = message.clientMsgID!;
    final fileName = message.fileElem!.fileName!;
    final isISend = message.sendID == OpenIM.iMManager.userID;
    int? progress;

    if (message.isFileType) {
      final uploadProgress = message.attachedInfoElem?.uploadProgress;
      if (uploadProgress != null) {
        progress = ((uploadProgress.save! / uploadProgress.total!) * 100).toInt();
      }
    }

    return Stack(
      children: [
        IMUtils.fileIcon(fileName).toImage
          ..width = 38.w
          ..height = 44.h,
        ChatProgressView(
          isISend: isISend,
          width: 38.w,
          height: 44.h,
          id: id,
          stream: sendProgressStream,
          type: ProgressType.file,
          initialProgress: progress,
        ),
        if (null != downloadProgressView) downloadProgressView!,
      ],
    );
  }
}
