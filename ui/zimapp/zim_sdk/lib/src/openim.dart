import 'package:zim_sdk/src/client/method_channel.dart';
import 'package:zim_sdk/src/manager/im_manager.dart';

class OpenIM {
  static const version = 'zim_sdk-0.1.0';

  static final _channel = ZimSdkMethodChannel();
  static final iMManager = IMManager(_channel);

  OpenIM._();
}
