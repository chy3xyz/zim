import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_logic.dart';
import 'chat_view.dart';

/// PreviewChatPage - A dedicated page for preview chat mode
/// Uses PreviewChatLogic to isolate preview behavior from normal chat
class PreviewChatPage extends StatefulWidget {
  final String conversationName;

  const PreviewChatPage({
    super.key,
    required this.conversationName,
  });

  @override
  State<PreviewChatPage> createState() => _PreviewChatPageState();
}

class _PreviewChatPageState extends State<PreviewChatPage> {
  void _cleanupFocus() {
    // Clean up PreviewChat focus without auto-activating underlying keyboard
    try {
      final previewTag = GetTags.chatPreview;

      if (previewTag != null && Get.isRegistered<ChatLogic>(tag: previewTag)) {
        final previewLogic = Get.find<ChatLogic>(tag: previewTag);

        // Only unfocus if this node has focus or is primary focus
        if (previewLogic.focusNode.hasFocus || FocusManager.instance.primaryFocus == previewLogic.focusNode) {
          // First try to unfocus this specific node
          previewLogic.focusNode.unfocus();

          // If it somehow still remains primary focus, clear via FocusManager
          if (FocusManager.instance.primaryFocus == previewLogic.focusNode) {
            FocusManager.instance.primaryFocus?.unfocus();
          }
        }
      }
    } catch (e) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void _closePreview() {
    // Cleanup focus before navigation
    _cleanupFocus();

    // Close after a short delay to ensure cleanup completes
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<bool> _handleWillPop() async {
    _cleanupFocus();

    // Wait a frame to ensure focus cleanup completes
    await Future.delayed(const Duration(milliseconds: 50));
    return true;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final modalHeight = screenHeight * 5 / 6;

    return WillPopScope(
      onWillPop: _handleWillPop,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.black.withOpacity(0.5),
        body: GestureDetector(
          onTap: _closePreview,
          child: Container(
            color: Colors.transparent,
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {}, // Prevent tap from propagating
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                child: Container(
                  height: modalHeight,
                  color: Styles.c_FFFFFF,
                  child: Column(
                    children: [
                      // Header
                      _buildHeader(context),

                      // Chat content
                      Expanded(
                        child: ChatPage(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 56.h,
      decoration: BoxDecoration(
        color: Styles.c_FFFFFF,
        border: Border(
          bottom: BorderSide(
            color: Styles.c_E8EAEF,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Close button
          IconButton(
            icon: Icon(Icons.close, color: Styles.c_0C1C33),
            onPressed: _closePreview,
          ),

          // Title
          Expanded(
            child: Text(
              widget.conversationName,
              style: Styles.ts_0C1C33_17sp_medium,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Expand button
          IconButton(
            onPressed: () {
              // Cleanup focus before closing
              _cleanupFocus();

              // Close preview after delay
              Future.delayed(const Duration(milliseconds: 50), () {
                if (!mounted) return;

                // Close preview
                Get.back();

                // Open full chat
                GetTags.createChatTag();
                final arguments = Get.arguments as Map<String, dynamic>?;
                if (arguments != null) {
                  arguments.remove('isPreviewChat');
                  Get.offNamedUntil(
                    '/chat',
                    (route) => route.settings.name == '/home',
                    arguments: arguments,
                  );
                }
              });
            },
            icon: Icon(
              Icons.open_in_full,
              color: Styles.c_8E9AB0,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }
}
