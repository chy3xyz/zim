import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:zim_sdk/zim_sdk.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

class AlertMessageController extends GetxController {
  // Anti-disturbance mechanism
  final Map<String, DateTime> _lastNotificationTime = {};
  final Map<String, int> _pendingMessageCount = {};
  final Map<String, Timer?> _aggregationTimers = {};

  // Configuration parameters
  static const Duration _cooldownDuration = Duration(minutes: 2); // Cooldown time
  static const Duration _aggregationDelay = Duration(seconds: 3); // Aggregation delay
  static const int _maxImmediateNotifications = 2; // Maximum immediate notifications

  void showAlertMessage(Message message) {
    if (_isCurrentlyInChat(message) || !message.isNormalMessage || message.sendID == OpenIM.iMManager.userID) {
      return;
    }

    _handleSmartNotification(message);
  }

  /// Handle smart notification processing
  void _handleSmartNotification(Message message) {
    // Use groupID (group chat) or sendID (private chat) as conversation identifier
    final conversationId = message.groupID ?? message.sendID ?? 'unknown';
    final now = DateTime.now();

    // Get last notification time and pending message count
    final lastTime = _lastNotificationTime[conversationId];
    final pendingCount = _pendingMessageCount[conversationId] ?? 0;

    // Determine whether to show immediate notification
    if (_shouldShowImmediateNotification(lastTime, pendingCount, now)) {
      _showImmediateNotification(message, conversationId, now);
    } else {
      _scheduleAggregatedNotification(message, conversationId);
    }
  }

  /// Determine whether to show immediate notification
  bool _shouldShowImmediateNotification(DateTime? lastTime, int pendingCount, DateTime now) {
    // First time receiving message, show immediately
    if (lastTime == null) return true;

    // Within cooldown time but hasn't reached max immediate notifications
    if (now.difference(lastTime) < _cooldownDuration && pendingCount < _maxImmediateNotifications) {
      return true;
    }

    // Exceeded cooldown time, reset count
    if (now.difference(lastTime) >= _cooldownDuration) {
      return true;
    }

    return false;
  }

  /// Show immediate notification
  void _showImmediateNotification(Message message, String conversationId, DateTime now) {
    showSnackbar(message);
    _lastNotificationTime[conversationId] = now;
    _pendingMessageCount[conversationId] = (_pendingMessageCount[conversationId] ?? 0) + 1;
  }

  /// Schedule aggregated notification
  void _scheduleAggregatedNotification(Message message, String conversationId) {
    // Increase pending message count
    _pendingMessageCount[conversationId] = (_pendingMessageCount[conversationId] ?? 0) + 1;

    // Cancel previous aggregation timer
    _aggregationTimers[conversationId]?.cancel();

    // Set new aggregation timer
    _aggregationTimers[conversationId] = Timer(_aggregationDelay, () {
      _showAggregatedNotification(message, conversationId);
    });
  }

  /// Show aggregated notification
  void _showAggregatedNotification(Message message, String conversationId) {
    // Check if still in chat page, don't show aggregated notification if so
    if (_isCurrentlyInChat(message)) {
      _resetNotificationState(conversationId);
      return;
    }

    final pendingCount = _pendingMessageCount[conversationId] ?? 0;

    if (pendingCount > 1) {
      // Show aggregated message
      _showAggregatedSnackbar(message, pendingCount);
    } else {
      // Only one message, show normally
      showSnackbar(message);
    }

    _resetNotificationState(conversationId);
  }

  /// Check if currently in chat page
  bool _isCurrentlyInChat(Message message) {
    if (!Get.isRegistered<ChatLogic>(tag: GetTags.chat) && !Get.isRegistered<ChatLogic>(tag: GetTags.chatPreview)) {
      return true;
    }

    if (Get.isRegistered<ChatLogic>(tag: GetTags.chat)) {
      final logic = Get.find<ChatLogic>(tag: GetTags.chat);
      if (logic.isCurrentChat(message)) {
        return true;
      }
    }

    if (Get.isRegistered<ChatLogic>(tag: GetTags.chatPreview)) {
      final previewLogic = Get.find<ChatLogic>(tag: GetTags.chatPreview);
      if (previewLogic.isCurrentChat(message)) {
        return true;
      }
    }

    return false;
  }

  /// Reset notification state
  void _resetNotificationState(String conversationId) {
    _lastNotificationTime[conversationId] = DateTime.now();
    _pendingMessageCount[conversationId] = 0;
    _aggregationTimers[conversationId] = null;
  }

  /// Show aggregated snackbar
  void _showAggregatedSnackbar(Message message, int count) {
    final senderName = message.senderNickname ?? '';
    final isGroup = message.groupID != null;

    String title;
    String content;

    if (isGroup) {
      title = StrRes.groupChat;
      content = _getGroupAggregatedMessage(senderName, count);
    } else {
      title = senderName;
      content = _getPrivateAggregatedMessage(count);
    }

    _showSnackbar(message, title: title, content: content);
  }

  /// Show single message snackbar
  void showSnackbar(Message message) {
    final senderName = message.senderNickname ?? '';
    final content = IMUtils.parseMsg(message, isConversation: true, replaceIdToNickname: true);

    _showSnackbar(message, title: senderName, content: content);
  }

  /// Common snackbar display method
  void _showSnackbar(Message message, {required String title, required String content}) {
    Get.snackbar(
      title,
      content,
      mainButton: TextButton(
        onPressed: null,
        child: const Icon(
          Icons.keyboard_arrow_right,
          size: 24,
        ),
      ),
      onTap: (snack) {
        _handleSnackbarTap(message);
      },
    );
  }

  /// Get group aggregated message text
  String _getGroupAggregatedMessage(String senderName, int count) {
    return StrRes.groupAggregatedMessage.replaceFirst('{sender}', senderName).replaceFirst('{count}', count.toString());
  }

  /// Get private aggregated message text
  String _getPrivateAggregatedMessage(int count) {
    return StrRes.privateAggregatedMessage.replaceFirst('{count}', count.toString());
  }

  /// Handle snackbar tap event
  void _handleSnackbarTap(Message message) async {
    Get.closeCurrentSnackbar();

    // Clear notification marks for this conversation
    final conversationId = message.groupID ?? message.sendID ?? 'unknown';
    _clearNotificationMarks(conversationId);

    final sessionType = message.isGroupChat ? ConversationType.superGroup : ConversationType.single;
    final sourceID = message.isGroupChat ? message.groupID : message.sendID;
    final conversationInfo =
        await OpenIM.iMManager.conversationManager.getOneConversation(sourceID: sourceID!, sessionType: sessionType);
    AppNavigator.startChat(conversationInfo: conversationInfo, isPreviewChat: true);
  }

  /// Clear notification marks for a specific conversation
  void _clearNotificationMarks(String conversationId) {
    _lastNotificationTime.remove(conversationId);
    _pendingMessageCount.remove(conversationId);
    _aggregationTimers[conversationId]?.cancel();
    _aggregationTimers.remove(conversationId);
  }

  @override
  void onClose() {
    // Clean up all timers
    for (final timer in _aggregationTimers.values) {
      timer?.cancel();
    }
    _aggregationTimers.clear();
    super.onClose();
  }
}
