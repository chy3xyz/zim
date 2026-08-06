// chat_mention_logic.dart — mechanically split from ChatLogic (@-mention
// mapping/parsing methods); zero behavior change.
part of 'chat_logic.dart';

mixin ChatMentionLogic on ChatLogicBase {

  void clearCurAtMap() {
    // curMsgAtUser.removeWhere((uid) => !inputCtrl.text.contains('@$uid '));
  }

  void _putMemberInfo(List<GroupMembersInfo>? list) {
    list?.forEach((member) {
      _setAtMapping(
        userID: member.userID!,
        nickname: member.nickname!,
        faceURL: member.faceURL,
      );
      memberUpdateInfoMap[member.userID!] = member;
    });
    // 更新群成员信息
    messageList.refresh();
    atUserNameMappingMap[OpenIM.iMManager.userID] = StrRes.you;
    atUserInfoMappingMap[OpenIM.iMManager.userID] = OpenIM.iMManager.userInfo;

    // DataSp.putAtUserMap(groupID!, atUserNameMappingMap);
  }

  void _setAtMapping({
    required String userID,
    required String nickname,
    String? faceURL,
  }) {
    atUserNameMappingMap[userID] = nickname;
    atUserInfoMappingMap[userID] = UserInfo(
      userID: userID,
      nickname: nickname,
      faceURL: faceURL,
    );
    // DataSp.putAtUserMap(groupID!, atUserNameMappingMap);
  }

  _handleAtMemberList(memberList, cursor) {
    if (memberList is List<GroupMembersInfo>) {
      var buffer = StringBuffer();
      for (var e in memberList) {
        _setAtMapping(
          userID: e.userID!,
          nickname: e.nickname ?? '',
          faceURL: e.faceURL,
        );
        if (!curMsgAtUser.contains(e.userID)) {
          curMsgAtUser.add(e.userID!);
          buffer.write('@${e.userID} ');
        } else {
          buffer.write('@${e.userID} ');
        }
      }
      if (cursor < 0) cursor = 0;
      // 光标前面的内容
      var start = inputCtrl.text.substring(0, cursor);
      // 光标后面的内容
      var end = inputCtrl.text.substring(cursor + 1);
      inputCtrl.text = '$start$buffer$end';
      inputCtrl.selection = TextSelection.fromPosition(TextPosition(
        offset: '$start$buffer'.length,
      ));
      _lastCursorIndex = inputCtrl.selection.start;
    } else {}
  }
}
