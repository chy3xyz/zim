// Backend integration test — verifies the full data path between zim_sdk
// (pure Dart) and the running zim backend (HTTP :10000, WS :10001).
//
// Prereq: zim backend running (cd src && ./zig-out/bin/zim).
// Run:   flutter test test/backend_integration_test.dart
//
// Covers: register → login → add-friend → send message → conversation sync →
//         message pull → read receipt. Skips (with a notice) when backend down.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zim_sdk/zim_sdk.dart';

/// path_provider needs a platform channel; on the VM test runner we point it
/// at the system temp dir.
class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async => Directory.systemTemp.path;

  @override
  Future<String?> getTemporaryDirectoryPath() async => Directory.systemTemp.path;

  @override
  Future<String?> getApplicationSupportPath() async => Directory.systemTemp.path;
}

const apiAddr = 'http://localhost:10000';
const wsAddr = 'ws://localhost:10001';

Future<bool> backendUp() async {
  try {
    final c = HttpClient();
    final req = await c.getUrl(Uri.parse('$apiAddr/health')).timeout(const Duration(seconds: 2));
    final resp = await req.close().timeout(const Duration(seconds: 2));
    c.close();
    return resp.statusCode == 200;
  } catch (_) {
    return false;
  }
}

Future<Map<String, dynamic>> httpPost(String path, Map<String, dynamic> body,
    {String? token}) async {
  final c = HttpClient();
  final req = await c.postUrl(Uri.parse('$apiAddr$path'));
  req.headers.contentType = ContentType.json;
  if (token != null) req.headers.set('token', token);
  req.headers.set('connection', 'close');
  final bytes = utf8.encode(jsonEncode(body));
  req.contentLength = bytes.length;
  req.add(bytes);
  final resp = await req.close().timeout(const Duration(seconds: 10));
  final text = await resp.transform(utf8.decoder).join();
  c.close();
  final decoded = jsonDecode(text) as Map<String, dynamic>;
  expect(decoded['errCode'], 0, reason: '$path failed: $text');
  return (decoded['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
}

void main() {
  final suffix = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
  final uidA = 'it_a_$suffix';
  final uidB = 'it_b_$suffix';

  test('full pipeline: register/login/friend/message/conversation via real backend', () async {
    if (!await backendUp()) {
      markTestSkipped('zim backend not running on $apiAddr — start it first');
      return;
    }
    PathProviderPlatform.instance = _FakePathProvider();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // 1. register A and B
    await httpPost('/account/register',
        {'user': {'nickname': 'IT-A', 'password': 'test1234', 'account': uidA}});
    await httpPost('/account/register',
        {'user': {'nickname': 'IT-B', 'password': 'test1234', 'account': uidB}});

    // 2. login A (get IM token)
    final loginA = await httpPost('/account/login', {'account': uidA, 'password': 'test1234'});
    final tokenA = loginA['imToken'] as String;
    expect(tokenA, isNotEmpty);
    final loginB = await httpPost('/account/login', {'account': uidB, 'password': 'test1234'});
    final tokenB = loginB['imToken'] as String;

    // 3. A adds B as friend (through SDK-free HTTP for the relation)
    await httpPost('/friend/add_friend', {'fromUserID': uidA, 'toUserID': uidB}, token: tokenA);
    await httpPost('/friend/add_friend_response',
        {'fromUserID': uidA, 'toUserID': uidB, 'handleResult': 1}, token: tokenB);
    final friends = await httpPost('/friend/get_friend_list', {'userID': uidA}, token: tokenA);
    final friendList = (friends['friendsInfo'] ?? []) as List;
    expect(friendList.any((f) => (f as Map)['friendUserID'] == uidB), isTrue,
        reason: 'A should have B as friend');

    // 4. SDK-side: init + login as A
    var loggedIn = false;
    final listener = OnConnectListener(
      onConnecting: () {},
      onConnectSuccess: () {},
      onConnectFailed: (code, msg) {},
      onKickedOffline: () {},
      onUserTokenExpired: () {},
    );
    final initOk = await OpenIM.iMManager.initSDK(
      platformID: 1,
      apiAddr: apiAddr,
      wsAddr: wsAddr,
      dataDir: Directory.systemTemp.path,
      listener: listener,
    );
    expect(initOk, isTrue);
    final userInfo = await OpenIM.iMManager.login(userID: uidA, token: tokenA);
    expect(userInfo.userID, uidA);
    loggedIn = true;

    // 5. send a text message A → B via the SDK
    final msg = await OpenIM.iMManager.messageManager.createTextMessage(text: 'it-pipeline-${DateTime.now().millisecondsSinceEpoch}');
    final sent = await OpenIM.iMManager.messageManager.sendMessage(
      message: msg,
      offlinePushInfo: OfflinePushInfo(),
      userID: uidB,
      groupID: null,
    );
    expect(sent.serverMsgID, isNotNull);
    // Backend SendMsgResp carries serverMsgID/clientMsgID/sendTime/seq only
    // (Go contract) — sendID is not echoed back.
    expect(sent.clientMsgID, isNotNull);

    // 6. conversation auto-created for A with B as latest sender
    final convs = await httpPost('/conversation/get_sorted_conversation_list', {'userID': uidA}, token: tokenA);
    final elems = (convs['conversationElems'] ?? []) as List;
    expect(elems, isNotEmpty, reason: 'A must have at least one conversation');
    final elem = elems.first as Map;
    final convID = elem['conversationID'] as String;
    final msgInfo = elem['msgInfo'] as Map;
    expect(msgInfo['sendID'], uidA, reason: 'latest msg sent by A');
    expect(msgInfo['recvID'], uidB, reason: 'latest msg to B');
    expect(msgInfo['contentType'], 101, reason: 'text type');

    // 7. pull messages back (seq-based) — verify the sent text arrives
    final maxSeq = elem['msgInfo']['seq'] as int? ?? 1;
    final pulled = await httpPost('/msg/pull_msg_by_seq', {
      'userID': uidA,
      'conversationID': convID,
      'seqList': [maxSeq],
    }, token: tokenA);
    final msgs = (pulled['messages'] ?? []) as List;
    expect(msgs, isNotEmpty, reason: 'pulled messages should contain the sent one');
    final pulledMsg = msgs.first as Map;
    expect(pulledMsg['sendID'], uidA);
    expect(pulledMsg['recvID'], uidB);
    expect(pulledMsg['contentType'], 101, reason: 'text type');

    // 8. unread for B
    final convsB = await httpPost('/conversation/get_sorted_conversation_list', {'userID': uidB}, token: tokenB);
    final elemB = ((convsB['conversationElems'] ?? []) as List).first as Map;
    final convBID = elemB['conversationID'] as String;
    final unreadB = elemB['unreadCount'] ?? 0;
    expect(unreadB, greaterThanOrEqualTo(1), reason: 'B should have unread from A');

    // 9. B marks read → unread 0
    await httpPost('/msg/mark_msgs_as_read',
        {'conversationID': convBID, 'seqs': [maxSeq]},
        token: tokenB);
    final convsB2 = await httpPost('/conversation/get_sorted_conversation_list', {'userID': uidB}, token: tokenB);
    final elemB2 = (((convsB2['conversationElems'] ?? []) as List).first as Map);
    expect(elemB2['unreadCount'], 0, reason: 'unread cleared after mark-as-read');

    // cleanup
    if (loggedIn) {
      await OpenIM.iMManager.logout();
    }
  });
}
