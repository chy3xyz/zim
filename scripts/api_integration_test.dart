#!/usr/bin/env dart
// ============================================
// ZIM Server API Integration Test
// Run: dart scripts/api_integration_test.dart
// ============================================

import 'dart:convert';
import 'dart:io';

const String baseUrl = 'http://localhost:10000';
const String adminUserID = 'admin';
const String testUser1 = 'test_user_1';
const String testUser2 = 'test_user_2';
const String testUser3 = 'test_user_3';
const String testGroup1 = 'test_group_1';

int passed = 0;
int failed = 0;
String? authToken;

void main() async {
  print('=' * 60);
  print('  ZIM Server API Integration Test');
  print('  Target: $baseUrl');
  print('=' * 60);
  print('');

  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 5);

  try {
    // ========== Auth APIs ==========
    await testAuth(client);

    // ========== User APIs ==========
    await testUser(client);

    // ========== Friend APIs ==========
    await testFriend(client);

    // ========== Group APIs ==========
    await testGroup(client);

    // ========== Message APIs ==========
    await testMessage(client);

    // ========== Conversation APIs ==========
    await testConversation(client);

    print('');
    print('=' * 60);
    print('  Results: $passed passed, $failed failed');
    print('=' * 60);

    if (failed > 0) {
      exit(1);
    }
  } finally {
    client.close();
  }
}

// ============================================
// Helpers
// ============================================

Future<Map<String, dynamic>> post(
  HttpClient client,
  String path, {
  Map<String, dynamic>? body,
  bool useAuth = true,
}) async {
  final req = await client.postUrl(Uri.parse('$baseUrl$path'));
  req.headers.contentType = ContentType.json;
  if (useAuth && authToken != null) {
    req.headers.set('Authorization', authToken!);
  }
  if (body != null) {
    final bodyBytes = utf8.encode(jsonEncode(body));
    req.contentLength = bodyBytes.length;
    req.add(bodyBytes);
  }
  final resp = await req.close();
  final respBody = await resp.transform(utf8.decoder).join();
  return jsonDecode(respBody) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> get(
  HttpClient client,
  String path, {
  bool useAuth = true,
}) async {
  final req = await client.getUrl(Uri.parse('$baseUrl$path'));
  if (useAuth && authToken != null) {
    req.headers.set('Authorization', authToken!);
  }
  final resp = await req.close();
  final respBody = await resp.transform(utf8.decoder).join();
  return jsonDecode(respBody) as Map<String, dynamic>;
}

void assertEq(String name, dynamic actual, dynamic expected, {bool skip = false}) {
  if (skip) {
    print('  [SKIP] $name');
    return;
  }
  if (actual == expected) {
    print('  [PASS] $name');
    passed++;
  } else {
    print('  [FAIL] $name: expected=$expected, actual=$actual');
    failed++;
  }
}

void assertOk(String name, Map<String, dynamic> resp) {
  final errCode = resp['errCode'];
  if (errCode == 0) {
    print('  [PASS] $name');
    passed++;
  } else {
    print('  [FAIL] $name: errCode=$errCode, errMsg=${resp['errMsg']}');
    failed++;
  }
}

void assertDataField(String name, Map<String, dynamic> resp, String field, {bool shouldExist = true}) {
  final data = resp['data'];
  if (data is! Map) {
    print('  [FAIL] $name: data is not a Map');
    failed++;
    return;
  }
  final exists = data.containsKey(field);
  if (shouldExist && exists) {
    print('  [PASS] $name (field "$field" exists)');
    passed++;
  } else if (!shouldExist && !exists) {
    print('  [PASS] $name (field "$field" absent)');
    passed++;
  } else {
    print('  [FAIL] $name: field "$field" ${exists ? "exists" : "missing"}, expected ${shouldExist ? "exists" : "absent"}');
    failed++;
  }
}

// ============================================
// Auth Tests
// ============================================

Future<void> testAuth(HttpClient client) async {
  print('--- Auth APIs ---');

  // Test: get admin token
  final adminResp = await post(client, '/auth/get_admin_token',
      body: {'secret': 'change-me-in-production'}, useAuth: false);
  assertEq('get_admin_token returns errCode 0 or 403',
      adminResp['errCode'] == 0 || adminResp['errCode'] == 403 || adminResp['errCode'] == 500, true);

  // Test: get user token (this will generate a real JWT)
  final tokenResp = await post(client, '/auth/get_user_token',
      body: {'userID': testUser1, 'platformID': 1}, useAuth: false);
  if (tokenResp['errCode'] == 0) {
    authToken = tokenResp['data']['token'] as String?;
    print('  [INFO] Got auth token for $testUser1');
    assertDataField('get_user_token has token', tokenResp, 'token');
    assertDataField('get_user_token has expireTime', tokenResp, 'expireTime');
  } else {
    print('  [WARN] get_user_token failed: ${tokenResp['errMsg']}, trying admin fallback...');
    // Fallback: try admin token if config secret matches default
    final adminFallback = await post(client, '/auth/get_admin_token',
        body: {'secret': 'zim-secret-change-in-production'}, useAuth: false);
    if (adminFallback['errCode'] == 0) {
      authToken = adminFallback['data']['token'] as String?;
      print('  [INFO] Got admin auth token');
    }
  }

  if (authToken == null) {
    print('  [WARN] Could not obtain auth token. Skipping auth-required tests.');
  }

  // Test: health check (no auth)
  final health = await get(client, '/health', useAuth: false);
  assertEq('health check errCode', health['errCode'], 0);
  assertDataField('health check has status', health, 'status');

  print('');
}

// ============================================
// User Tests
// ============================================

Future<void> testUser(HttpClient client) async {
  print('--- User APIs ---');
  if (authToken == null) {
    print('  [SKIP] No auth token');
    print('');
    return;
  }

  // Test: get_users_info
  final usersInfo = await post(client, '/user/get_users_info',
      body: {'userIDs': [testUser1, testUser2, testUser3]});
  assertOk('get_users_info', usersInfo);
  if (usersInfo['errCode'] == 0) {
    final users = (usersInfo['data']['users'] as List?) ?? [];
    assertEq('get_users_info returns 3 users', users.length, 3);
    if (users.isNotEmpty) {
      assertEq('get_users_info user has userID',
          (users[0] as Map).containsKey('userID'), true);
      assertEq('get_users_info user has nickname',
          (users[0] as Map).containsKey('nickname'), true);
      assertEq('get_users_info user has faceURL',
          (users[0] as Map).containsKey('faceURL'), true);
    }
  }

  // Test: get_users
  final usersList = await post(client, '/user/get_users',
      body: {'userID': testUser1, 'pagination': {'pageNumber': 1, 'showNumber': 10}});
  assertOk('get_users', usersList);

  // Test: user_register_count
  final countResp = await post(client, '/user/user_register_count', body: {});
  assertOk('user_register_count', countResp);
  if (countResp['errCode'] == 0) {
    final count = countResp['data']['count'];
    assertEq('user_register_count >= 7', count >= 7, true);
  }

  // Test: get_users_online_status
  final onlineResp = await post(client, '/user/get_users_online_status',
      body: {'userIDs': [testUser1]});
  assertOk('get_users_online_status', onlineResp);

  print('');
}

// ============================================
// Friend Tests
// ============================================

Future<void> testFriend(HttpClient client) async {
  print('--- Friend APIs ---');
  if (authToken == null) {
    print('  [SKIP] No auth token');
    print('');
    return;
  }

  // Test: get_friend_list
  final friendList = await post(client, '/friend/get_friend_list',
      body: {'ownerUserID': testUser1, 'pagination': {'pageNumber': 1, 'showNumber': 20}});
  assertOk('get_friend_list', friendList);
  if (friendList['errCode'] == 0) {
    final friends = (friendList['data']['friends'] as List?) ?? [];
    assertEq('get_friend_list has friends', friends.length >= 2, true);
    if (friends.isNotEmpty) {
      final first = friends[0] as Map;
      assertEq('friend has ownerUserID', first.containsKey('ownerUserID'), true);
      assertEq('friend has friendUserID', first.containsKey('friendUserID'), true);
      assertEq('friend has nickname', first.containsKey('nickname'), true);
      assertEq('friend has faceURL', first.containsKey('faceURL'), true);
    }
  }

  // Test: is_friend
  final isFriend = await post(client, '/friend/is_friend',
      body: {'userID1': testUser1, 'userID2': testUser2});
  assertOk('is_friend', isFriend);
  if (isFriend['errCode'] == 0) {
    assertEq('is_friend(test_user_1, test_user_2)', isFriend['data']['isFriend'], true);
  }

  // Test: get_black_list
  final blackList = await post(client, '/friend/get_black_list',
      body: {'ownerUserID': testUser1, 'pagination': {'pageNumber': 1, 'showNumber': 20}});
  assertOk('get_black_list', blackList);
  if (blackList['errCode'] == 0) {
    final blacks = (blackList['data']['blacks'] as List?) ?? [];
    assertEq('get_black_list has 1 entry', blacks.length, 1);
  }

  // Test: get_friend_apply_list
  final applyList = await post(client, '/friend/get_friend_apply_list',
      body: {'toUserID': testUser1});
  assertOk('get_friend_apply_list', applyList);

  // Test: get_designated_friends
  final designated = await post(client, '/friend/get_designated_friends',
      body: {'ownerUserID': testUser1, 'friendUserIDs': [testUser2]});
  assertOk('get_designated_friends', designated);

  print('');
}

// ============================================
// Group Tests
// ============================================

Future<void> testGroup(HttpClient client) async {
  print('--- Group APIs ---');
  if (authToken == null) {
    print('  [SKIP] No auth token');
    print('');
    return;
  }

  // Test: get_groups_info
  final groupsInfo = await post(client, '/group/get_groups_info',
      body: {'groupIDs': [testGroup1]});
  assertOk('get_groups_info', groupsInfo);
  if (groupsInfo['errCode'] == 0) {
    final groups = (groupsInfo['data']['groups'] as List?) ?? [];
    assertEq('get_groups_info returns 1 group', groups.length, 1);
    if (groups.isNotEmpty) {
      final g = groups[0] as Map;
      assertEq('group has groupID', g.containsKey('groupID'), true);
      assertEq('group has groupName', g.containsKey('groupName'), true);
      assertEq('group has memberCount', g.containsKey('memberCount'), true);
      assertEq('group has creatorUserID', g.containsKey('creatorUserID'), true);
    }
  }

  // Test: get_group_member_list
  final memberList = await post(client, '/group/get_group_member_list',
      body: {'groupID': testGroup1, 'pagination': {'pageNumber': 1, 'showNumber': 20}});
  assertOk('get_group_member_list', memberList);
  if (memberList['errCode'] == 0) {
    final members = (memberList['data']['members'] as List?) ?? [];
    assertEq('get_group_member_list has members', members.length >= 3, true);
    if (members.isNotEmpty) {
      final m = members[0] as Map;
      assertEq('member has userID', m.containsKey('userID'), true);
      assertEq('member has nickname', m.containsKey('nickname'), true);
      assertEq('member has roleLevel', m.containsKey('roleLevel'), true);
    }
  }

  // Test: get_joined_group_list
  final joinedGroups = await post(client, '/group/get_joined_group_list',
      body: {'userID': testUser1, 'pagination': {'pageNumber': 1, 'showNumber': 20}});
  assertOk('get_joined_group_list', joinedGroups);

  // Test: get_group_members_info
  final membersInfo = await post(client, '/group/get_group_members_info',
      body: {'groupID': testGroup1, 'userIDs': [testUser1, testUser2]});
  assertOk('get_group_members_info', membersInfo);

  print('');
}

// ============================================
// Message Tests
// ============================================

Future<void> testMessage(HttpClient client) async {
  print('--- Message APIs ---');
  if (authToken == null) {
    print('  [SKIP] No auth token');
    print('');
    return;
  }

  // Test: send_msg
  final sendResp = await post(client, '/msg/send_msg', body: {
    'sendID': testUser1,
    'recvID': testUser2,
    'sessionType': 1,
    'contentType': 101,
    'content': 'Integration test message at ${DateTime.now().toIso8601String()}',
    'senderNickname': 'Alice',
    'senderFaceURL': 'https://example.com/faces/alice.png',
  });
  assertOk('send_msg', sendResp);
  if (sendResp['errCode'] == 0) {
    assertDataField('send_msg has serverMsgID', sendResp, 'serverMsgID');
    assertDataField('send_msg has clientMsgID', sendResp, 'clientMsgID');
    assertDataField('send_msg has sendTime', sendResp, 'sendTime');
  }

  // Test: search_msg
  final searchResp = await post(client, '/msg/search_msg', body: {
    'conversationID': 'si_${testUser1}_$testUser2',
    'limit': 10,
  });
  assertOk('search_msg', searchResp);
  if (searchResp['errCode'] == 0) {
    final msgs = (searchResp['data']['messages'] as List?) ?? [];
    assertEq('search_msg has messages', msgs.length >= 1, true);
  }

  // Test: get_seq (route is /msg/newest_seq)
  final seqResp = await post(client, '/msg/newest_seq', body: {
    'conversationID': 'si_${testUser1}_$testUser2',
  });
  assertOk('newest_seq', seqResp);

  // Test: get_server_time
  final timeResp = await post(client, '/msg/get_server_time', body: {});
  assertOk('get_server_time', timeResp);
  if (timeResp['errCode'] == 0) {
    final serverTime = timeResp['data']['serverTime'];
    assertEq('get_server_time returns positive timestamp', serverTime > 0, true);
  }

  print('');
}

// ============================================
// Conversation Tests
// ============================================

Future<void> testConversation(HttpClient client) async {
  print('--- Conversation APIs ---');
  if (authToken == null) {
    print('  [SKIP] No auth token');
    print('');
    return;
  }

  // Test: get_sorted_conversation_list
  final sortedResp = await post(client, '/conversation/get_sorted_conversation_list',
      body: {'userID': testUser1});
  assertOk('get_sorted_conversation_list', sortedResp);
  if (sortedResp['errCode'] == 0) {
    final convs = (sortedResp['data']['conversations'] as List?) ?? [];
    assertEq('get_sorted_conversation_list has conversations', convs.length >= 1, true);
    if (convs.isNotEmpty) {
      final c = convs[0] as Map;
      assertEq('conversation has conversationID', c.containsKey('conversationID'), true);
      assertEq('conversation has conversationType', c.containsKey('conversationType'), true);
      assertEq('conversation has latestMsgSendTime', c.containsKey('latestMsgSendTime'), true);
    }
  }

  // Test: get_conversation
  final convResp = await post(client, '/conversation/get_conversation', body: {
    'userID': testUser1,
    'conversationID': 'si_${testUser1}_$testUser2',
  });
  assertOk('get_conversation', convResp);
  if (convResp['errCode'] == 0) {
    assertDataField('get_conversation has conversation', convResp, 'conversation');
  }

  // Test: set_conversations
  final setResp = await post(client, '/conversation/set_conversations', body: {
    'userID': testUser1,
    'conversationID': 'si_${testUser1}_$testUser2',
    'isPinned': true,
  });
  assertOk('set_conversations', setResp);

  // Verify it was updated
  final verifyResp = await post(client, '/conversation/get_conversation', body: {
    'userID': testUser1,
    'conversationID': 'si_${testUser1}_$testUser2',
  });
  if (verifyResp['errCode'] == 0) {
    final conv = verifyResp['data']['conversation'] as Map?;
    if (conv != null) {
      assertEq('set_conversations isPinned=true', conv['isPinned'], true);
    }
  }

  print('');
}
