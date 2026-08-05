import 'package:zim_sdk/zim_sdk.dart';

class OnMessageKvInfoListener {
  Function(List<MessageKv> list)? onMessageKvInfoChanged;

  OnMessageKvInfoListener({this.onMessageKvInfoChanged});

  void messageKvInfoChanged(List<MessageKv> list) {
    onMessageKvInfoChanged?.call(list);
  }
}
