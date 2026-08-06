import 'package:test/test.dart';
import 'package:zim_sdk/zim_sdk.dart';

/// Contract tests for Message/UserInfo JSON mapping.
///
/// These pin the camelCase OpenIM field names the SDK expects, so a backend
/// contract change (snake_case regression, renamed key) fails fast here.
/// Run: flutter test zim_sdk/test/message_model_test.dart
void main() {
  group('Message.fromJson', () {
    test('maps OpenIM camelCase fields', () {
      final m = Message.fromJson({
        'clientMsgID': 'cm1',
        'serverMsgID': 'sm1',
        'sendID': 'sender_u1',
        'recvID': 'recv_u2',
        'groupID': 'g_1',
        'senderFaceUrl': 'https://x/face.png',
        'senderNickname': 'Alice',
        'sessionType': 1,
        'msgFrom': 100,
        'contentType': 101,
        'status': 2,
        'sendTime': 1700000000000,
        'seq': 5,
      });
      expect(m.clientMsgID, 'cm1');
      expect(m.serverMsgID, 'sm1');
      expect(m.sendID, 'sender_u1');
      expect(m.recvID, 'recv_u2');
      expect(m.groupID, 'g_1');
      expect(m.senderFaceUrl, 'https://x/face.png');
      expect(m.senderNickname, 'Alice');
      expect(m.sessionType, 1);
      expect(m.msgFrom, 100);
      expect(m.contentType, 101);
      expect(m.status, 2);
      expect(m.sendTime, 1700000000000);
      expect(m.seq, 5);
    });

    test('tolerates missing optional fields', () {
      final m = Message.fromJson({'clientMsgID': 'cm1'});
      expect(m.clientMsgID, 'cm1');
      expect(m.recvID, isNull);
    });

    test('parses embedded elements', () {
      final m = Message.fromJson({
        'clientMsgID': 'cm1',
        'contentType': 103,
        'textElem': {'content': 'hello'},
        'pictureElem': {
          'sourcePath': 'a.jpg',
          'sourcePicture': {'url': 'https://x/a.jpg'},
        },
      });
      expect(m.textElem?.content, 'hello');
      expect(m.pictureElem?.sourcePath, 'a.jpg');
    });
  });

  group('UserInfo.fromJson', () {
    test('maps appMangerLevel and standard fields', () {
      final u = UserInfo.fromJson({
        'userID': 'u1',
        'nickname': 'Bob',
        'faceURL': 'https://x/b.png',
        'appMangerLevel': 2,
        'gender': 1,
        'ex': '{}',
      });
      expect(u.userID, 'u1');
      expect(u.nickname, 'Bob');
      expect(u.faceURL, 'https://x/b.png');
      expect(u.appMangerLevel, 2);
    });
  });
}
