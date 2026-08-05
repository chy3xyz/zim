import 'package:flutter/widgets.dart';

import 'chat_logic.dart';

/// PreviewChatLogic - Extends ChatLogic with preview-specific behavior
/// This isolates preview mode logic and prevents interference with normal chat
class PreviewChatLogic extends ChatLogic {
  @override
  void onInit() {
    // Set preview mode flag before initialization
    isPreviewChat = true;
    super.onInit();
  }

  @override
  void onClose() {
    // CRITICAL: Must cleanup focusNode BEFORE super.onClose()
    // because parent class will dispose() the focusNode

    // Aggressively clear focus before disposal
    if (focusNode.hasFocus || FocusManager.instance.primaryFocus == focusNode) {
      // Try multiple ways to clear focus
      focusNode.unfocus();

      // If still primary focus after unfocus, try harder
      if (FocusManager.instance.primaryFocus == focusNode) {
        // Clear primary focus via scope
        final context = focusNode.context;
        if (context != null && context.mounted) {
          FocusScope.of(context).unfocus();
        }

        // Final check
        if (FocusManager.instance.primaryFocus == focusNode) {}
      }
    }
    // Preview mode cleanup - parent class will dispose focusNode
    super.onClose();
  }

  // Override methods to customize preview behavior as needed
  // For example:
  // - Disable certain features
  // - Customize dialog handling
  // - Modify navigation behavior
}
