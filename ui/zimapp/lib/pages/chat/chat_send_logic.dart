// chat_send_logic.dart — mechanically split from ChatLogic (45 send-family
// methods); zero behavior change. `part of` shares the library scope so
// private members stay reachable; mixin applies to ChatLogicBase (fields +
// lifecycle live there).
part of 'chat_logic.dart';

mixin ChatSendLogic on ChatLogicBase {

  void sendTextMsg() async {
    var content = IMUtils.safeTrim(inputCtrl.text);
    if (content.isEmpty) return;
    Message message;
    if (curMsgAtUser.isNotEmpty) {
      createAtInfoByID(id) => AtUserInfo(
            atUserID: id,
            groupNickname: atUserNameMappingMap[id],
          );

      // 发送 @ 消息
      message = await OpenIM.iMManager.messageManager.createTextAtMessage(
        text: content,
        atUserIDList: curMsgAtUser,
        atUserInfoList: curMsgAtUser.map(createAtInfoByID).toList(),
        quoteMessage: quoteMsg,
      );
    } else if (quoteMsg != null) {
      // 发送引用消息
      message = await OpenIM.iMManager.messageManager.createQuoteMessage(
        text: content,
        quoteMsg: quoteMsg!,
      );
    } else {
      // 发送普通消息
      message = await OpenIM.iMManager.messageManager.createTextMessage(
        text: content,
      );
    }
    _sendMessage(message);
  }

  Future sendPicture({required String path, bool sendNow = true}) async {
    try {
      Logger.print('Sending picture from path: $path');

      // 检查原始文件是否存在
      final originalFile = File(path);
      if (!await originalFile.exists()) {
        Logger.print('Original image file does not exist: $path');
        IMViews.showToast('图片文件不存在');
        return;
      }

      final file = await IMUtils.compressImageAndGetFile(originalFile);

      if (file == null) {
        Logger.print('Failed to compress image, file is null');
        IMViews.showToast('图片处理失败');
        return;
      }

      final exists = await file.exists();
      Logger.print('Compressed file exists: $exists, path: ${file.path}');

      if (!exists) {
        Logger.print('Compressed file does not exist, using original file');
        // 如果压缩文件不存在，尝试使用原始文件
        if (await originalFile.exists()) {
          final message = await OpenIM.iMManager.messageManager.createImageMessageFromFullPath(
            imagePath: originalFile.path,
          );

          if (sendNow) {
            return _sendMessage(message);
          } else {
            _addMessage(message);
          }
        } else {
          IMViews.showToast('图片文件不存在');
          return;
        }
      } else {
        var message = await OpenIM.iMManager.messageManager.createImageMessageFromFullPath(
          imagePath: file.path,
        );

        if (sendNow) {
          return _sendMessage(message);
        } else {
          _addMessage(message);
        }
      }

      if (Platform.isIOS) {
        originalFile.deleteSync();
      }
    } catch (e, stackTrace) {
      Logger.print('Error sending picture: $e');
      Logger.print('StackTrace: $stackTrace');
      IMViews.showToast('发送图片失败: $e');
    }
  }

  void sendVoice(int duration, String path) async {
    var message = await OpenIM.iMManager.messageManager.createSoundMessageFromFullPath(
      soundPath: path,
      duration: duration,
    );
    _sendMessage(message);
  }

  Future sendVideo(
      {required String videoPath,
      required String mimeType,
      required int duration,
      required String thumbnailPath,
      bool sendNow = true}) async {
    // 插件有bug，有些视频长度*1000
    var d = duration > 1000.0 ? duration / 1000.0 : duration;
    var message = await OpenIM.iMManager.messageManager.createVideoMessageFromFullPath(
      videoPath: videoPath,
      videoType: mimeType,
      duration: d.toInt(),
      snapshotPath: thumbnailPath,
    );

    if (sendNow) {
      return _sendMessage(message);
    } else {
      _addMessage(message);
    }
  }

  void sendFile({required String filePath, required String fileName}) async {
    var message = await OpenIM.iMManager.messageManager.createFileMessageFromFullPath(
      filePath: filePath,
      fileName: fileName,
    );
    _sendMessage(message);
  }

  void sendLocation({
    required dynamic location,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createLocationMessage(
      latitude: location['latitude'],
      longitude: location['longitude'],
      description: location['description'],
    );
    _sendMessage(message);
  }

  Future sendForwardRemarkMsg(
    String content, {
    String? userId,
    String? groupId,
  }) async {
    final message = await OpenIM.iMManager.messageManager.createTextMessage(
      text: content,
    );
    _sendMessage(message, userId: userId, groupId: groupId);
  }

  Future sendForwardMsg(
    Message originalMessage, {
    String? userId,
    String? groupId,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createForwardMessage(
      message: originalMessage,
    );
    _sendMessage(message, userId: userId, groupId: groupId);
  }

  void sendMergeMsg({
    String? userId,
    String? groupId,
  }) async {
    final result = await createSummarys();
    String title;
    if (isGroupChat) {
      title = sprintf(StrRes.xChatRecord, [StrRes.groupChat]);
    } else {
      var partner1 = OpenIM.iMManager.userInfo.getShowName();
      var partner2 = await _querySenderNickname();
      title = sprintf(StrRes.xChatRecord, [
        sprintf(StrRes.aAndB, [partner1, partner2])
      ]);
    }
    var message = await OpenIM.iMManager.messageManager.createMergerMessage(
      messageList: result.messages,
      title: title,
      summaryList: result.summarys,
    );
    _sendMessage(message, userId: userId, groupId: groupId);
  }

  Future sendMessage(Message message, {String? userId, String? groupId}) {
    return _sendMessage(message, userId: userId, groupId: groupId);
  }

  void sendTypingMsg({bool focus = false}) async {
    if (isSingleChat) {
      OpenIM.iMManager.conversationManager
          .changeInputStates(conversationID: conversationInfo.conversationID, focus: focus);
    }
  }

  void sendCarte({
    required String userID,
    String? nickname,
    String? faceURL,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createCardMessage(
      userID: userID,
      nickname: nickname ?? '',
      faceURL: faceURL,
    );
    _sendMessage(message);
  }

  void sendCustomMsg({
    required String data,
    required String extension,
    required String description,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createCustomMessage(
      data: data,
      extension: extension,
      description: description,
    );
    _sendMessage(message);
  }

  Future _sendMessage(
    Message message, {
    String? userId,
    String? groupId,
    bool addToUI = true,
    bool notOSS = false,
  }) {
    log('send : ${json.encode(message)}');
    userId = IMUtils.emptyStrToNull(userId);
    groupId = IMUtils.emptyStrToNull(groupId);
    if (null == userId && null == groupId ||
        userId == userID && userId != null ||
        groupId == groupID && groupId != null) {
      if (addToUI) {
        // 失败重复不需要添加到ui
        if (!messageList.any((e) => e.clientMsgID == message.clientMsgID)) {
          _addMessage(message);
        }
        scrollBottom();
      }
    }
    Logger.print('uid:$userID userId:$userId gid:$groupID groupId:$groupId');
    _reset(message);
    // 借用当前聊天窗口，给其他用户或群发送信息，如合并转发，分享名片。
    bool useOuterValue = null != userId || null != groupId;

    if (directionalUsers.isNotEmpty) {
      message.dstUserIDs = directionalUsers.value.map((e) => e.userID!).toList();
    }

    final recvUserID = useOuterValue ? userId : userID;
    final recvGroupID = useOuterValue ? groupId : groupID;
    message.recvID = recvUserID;
    message.groupID = recvGroupID;

    if (notOSS) {
      return OpenIM.iMManager.messageManager
          .sendMessageNotOss(
            message: message,
            userID: recvUserID,
            groupID: recvGroupID,
            offlinePushInfo: Config.offlinePushInfo,
          )
          .then((value) => _sendSucceeded(message, value))
          .catchError((error, _) => _senFailed(message, groupId, userId, error, _))
          .whenComplete(() => _completed());
    } else {
      return OpenIM.iMManager.messageManager
          .sendMessage(
            message: message,
            userID: recvUserID,
            groupID: recvGroupID,
            offlinePushInfo: Config.offlinePushInfo,
          )
          .then((value) => _sendSucceeded(message, value))
          .catchError((error, _) => _senFailed(message, groupId, userId, error, _))
          .whenComplete(() => _completed());
    }
  }

  void _sendSucceeded(Message oldMsg, Message newMsg) {
    Logger.print('message send success----');
    // message.status = MessageStatus.succeeded;
    oldMsg.update(newMsg);
    sendStatusSub.addSafely(MsgStreamEv<bool>(
      id: oldMsg.clientMsgID!,
      value: true,
    ));
  }

  void _senFailed(Message message, String? groupId, String? userId, error, stack) async {
    Logger.print('message send failed userID: $userId groupId:$groupId, catch error :$error  $stack');
    message.status = MessageStatus.failed;
    sendStatusSub.addSafely(MsgStreamEv<bool>(
      id: message.clientMsgID!,
      value: false,
    ));
    if (error is PlatformException) {
      int code = int.tryParse(error.code) ?? 0;
      if (isSingleChat) {
        int? customType;
        if (code == SDKErrorCode.hasBeenBlocked) {
          customType = CustomMessageType.blockedByFriend;
        } else if (code == SDKErrorCode.notFriend) {
          customType = CustomMessageType.deletedByFriend;
        }
        if (null != customType) {
          final hintMessage = (await OpenIM.iMManager.messageManager.createFailedHintMessage(type: customType))
            ..status = 2
            ..isRead = true;
          if (userId != null) {
            if (userId == userID) {
              _addMessage(hintMessage);
            }
          } else {
            _addMessage(hintMessage);
          }
          OpenIM.iMManager.messageManager.insertSingleMessageToLocalStorage(
            message: hintMessage,
            receiverID: userId ?? userID,
            senderID: OpenIM.iMManager.userID,
          );
        }
      } else {
        if ((code == SDKErrorCode.userIsNotInGroup || code == SDKErrorCode.groupDisbanded) && null == groupId) {
          final status = groupInfo?.status;
          final hintMessage = (await OpenIM.iMManager.messageManager.createFailedHintMessage(
              type: status == 2 ? CustomMessageType.groupDisbanded : CustomMessageType.removedFromGroup))
            ..status = 2
            ..isRead = true;
          _addMessage(hintMessage);
          OpenIM.iMManager.messageManager.insertGroupMessageToLocalStorage(
            message: hintMessage,
            groupID: groupID,
            senderID: OpenIM.iMManager.userID,
          );
        }
      }
    }
  }

  void _reset(Message message) {
    if (message.contentType == MessageType.text ||
        message.contentType == MessageType.atText ||
        message.contentType == MessageType.quote) {
      inputCtrl.clear();
      setQuoteMsg(null);
    }
    closeMultiSelMode();
  }

  void _completed() {
    messageList.refresh();
    // setQuoteMsg(-1);
    // closeMultiSelMode();
    // inputCtrl.clear();
  }

  void setQuoteMsg(Message? message) {
    if (message == null) {
      quoteMsg = null;
      quoteContent.value = '';
    } else {
      quoteMsg = message;
      var name = quoteMsg!.senderNickname;
      quoteContent.value =
          "$name：${quoteMsg?.contentType == MessageType.revokeMessageNotification ? StrRes.quoteContentBeRevoked : IMUtils.parseMsg(
              quoteMsg!,
              replaceIdToNickname: true,
            )}";
      focusNode.requestFocus();
    }
  }

  void deleteMsg(Message message) {
    if (message.isPrivateType) {
      _deleteMessages(clientMsgIDs: [message.clientMsgID!], isSync: false);
      return;
    }
    showDeleteMessagesDialog(
      context: Get.context!,
      messages: [message],
      deleteMessages: _deleteMessages,
    );
  }

  void _deleteMultiMsg() async {
    if (multiSelList.isEmpty) return;

    await showDeleteMessagesDialog(
      context: Get.context!,
      messages: multiSelList,
      deleteMessages: _deleteMessages,
    );
    closeMultiSelMode();
  }

  Future _deleteMessages({required List<String> clientMsgIDs, bool isSync = false}) async {
    for (final clientMsgID in clientMsgIDs) {
      Logger.print('Deleting message with clientMsgID: $clientMsgID');

      await OpenIM.iMManager.messageManager
          .deleteMessageFromLocalAndSvr(
            conversationID: conversationInfo.conversationID,
            clientMsgID: clientMsgID,
          )
          .then((value) => privateMessageList.removeWhere((message) => clientMsgIDs.contains(message.clientMsgID)))
          .then((value) {
        chatObserver.standby(isRemove: true);
        messageList.removeWhere((message) => clientMsgIDs.contains(message.clientMsgID));
        _formatQuoteRevokeMessage(messageList.value);
        messageCache.removeMessages(clientMsgIDs);

        // Remove deleted message IDs from the set
        for (final id in clientMsgIDs) {
          _messageIds.remove(id);
        }
      });
    }
  }

  void forward(Message? message) async {
    final result = await AppNavigator.startSelectContacts(
      action: SelAction.forward,
      ex: null != message ? IMUtils.parseMsg(message) : sprintf(StrRes.mergeForwardHint, [multiSelList.length]),
    );
    if (null != result) {
      final customEx = result['customEx'];
      final checkedList = result['checkedList'];
      for (var info in checkedList) {
        final userID = IMUtils.convertCheckedToUserID(info);
        final groupID = IMUtils.convertCheckedToGroupID(info);

        if (null != message) {
          sendForwardMsg(message, userId: userID, groupId: groupID);
        } else {
          sendMergeMsg(userId: userID, groupId: groupID);
        }

        if (customEx is String && customEx.isNotEmpty) {
          sendForwardRemarkMsg(customEx, userId: userID, groupId: groupID);
        }
      }
    }
  }

  void _getInputState() async {
    if (conversationInfo.isSingleChat) {
      final result =
          await OpenIM.iMManager.conversationManager.getInputStates(conversationInfo.conversationID, userID!);
      typing.value = result?.isNotEmpty == true;
    }
  }

  void _changeInputStatus(bool focus) async {
    if (conversationInfo.isSingleChat) {
      await OpenIM.iMManager.conversationManager
          .changeInputStates(conversationID: conversationInfo.conversationID, focus: focus);
    }
  }

  void mergeDelete() => _deleteMultiMsg();

  void multiSelMsg(Message message, bool checked) {
    if (checked) {
      // 合并最多20条限制
      if (multiSelList.length >= 20) {
        showDialog(
          context: Get.context!,
          useRootNavigator: true,
          builder: (context) => CustomDialog(title: StrRes.forwardMaxCountHint),
        );
      } else {
        multiSelList.add(message);
        multiSelList.sort((a, b) {
          if (a.createTime! > b.createTime!) {
            return 1;
          } else if (a.createTime! < b.createTime!) {
            return -1;
          } else {
            return 0;
          }
        });
      }
    } else {
      multiSelList.remove(message);
    }
  }

  void openMultiSelMode(Message message) {
    multiSelMode.value = true;
    multiSelMsg(message, true);
  }

  void closeMultiSelMode() {
    multiSelMode.value = false;
    multiSelList.clear();
  }

  void closeToolbox() {
    forceCloseToolbox.addSafely(true);
  }

  void onTapLocation() async {
    var location = await Get.to(
      ChatWebViewMap(host: Config.locationHost, webKey: Config.webKey, webServerKey: Config.webServerKey),
      transition: Transition.cupertino,
      popGesture: true,
    );
    if (null != location) {
      Logger.print(location);
      sendLocation(location: location);
    }
  }

  void onTapAlbum() async {
    final List<AssetEntity>? assets = await AssetPicker.pickAssets(Get.context!,
        pickerConfig: AssetPickerConfig(
            gridThumbnailSize: ThumbnailSize(160, 160),
            sortPathsByModifiedDate: true,
            filterOptions: FilterOptionGroup(
                containsPathModified: true,
                imageOption: FilterOption(
                  sizeConstraint: SizeConstraint(
                    ignoreSize: true,
                  ),
                ),
                videoOption: FilterOption(
                  sizeConstraint: SizeConstraint(
                    ignoreSize: true,
                  ),
                )),
            selectPredicate: (_, entity, isSelected) async {
              if (entity.type == AssetType.image) {
                if (await allowSendImageType(entity)) {
                  return true;
                }

                IMViews.showToast(StrRes.supportsTypeHint);

                return false;
              }
              // 视频限制5分钟的时长
              if (entity.videoDuration > const Duration(seconds: 5 * 60)) {
                IMViews.showToast(sprintf(StrRes.selectVideoLimit, [5]) + StrRes.minute);
                return false;
              }
              return true;
            }));
    if (null != assets) {
      await _addAssetsToView(assets, sendNow: true);
    }
  }

  void onTapCamera() async {
    final AssetEntity? entity = await CameraPicker.pickFromCamera(
      Get.context!,
      locale: Get.locale,
      pickerConfig: CameraPickerConfig(
        enableAudio: true,
        enableRecording: true,
        enableScaledPreview: false,
        maximumRecordingDuration: 60.seconds,
        resolutionPreset: ResolutionPreset.high,
        lockCaptureOrientation: DeviceOrientation.portraitUp,
        onMinimumRecordDurationNotMet: () {
          IMViews.showToast(StrRes.tapTooShort);
        },
      ),
    );
    if (entity != null) {
      await _addAssetsToView([entity], sendNow: true);
    }
  }

  Future _addAssetsToView(List<AssetEntity> assets, {bool sendNow = false}) async {
    await Future.forEach(assets, (asset) => _handleAssets(asset, sendNow: sendNow));
  }

  void onTapFile() async {
    await FilePicker.platform.clearTemporaryFiles();
    FilePickerResult? result = await FilePicker.platform.pickFiles(
        // type: FileType.custom,
        // allowedExtensions: ['jpg', 'pdf', 'doc'],
        );

    if (result != null) {
      for (var file in result.files) {
        // String? mimeType = IMUtils.getMediaType(file.name);
        String? mimeType = lookupMimeType(file.name);
        if (mimeType != null) {
          if (IMUtils.allowImageType(mimeType)) {
            sendPicture(path: file.path!);
            continue;
          } else if (mimeType.contains('video/')) {
            try {
              final videoPath = file.path!;
              final mediaInfo = await IMUtils.getMediaInfo(videoPath);
              var thumbnailFile = await IMUtils.getVideoThumbnail(File(videoPath));

              sendVideo(
                videoPath: videoPath,
                mimeType: mimeType,
                duration: mediaInfo.duration!.toInt(),
                thumbnailPath: thumbnailFile.path,
              );
              continue;
            } catch (e, s) {
              Logger.print('e :$e  s:$s');
            }
          }
        }
        sendFile(filePath: file.path!, fileName: file.name);
      }
    } else {
      // User canceled the picker
    }
  }

  void onTapCarte() async {
    var result = await AppNavigator.startSelectContacts(
      action: SelAction.carte,
    );
    if (result is UserInfo || result is FriendInfo) {
      sendCarte(
        userID: result.userID!,
        nickname: result.nickname,
        faceURL: result.faceURL,
      );
    }
  }

  Future _handleAssets(AssetEntity? asset, {bool sendNow = true}) async {
    if (null != asset) {
      Logger.print('--------assets type-----${asset.type} create time: ${asset.createDateTime}');
      final originalFile = await asset.file;
      final originalPath = originalFile!.path;
      var path = originalPath.toLowerCase().endsWith('.gif') ? originalPath : originalFile.path;
      Logger.print('--------assets path-----$path');
      switch (asset.type) {
        case AssetType.image:
          sendPicture(path: path, sendNow: sendNow);
          break;
        case AssetType.video:
          var thumbnailFile = await IMUtils.getVideoThumbnail(File(path));
          var file = File(path);

          if (sendNow) {
            EasyLoading.show(status: StrRes.processingHint);
            final temp = await IMUtils.compressVideoAndGetFile(File(path));

            if (temp != null) {
              file = temp;
            }
            EasyLoading.dismiss();
          }

          await sendVideo(
            videoPath: file.path,
            mimeType: asset.mimeType ?? IMUtils.getMediaType(path)!,
            duration: asset.duration,
            thumbnailPath: thumbnailFile.path,
            sendNow: sendNow,
          );
          break;
        default:
          break;
      }
    }
  }

  void onTapDirectionalMessage() async {
    if (null != groupInfo) {
      final list = await AppNavigator.startGroupMemberList(
        groupInfo: groupInfo!,
        opType: GroupMemberOpType.call,
      );
      if (list is List<GroupMembersInfo>) {
        directionalUsers.assignAll(list);
      }
    }
  }

  void onClearDirectional() {
    directionalUsers.clear();
  }

  void parseClickEvent(Message msg) async {
    Logger.print('parseClickEvent:${jsonEncode(msg)}');
    if (msg.contentType == MessageType.custom) {
      var data = msg.customElem!.data;
      var map = json.decode(data!);
      var customType = map['customType'];
      if (CustomMessageType.call == customType && !isInBlacklist.value) {
      } else if (CustomMessageType.meeting == customType) {
      } else if (CustomMessageType.tag == customType) {
        final data = map['data'];
        if (null != data['soundElem']) {
          final soundElem = SoundElem.fromJson(data['soundElem']);
          msg.soundElem = soundElem;
          _playVoiceMessage(msg);
        }
      }
      return;
    }
    if (msg.contentType == MessageType.voice) {
      _playVoiceMessage(msg);
      // 收听则为已读
      _markMessageAsRead(msg);
      return;
    }
    if (msg.contentType == MessageType.groupInfoSetAnnouncementNotification) {
      AppNavigator.startEditGroupAnnouncement(
        groupID: groupInfo!.groupID,
      );
      return;
    }

    IMUtils.parseClickEvent(
      msg,
      messageList: messageList,
      onViewUserInfo: (userInfo) {
        viewUserInfo(userInfo, isCard: msg.isCardType);
      },
      onForward: () => forward(msg),
    );
  }

  void onStartVoiceInput() {
    // SpeechToTextUtil.instance.startListening((result) {
    //   inputCtrl.text = result.recognizedWords;
    // });
  }

  void onStopVoiceInput() {
    // SpeechToTextUtil.instance.stopListening();
  }

  void onAddEmoji(String emoji) {
    var input = inputCtrl.text;
    if (_lastCursorIndex != -1 && input.isNotEmpty) {
      var part1 = input.substring(0, _lastCursorIndex);
      var part2 = input.substring(_lastCursorIndex);
      inputCtrl.text = '$part1$emoji$part2';
      _lastCursorIndex = _lastCursorIndex + emoji.length;
    } else {
      inputCtrl.text = '$input$emoji';
      _lastCursorIndex = emoji.length;
    }
    inputCtrl.selection = TextSelection.fromPosition(TextPosition(
      offset: _lastCursorIndex,
    ));
  }

  void onDeleteEmoji() {
    final input = inputCtrl.text;
    final regexEmoji = emojiFaces.keys.toList().join('|').replaceAll('[', '\\[').replaceAll(']', '\\]');
    final list = [regexAt, regexEmoji];
    final pattern = '(${list.toList().join('|')})';
    final atReg = RegExp(regexAt);
    final emojiReg = RegExp(regexEmoji);
    var reg = RegExp(pattern);
    var cursor = _lastCursorIndex;
    if (cursor == 0) return;
    Match? match;
    if (reg.hasMatch(input)) {
      for (var m in reg.allMatches(input)) {
        var matchText = m.group(0)!;
        var start = m.start;
        var end = start + matchText.length;
        if (end == cursor) {
          match = m;
          break;
        }
      }
    }
    var matchText = match?.group(0);
    if (matchText != null) {
      var start = match!.start;
      var end = start + matchText.length;
      if (atReg.hasMatch(matchText)) {
        String id = matchText.replaceFirst("@", "").trim();
        if (curMsgAtUser.remove(id)) {
          inputCtrl.text = input.replaceRange(start, end, '');
          cursor = start;
        } else {
          inputCtrl.text = input.replaceRange(cursor - 1, cursor, '');
          --cursor;
        }
      } else if (emojiReg.hasMatch(matchText)) {
        inputCtrl.text = input.replaceRange(start, end, "");
        cursor = start;
      } else {
        inputCtrl.text = input.replaceRange(cursor - 1, cursor, '');
        --cursor;
      }
    } else {
      inputCtrl.text = input.replaceRange(cursor - 1, cursor, '');
      --cursor;
    }
    _lastCursorIndex = cursor;
  }

  void favoriteManage() => AppNavigator.startFavoriteMange();
}
