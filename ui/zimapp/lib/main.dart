import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bugly/flutter_bugly.dart';
import 'package:openim_common/openim_common.dart';

import 'app.dart';

void main() {
  FlutterBugly.postCatchedException(() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      Logger.print('FlutterError: ${details.exception.toString()}, ${details.stack.toString()}');
      // Upload to Bugly
      FlutterBugly.uploadException(
        type: details.exception.runtimeType.toString(),
        message: details.exception.toString(),
        detail: details.stack.toString(),
      );
    };

    Config.init(() => runApp(const ChatApp()));

    // Initialize Bugly
    FlutterBugly.init(
      androidAppId: "6ab9a7f158", // Replace with actual Bugly Android App ID
      iOSAppId: "2216e23c69", // Replace with actual Bugly iOS App ID
    );
  });

  // Additional error handler for uncaught async errors
  runZonedGuarded(() {}, (error, stackTrace) {
    Logger.print('FlutterError: ${error.toString()}, ${stackTrace.toString()}');
    // Upload to Bugly
    FlutterBugly.uploadException(
      type: error.runtimeType.toString(),
      message: error.toString(),
      detail: stackTrace.toString(),
    );
  });
}
