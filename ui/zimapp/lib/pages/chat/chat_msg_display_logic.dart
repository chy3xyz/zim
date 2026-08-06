// chat_msg_display_logic.dart — mechanically split from ChatLogic (message
// display/interaction methods); zero behavior change.
part of 'chat_logic.dart';

mixin ChatMsgDisplayLogic on ChatLogicBase {

  bool isCurrentChat(Message message) {
    var senderId = message.sendID;
    var receiverId = message.recvID;
    var groupId = message.groupID;
    // var sessionType = message.sessionType;
    var isCurSingleChat = message.isSingleChat &&
        isSingleChat &&
        (senderId == userID ||
            // 其他端当前登录用户向uid发送的消息
            senderId == OpenIM.iMManager.userID && receiverId == userID);
    var isCurGroupChat = message.isGroupChat && isGroupChat && groupID == groupId;
    return isCurSingleChat || isCurGroupChat;
  }

  void scrollBottom() {
    _resetAboutLocateMessage();

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      scrollController.jumpTo(0);
    });
  }

  void formatQuoteMessage(String focusClientMsgID) {
    var quotes = messageList
        .where((element) =>
            element.contentType == MessageType.quote && element.quoteMessage?.clientMsgID == focusClientMsgID)
        .toList();
    quotes.forEach((element) {
      final textEelemt = element.quoteMessage?.textElem ?? TextElem();
      textEelemt.content = StrRes.quoteContentBeRevoked;
      element.quoteMessage?.textElem = textEelemt;
      element.quoteMessage?.contentType = 2101;
    });
  }

  void _addMessage(Message message) async {
    await _messageListLock.synchronized(() {
      // Check for duplicates using clientMsgID
      final msgId = message.clientMsgID ?? '';
      if (msgId.isEmpty || _messageIds.contains(msgId)) {
        Logger.print('_addMessage: duplicate message ignored: $msgId');
        return;
      }

      chatObserver.standby(
        mode: ChatScrollObserverHandleMode.normal,
      );

      messageList.insert(0, message);
      _messageIds.add(msgId);
      messageCache.addNewMessage(message);

      if (_isLocateQuoteMsg) {
        _messagesBeforeLocate.insert(0, message);
      }
    });
  }

  void onTapQuoteMsg(Message message) {
    // if (message.contentType == MessageType.quote) {
    //   parseClickEvent(message.quoteElem!.quoteMessage!);
    // } else if (message.contentType == MessageType.atText) {
    //   parseClickEvent(message.atElem!.quoteMessage!);
    // }
    if (message.isTextType || message.isAtTextType) {
      FullScreenView.show(
        context: Get.context!,
        text: message.textElem?.content ?? '',
        backgroundColor: Colors.grey.shade100,
      );
    } else {
      parseClickEvent(message);
    }
  }

  void onTapLocateQuoteMsg(Message message) {
    focusNode.unfocus();

    if (messageList.contains(message)) {
      // 如果原消息在当前消息列表中，也就是在ChatListView当前页，则定位到原消息位置
      final index = messageList.indexOf(message);

      observerController.jumpTo(
        index: index,
        alignment: 1,
        offset: (targetOffset) {
          return MediaQuery.of(Get.context!).size.height / 2;
        },
      );
    } else {
      // 如果原消息不在messageList中，则使用fetchSurroundingMessages获取原消息位置,然后使用fetchHistoryMessageList获取历史记录进行翻页
      OpenIM.iMManager.messageManager
          .fetchSurroundingMessages(
        FetchSurroundingMessagesReq(
          startMessage: message,
          before: 10,
          after: 10,
          viewType: FetchSurroundingHistoryViewType.history,
        ),
      )
          .then((value) {
        _isLocateQuoteMsg = true;
        _messagesBeforeLocate.assignAll(messageList.value);

        final msgs = value.reversed.toList();
        chatObserver.standby(changeCount: value.length);
        messageCache.assignMessages(value);
        messageList.assignAll(msgs);

        final index = messageList.indexOf(message);
        observerController.jumpTo(
          index: index,
          alignment: 1,
          offset: (targetOffset) {
            return MediaQuery.of(Get.context!).size.height / 2;
          },
        );
      }).catchError((error) {});
    }
  }

  void onLongPressLeftAvatar(Message message) {
    if (isMuted || isInvalidGroup) return;
    if (isGroupChat) {
      // 不查询群成员列表
      _setAtMapping(
        userID: message.sendID!,
        nickname: message.senderNickname!,
        faceURL: message.senderFaceUrl,
      );
      var uid = message.sendID!;
      // var uname = msg.senderNickName;
      if (curMsgAtUser.contains(uid)) return;
      curMsgAtUser.add(uid);
      // 在光标出插入内容
      // 先保存光标前和后内容
      var cursor = inputCtrl.selection.base.offset;
      if (!focusNode.hasFocus) {
        focusNode.requestFocus();
        cursor = _lastCursorIndex;
      }
      if (cursor < 0) cursor = 0;
      // 光标前面的内容
      var start = inputCtrl.text.substring(0, cursor);
      // 光标后面的内容
      var end = inputCtrl.text.substring(cursor);
      var at = '@$uid ';
      inputCtrl.text = '$start$at$end';
      Logger.print('start:$start end:$end  at:$at  content:${inputCtrl.text}');
      inputCtrl.selection = TextSelection.collapsed(offset: '$start$at'.length);
      // inputCtrl.selection = TextSelection.fromPosition(TextPosition(
      //   offset: '$start$at'.length,
      // ));
      _lastCursorIndex = inputCtrl.selection.start;
    }
  }

  void onTapLeftAvatar(Message message) {
    viewUserInfo(UserInfo()
      ..userID = message.sendID
      ..nickname = message.senderNickname
      ..faceURL = message.senderFaceUrl);
  }

  void onTapRightAvatar() {
    viewUserInfo(OpenIM.iMManager.userInfo);
  }

  void clickAtText(id) async {
    var tag = await OpenIM.iMManager.conversationManager.getAtAllTag();
    if (id == tag) return;
    if (null != atUserInfoMappingMap[id]) {
      viewUserInfo(atUserInfoMappingMap[id]!);
    } else {
      viewUserInfo(UserInfo(userID: id));
    }
  }

  void viewUserInfo(UserInfo userInfo, {bool isCard = false}) {
    if (isGroupChat && !isAdminOrOwner && !isCard) {
      if (groupInfo!.lookMemberInfo != 1) {
        AppNavigator.startUserProfilePane(
          userID: userInfo.userID!,
          nickname: userInfo.nickname,
          faceURL: userInfo.faceURL,
          groupID: groupID,
          offAllWhenDelFriend: isSingleChat,
        );
      }
    } else {
      AppNavigator.startUserProfilePane(
        userID: userInfo.userID!,
        nickname: userInfo.nickname,
        faceURL: userInfo.faceURL,
        groupID: groupID,
        offAllWhenDelFriend: isSingleChat,
        forceCanAdd: isCard,
      );
    }
  }

  void clickLinkText(url, type) async {
    Logger.print('--------link  type:$type-------url: $url---');
    if (type == PatternType.at) {
      clickAtText(url);
      return;
    }
    if (await canLaunch(url)) {
      await launch(url);
    }
    // await canLaunch(url) ? await launch(url) : throw 'Could not launch $url';
  }

  void _readDraftText() {
    var draftText = Get.arguments['draftText'];
    Logger.print('readDraftText:$draftText');
    if (null != draftText && "" != draftText) {
      var map = json.decode(draftText!);
      String text = map['text'];
      Map<String, dynamic> atMap = map['at'];
      Logger.print('text:$text  atMap:$atMap');
      atMap.forEach((key, value) {
        if (!curMsgAtUser.contains(key)) curMsgAtUser.add(key);
        atUserNameMappingMap.putIfAbsent(key, () => value);
      });
      inputCtrl.text = text;
      inputCtrl.selection = TextSelection.fromPosition(TextPosition(
        offset: text.length,
      ));
      if (text.isNotEmpty) {
        focusNode.requestFocus();
      }
    }
  }

  String createDraftText() {
    var atMap = <String, dynamic>{};
    for (var uid in curMsgAtUser) {
      atMap[uid] = atUserNameMappingMap[uid];
    }
    if (inputCtrl.text.isEmpty) {
      return "";
    }
    return json.encode({'text': inputCtrl.text, 'at': atMap});
  }

  void _updateDartText(String text) {
    conversationLogic.updateDartText(
      text: text,
      conversationID: conversationInfo.conversationID,
    );
  }

  void focusNodeChanged(bool hasFocus) {
    _changeInputStatus(hasFocus);
    if (hasFocus) {
      Logger.print('focus:$hasFocus');
      scrollBottom();
    }
  }

  void copy(Message message) {
    String? content;
    final textElem = message.tagContent?.textElem;
    if (null != textElem) {
      content = textElem.content;
    } else if (message.isAtTextType) {
      content = message.atTextElem!.text;
    } else {
      content = copyTextMap[message.clientMsgID] ?? message.textElem?.content;
    }
    if (message.isNoticeType) {
      content = message.noticeContent;
    }

    if (message.isQuoteType) {
      content = message.quoteElem?.text;
    }
    if (null != content) {
      IMUtils.copy(text: content.replaceAll('\u200B', ''), showToast: false);
    }
  }

  Message indexOfMessage(int index, {bool calculate = true}) => IMUtils.calChatTimeInterval(
        messageList,
        calculate: calculate,
      ).reversed.elementAt(index);

  ValueKey itemKey(Message message) => ValueKey(message.clientMsgID!);

  @override
  

  void onClose() {
    messageCache.clear();
    _messageIds.clear();
    sendTypingMsg();
    _clearUnreadCount();
    // ChatGetTags.caches.removeLast();
    _unSubscribeUserOnlineStatus();
    inputCtrl.dispose();
    focusNode.dispose();
    _audioPlayer.dispose();
    // clickSubject.close();
    forceCloseToolbox.close();
    conversationSub.cancel();
    _newMessageSubscription.cancel();
    sendStatusSub.close();
    sendProgressSub.close();
    downloadProgressSub.close();
    memberAddSub.cancel();
    memberDelSub.cancel();
    memberInfoChangedSub.cancel();
    groupInfoUpdatedSub.cancel();
    friendInfoChangedSub.cancel();
    userStatusChangedSub?.cancel();
    selfInfoUpdatedSub?.cancel();
    // signalingMessageSub?.cancel();
    forceCloseMenuSub.close();
    joinedGroupAddedSub.cancel();
    joinedGroupDeletedSub.cancel();
    connectionSub.cancel();
    // onlineStatusTimer?.cancel();
    destroyMsg();

    _debounce?.cancel();
    unreadMsgCountEventSubscription?.cancel();
    _disposeObserver();
    super.onClose();
  }

  void clearAllMessage() {
    messageList.clear();
    _messageIds.clear();
  }
}
