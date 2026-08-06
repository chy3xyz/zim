// chat_history_logic.dart — mechanically split from ChatLogic (history sync,
// scroll listeners, unread/online-status updates); zero behavior change.
part of 'chat_logic.dart';

mixin ChatHistoryLogic on ChatLogicBase {

  void didChangeMetrics() {
    super.didChangeMetrics();
    // Update shrinkWrap in real time as the keyboard pops up or closes.
    chatObserver.observeSwitchShrinkWrap();
  }

  void _setupScrollObserver() {
    WidgetsBinding.instance.addObserver(this);
    scrollController.addListener(scrollControllerListener);
    observerController = ListObserverController(controller: scrollController)..cacheJumpIndexOffset = false;

    chatObserver = ChatScrollObserver(observerController)
      ..fixedPositionOffset = 5
      ..toRebuildScrollViewCallback = () {
        print('toRebuildScrollViewCallback');
        messageList.refresh();
      }
      ..onHandlePositionResultCallback = (result) {
        if (!needIncrementUnreadMsgCount) return;
        switch (result.type) {
          case ChatScrollObserverHandlePositionType.keepPosition:
            updateUnreadMsgCount(changeCount: result.changeCount);
            break;
          case ChatScrollObserverHandlePositionType.none:
            updateUnreadMsgCount(isReset: true);
            break;
        }
      };
  }

  void updateUnreadMsgCount({
    bool isReset = false,
    int changeCount = 1,
  }) {
    needIncrementUnreadMsgCount = false;
    if (isReset) {
      unreadMsgCount.value = 0;
    } else {
      unreadMsgCount.value += changeCount;
    }
  }

  void scrollControllerListener() {
    const threshold = 2.0;
    if (scrollController.hasClients &&
        scrollController.positions.length == 1 &&
        (scrollController.offset >= scrollController.position.maxScrollExtent - threshold)) {
      _loadMoreHistory();
    } else if (_isLocateQuoteMsg &&
        scrollController.hasClients &&
        scrollController.positions.length == 1 &&
        scrollController.offset < 50) {
      _loadNewestHistory().then((count) {
        if (count == 0) {
          _resetAboutLocateMessage(updateMsgs: false);
        }
      });
    }

    if (scrollController.hasClients &&
        scrollController.positions.length == 1 &&
        scrollController.offset < 50 &&
        !_isLocateQuoteMsg) {
      updateUnreadMsgCount(isReset: true);
    }
  }

  void _disposeObserver() {
    WidgetsBinding.instance.removeObserver(this);
    observerController.controller?.dispose();
  }

  void _resetAboutLocateMessage({bool updateMsgs = true}) {
    if (!_isLocateQuoteMsg) {
      return;
    }

    cacheExtentWhenLocateQuoteMsg = null;
    _isLocateQuoteMsg = false;

    if (!updateMsgs) {
      return;
    }

    bool isAllIncluded = _messagesBeforeLocate.every((m) => messageList.value.contains(m));

    if (!isAllIncluded) {
      messageCache.assignMessages(_messagesBeforeLocate);
      chatObserver.standby(changeCount: _messagesBeforeLocate.length);
      messageList.assignAll(_messagesBeforeLocate);
    }
  }

  bool showOnlineStatus() => !typing.value && onlineStatusDesc.isNotEmpty;

  void onScrollToTop() {
    // if (scrollingCacheMessageList.isNotEmpty) {
    //   messageList.addAll(scrollingCacheMessageList);
    //   scrollingCacheMessageList.clear();
    // }
  }

  Future<void> _loadMoreHistory() async {
    final msgs = await messageCache.fetchMessages(
      count: _pageSize,
      fetchFromDB: _isLocateQuoteMsg,
    );

    if (msgs.isEmpty) return;

    final filtered = msgs.where((msg) => !_isBeDeleteMessage(msg)).toList();
    _formatQuoteRevokeMessage(filtered);

    // Use lock to prevent concurrent modification
    await _messageListLock.synchronized(() {
      // Filter out duplicates
      final newMessages = <Message>[];
      for (final msg in filtered) {
        final msgId = msg.clientMsgID ?? '';
        if (msgId.isNotEmpty && !_messageIds.contains(msgId)) {
          newMessages.add(msg);
          _messageIds.add(msgId);
        }
      }

      if (newMessages.isNotEmpty) {
        chatObserver.standby(changeCount: newMessages.length);
        messageList.addAll(newMessages);
      }
    });
  }

  Future<int> _loadNewestHistory() async {
    final msgs = await messageCache.fetchMessages(
      count: _pageSize,
      reverse: true,
      fetchFromDB: _isLocateQuoteMsg,
    );
    final filtered = msgs.where((msg) => !_isBeDeleteMessage(msg)).toList();
    _formatQuoteRevokeMessage(filtered);

    int addedCount = 0;

    // Use lock to prevent concurrent modification
    await _messageListLock.synchronized(() {
      // Filter out duplicates
      final newMessages = <Message>[];
      for (final msg in filtered) {
        final msgId = msg.clientMsgID ?? '';
        if (msgId.isNotEmpty && !_messageIds.contains(msgId)) {
          newMessages.add(msg);
          _messageIds.add(msgId);
        }
      }

      addedCount = newMessages.length;

      if (newMessages.isNotEmpty) {
        chatObserver.fixedPositionOffset = -1;
        chatObserver.standby(changeCount: newMessages.length);
        cacheExtentWhenLocateQuoteMsg = newMessages.length * 200 + 200;
        messageList.insertAll(0, newMessages);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      chatObserver.fixedPositionOffset = 5;
    });

    return addedCount;
  }

  Future<void> _loadHistoryForSyncEnd() async {
    if (_isLocateQuoteMsg) {
      return;
    }
    final msgs = await messageCache.fetchMessages(
      count: _pageSize,
      refresh: true,
    );

    if (msgs.isEmpty) return;

    final filtered = msgs.where((msg) => !_isBeDeleteMessage(msg)).toList();
    _formatQuoteRevokeMessage(filtered);
    final offset =
        (scrollController.hasClients && scrollController.positions.length == 1) ? scrollController.offset : 0.0;

    // Use lock to prevent concurrent modification
    await _messageListLock.synchronized(() {
      chatObserver.standby(changeCount: filtered.length);
      messageList.assignAll(filtered);

      // Rebuild the message ID set
      _messageIds.clear();
      for (final msg in filtered) {
        final msgId = msg.clientMsgID ?? '';
        if (msgId.isNotEmpty) {
          _messageIds.add(msgId);
        }
      }
    });

    if (scrollController.hasClients) {
      scrollController.jumpTo(offset);
    }
  }
}
