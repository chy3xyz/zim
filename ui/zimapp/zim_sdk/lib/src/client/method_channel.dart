import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../enum/login_status.dart';
import '../enum/message_status.dart';
import '../enum/message_type.dart';
import '../models/conversation_info.dart';
import '../models/group_info.dart';
import '../models/init_config.dart';
import '../models/message.dart';
import '../models/notification_info.dart';
import '../models/search_info.dart';
import '../models/update_req.dart';
import '../models/user_info.dart';
import '../utils.dart';
import 'http_client.dart';
import 'ws_client.dart';
import '../db/local_db.dart';

/// Method-channel-style adapter that routes native SDK calls to zim HTTP APIs.
class ZimSdkMethodChannel {
  String? _apiUrl;
  String? _wsUrl;
  String? _dataDir;
  String? _token;
  String? _userID;
  int? _platformID;
  bool _initialized = false;
  bool _logined = false;

  final _localDB = ZimLocalDB();
  final _wsClient = ZimWsClient();

  StreamSubscription? _wsSub;

  Future<T?> invokeMethod<T>(String method, Map<String, dynamic> arguments) async {
    final manager = arguments['ManagerName'] as String? ?? '';
    final operationID = arguments['operationID'] as String?;
    final args = Map<String, dynamic>.from(arguments)..remove('ManagerName')..remove('operationID');

    try {
      switch (manager) {
        case 'imManager':
          return await _handleIMManager(method, args, operationID) as T?;
        case 'conversationManager':
          return await _handleConversationManager(method, args, operationID) as T?;
        case 'messageManager':
          return await _handleMessageManager(method, args, operationID) as T?;
        case 'friendshipManager':
          return await _handleFriendshipManager(method, args, operationID) as T?;
        case 'groupManager':
          return await _handleGroupManager(method, args, operationID) as T?;
        case 'userManager':
          return await _handleUserManager(method, args, operationID) as T?;
        default:
          throw UnsupportedError('Unknown manager: $manager, method: $method');
      }
    } catch (e, s) {
      log('ZimSdkMethodChannel error: $e\n$s');
      rethrow;
    }
  }

  // ─── IMManager ───
  Future<dynamic> _handleIMManager(String method, Map<String, dynamic> args, String? operationID) async {
    switch (method) {
      case 'initSDK':
        _apiUrl = args['apiAddr'] as String?;
        _wsUrl = args['wsAddr'] as String?;
        _dataDir = args['dataDir'] as String?;
        _platformID = args['platformID'] as int?;
        if (_apiUrl != null) {
          httpClient.init(baseUrl: _apiUrl!);
        }
        await _localDB.init();
        _initialized = true;
        return true;

      case 'unInitSDK':
        _wsClient.disconnect();
        _wsSub?.cancel();
        await _localDB.close();
        _initialized = false;
        return null;

      case 'login':
        _userID = args['userID'] as String?;
        _token = args['token'] as String?;
        if (_token != null) {
          httpClient.setToken(_token);
        }
        // Connect WebSocket
        if (_wsUrl != null && _userID != null && _token != null) {
          _wsClient.init(
            wsUrl: _wsUrl!,
            token: _token!,
            userID: _userID!,
          );
          await _wsClient.connect();
        }
        _logined = true;
        // Fetch self user info
        try {
          final info = await _post('/user/get_users_info', {
            'userIDs': [_userID],
          });
          final list = info?['usersInfo'] as List<dynamic>? ?? info?['users'] as List<dynamic>? ?? [];
          if (list.isNotEmpty) {
            return UserInfo.fromJson(list.first as Map<String, dynamic>);
          }
        } catch (_) {}
        return UserInfo(userID: _userID);

      case 'logout':
        _wsClient.disconnect();
        _wsSub?.cancel();
        _token = null;
        _logined = false;
        return null;

      case 'getLoginStatus':
        if (!_initialized) return LoginStatus.logout;
        if (_logined) return LoginStatus.logged;
        // Not logged in yet — report logout, NOT logging: the login flow
        // skips the real login call when status is logging/logged, which
        // would leave the token unset (401 on subsequent authed requests).
        return LoginStatus.logout;

      case 'uploadFile':
      case 'cancelUpload':
      case 'updateFcmToken':
      case 'uploadLogs':
      case 'logs':
      case 'setListenerForService':
        // Stubs - not critical for basic functionality
        return null;

      default:
        throw UnsupportedError('IMManager method not implemented: $method');
    }
  }

  // ─── ConversationManager ───
  Future<dynamic> _handleConversationManager(String method, Map<String, dynamic> args, String? operationID) async {
    switch (method) {
      case 'setConversationListener':
        return null;

      case 'getAllConversationList':
        try {
          final resp = await _post('/conversation/get_sorted_conversation_list', {});
          final list = resp?['conversationElems'] as List<dynamic>? ?? [];
          final convs = list.map((e) {
            final c = e['conversation'] as Map<String, dynamic>? ?? {};
            return ConversationInfo.fromJson(c);
          }).toList();
          // Cache locally
          await _localDB.insertConversations(convs.map((c) => c.toJson()).toList());
          return convs;
        } catch (_) {
          // Fallback to local cache
          final local = await _localDB.getConversations();
          return local.map((m) => ConversationInfo.fromJson(m)).toList();
        }

      case 'getOneConversation':
        final sourceID = args['sourceID'] as String?;
        final sessionType = args['sessionType'] as int?;
        if (sourceID == null || sessionType == null) return null;
        try {
          final convID = _conversationID(sourceID, sessionType);
          final resp = await _post('/conversation/get_conversation', {'conversationID': convID});
          final data = resp?['conversation'] as Map<String, dynamic>?;
          if (data != null) return ConversationInfo.fromJson(data);
        } catch (_) {}
        // Fallback to local
        final local = await _localDB.getConversation(_conversationID(sourceID, sessionType));
        return local != null ? ConversationInfo.fromJson(local) : null;

      case 'getMultipleConversation':
        final list = args['conversationIDList'] as List<dynamic>? ?? [];
        try {
          final resp = await _post('/conversation/get_conversations', {'conversationIDs': list});
          final data = resp?['conversations'] as List<dynamic>? ?? [];
          return data.map((e) => ConversationInfo.fromJson(e as Map<String, dynamic>)).toList();
        } catch (_) {
          final result = <ConversationInfo>[];
          for (final id in list) {
            final local = await _localDB.getConversation(id as String);
            if (local != null) result.add(ConversationInfo.fromJson(local));
          }
          return result;
        }

      case 'setConversation':
        final req = args['req'] as Map<String, dynamic>?;
        if (req == null) return null;
        try {
          await _post('/conversation/set_conversations', req);
        } catch (_) {}
        // Update local cache
        final convID = req['conversationID'] as String?;
        if (convID != null) {
          final local = await _localDB.getConversation(convID);
          if (local != null) {
            local.addAll(req);
            await _localDB.insertConversation(local);
          }
        }
        return null;

      case 'setConversationDraft':
        return _handleConversationManager('setConversation', {
          'req': {
            'conversationID': args['conversationID'],
            'draftText': args['draftText'],
            'draftTextTime': DateTime.now().millisecondsSinceEpoch,
          }
        }, operationID);

      case 'pinConversation':
        return _handleConversationManager('setConversation', {
          'req': {
            'conversationID': args['conversationID'],
            'isPinned': args['isPinned'],
          }
        }, operationID);

      case 'hideConversation':
        // Mark as hidden in local DB
        final convID = args['conversationID'] as String?;
        if (convID != null) {
          await _localDB.deleteConversation(convID);
        }
        return null;

      case 'hideAllConversations':
        await _localDB.clearAllConversations();
        return null;

      case 'getTotalUnreadMsgCount':
        try {
          final resp = await _post('/conversation/get_sorted_conversation_list', {});
          final list = resp?['conversationElems'] as List<dynamic>? ?? [];
          int total = 0;
          for (final e in list) {
            final c = e['conversation'] as Map<String, dynamic>?;
            if (c != null) total += (c['unreadCount'] as int? ?? 0);
          }
          return total;
        } catch (_) {
          final local = await _localDB.getConversations();
          int total = 0;
          for (final m in local) {
            total += (m['unread_count'] as int? ?? 0);
          }
          return total;
        }

      case 'setConversationRecvMessageOpt':
        return _handleConversationManager('setConversation', {
          'req': {
            'conversationID': args['conversationID'],
            'recvMsgOpt': args['opt'],
          }
        }, operationID);

      case 'deleteConversationAndDeleteAllMsg':
        final convID = args['conversationID'] as String?;
        if (convID != null) {
          await _localDB.deleteConversation(convID);
          await _localDB.deleteMessagesByConversation(convID, '');
        }
        return null;

      case 'clearConversationAndDeleteAllMsg':
        final convID = args['conversationID'] as String?;
        if (convID != null) {
          await _localDB.deleteMessagesByConversation(convID, '');
          final local = await _localDB.getConversation(convID);
          if (local != null) {
            local['latest_msg'] = null;
            local['latest_msg_send_time'] = 0;
            local['unread_count'] = 0;
            await _localDB.insertConversation(local);
          }
        }
        return null;

      case 'deleteAllConversationFromLocal':
        await _localDB.clearAllConversations();
        return null;

      case 'resetConversationGroupAtType':
        return _handleConversationManager('setConversation', {
          'req': {
            'conversationID': args['conversationID'],
            'groupAtType': 0,
          }
        }, operationID);

      case 'getAtAllTag':
        return '@All';

      case 'markConversationMessageAsRead':
        final convID = args['conversationID'] as String?;
        if (convID != null) {
          try {
            await _post('/msg/mark_conversation_as_read', {'conversationID': convID});
          } catch (_) {}
          final local = await _localDB.getConversation(convID);
          if (local != null) {
            local['unread_count'] = 0;
            local['has_read_seq'] = local['max_seq'];
            await _localDB.insertConversation(local);
          }
        }
        return null;

      case 'setConversationBurnDuration':
      case 'setConversationIsMsgDestruct':
      case 'setConversationMsgDestructTime':
      case 'setConversationEx':
      case 'changeInputStates':
        return _handleConversationManager('setConversation', {
          'req': args,
        }, operationID);

      default:
        throw UnsupportedError('ConversationManager method not implemented: $method');
    }
  }

  // ─── MessageManager ───
  Future<dynamic> _handleMessageManager(String method, Map<String, dynamic> args, String? operationID) async {
    switch (method) {
      case 'setAdvancedMsgListener':
        return null;

      case 'setMsgSendProgressListener':
        return null;

      case 'setCustomBusinessListener':
        return null;

      case 'setMessageKvInfoListener':
        return null;

      case 'sendMessage':
        final msg = args['message'] as Map<String, dynamic>?;
        if (msg == null) throw ArgumentError('message is required');
        final recvID = args['recvID'] as String? ?? '';
        final groupID = args['groupID'] as String? ?? '';

        // Build send_msg request
        final req = {
          'sendID': _userID,
          'recvID': recvID,
          if (groupID.isNotEmpty) 'groupID': groupID,
          'contentType': msg['contentType'] ?? 101,
          'content': msg['content']?['content'] ?? msg['content'] ?? '',
          'clientMsgID': msg['clientMsgID'] ?? const Uuid().v4(),
          'senderPlatformID': _platformID ?? 1,
          'sessionType': args['groupID'] != null && (args['groupID'] as String).isNotEmpty ? 2 : 1,
        };

        try {
          final resp = await _post('/msg/send_msg', req);
          final data = resp?['message'] as Map<String, dynamic>? ?? resp ?? {};
          final result = Message.fromJson(data);
          // Cache locally
          await _localDB.insertMessage(result.toJson());
          return result;
        } catch (e) {
          // Store as sending locally
          final localMsg = Message.fromJson(msg);
          localMsg.status = MessageStatus.sending;
          await _localDB.insertMessage(localMsg.toJson());
          rethrow;
        }

      case 'getHistoryMessageList':
        final req = args['req'] as Map<String, dynamic>?;
        if (req == null) return <Message>[];
        final convID = req['conversationID'] as String?;
        final userID = req['userID'] as String?;
        final groupID = req['groupID'] as String?;
        final count = req['count'] as int? ?? 20;
        final startClientMsgID = req['startClientMsgID'] as String?;

        try {
          final body = <String, dynamic>{};
          if (convID != null) body['conversationID'] = convID;
          if (userID != null) body['userID'] = userID;
          if (groupID != null) body['groupID'] = groupID;
          body['count'] = count;
          if (startClientMsgID != null) body['startClientMsgID'] = startClientMsgID;

          final resp = await _post('/msg/search_msg', body);
          final list = resp?['messages'] as List<dynamic>? ?? [];
          final msgs = list.map((e) => Message.fromJson(e as Map<String, dynamic>)).toList();
          await _localDB.insertMessages(msgs.map((m) => m.toJson()).toList());
          return msgs;
        } catch (_) {
          // Fallback to local
          final local = await _localDB.getMessages(
            sendID: userID,
            recvID: userID,
            limit: count,
          );
          return local.map((m) => Message.fromJson(m)).toList();
        }

      case 'deleteMessageFromLocalStorage':
        final clientMsgID = args['clientMsgID'] as String?;
        if (clientMsgID != null) {
          await _localDB.deleteMessage(clientMsgID);
        }
        return null;

      case 'deleteMessageFromLocalAndSvr':
        final clientMsgID = args['clientMsgID'] as String?;
        if (clientMsgID != null) {
          try {
            await _post('/msg/delete_msgs', {'clientMsgIDs': [clientMsgID]});
          } catch (_) {}
          await _localDB.deleteMessage(clientMsgID);
        }
        return null;

      case 'deleteAllMsgFromLocal':
        await _localDB.db.delete('messages');
        return null;

      case 'deleteAllMsgFromLocalAndSvr':
        try {
          await _post('/msg/user_clear_all_msg', {});
        } catch (_) {}
        await _localDB.db.delete('messages');
        return null;

      case 'revokeMessage':
        final clientMsgID = args['clientMsgID'] as String?;
        if (clientMsgID != null) {
          try {
            await _post('/msg/revoke_msg', {'clientMsgID': clientMsgID});
          } catch (_) {}
        }
        return null;

      case 'insertSingleMessageToLocalStorage':
      case 'insertGroupMessageToLocalStorage':
        final msg = args['message'] as Map<String, dynamic>?;
        if (msg != null) {
          await _localDB.insertMessage(Message.fromJson(msg).toJson());
        }
        return null;

      case 'searchLocalMessages':
        final req = args['req'] as Map<String, dynamic>?;
        if (req == null) return <Message>[];
        final keyword = req['keyword'] as String? ?? '';
        final count = req['count'] as int? ?? 20;
        final local = await _localDB.getMessages(limit: count);
        // Simple keyword filter
        final filtered = local.where((m) {
          final content = m['content'] as String? ?? '';
          return content.toLowerCase().contains(keyword.toLowerCase());
        }).toList();
        return filtered.map((m) => Message.fromJson(m)).toList();

      case 'markC2CMessageAsRead':
        final userID = args['userID'] as String?;
        final msgIDs = args['msgIDList'] as List<dynamic>?;
        if (userID != null && msgIDs != null && msgIDs.isNotEmpty) {
          try {
            await _post('/msg/mark_user_message_read', {
              'userID': userID,
              'msgIDs': msgIDs,
            });
          } catch (_) {}
        }
        return null;

      case 'markGroupMessageAsRead':
        final groupID = args['groupID'] as String?;
        final msgIDs = args['msgIDList'] as List<dynamic>?;
        if (groupID != null && msgIDs != null && msgIDs.isNotEmpty) {
          try {
            await _post('/msg/mark_group_message_read', {
              'groupID': groupID,
              'msgIDs': msgIDs,
            });
          } catch (_) {}
        }
        return null;

      case 'typingStatusUpdate':
        return null;

      case 'createTextMessage':
        final text = args['text'] as String? ?? '';
        return Message(
          clientMsgID: const Uuid().v4(),
          contentType: MessageType.text,
          textElem: TextElem(content: text),
          sendID: _userID,
          createTime: DateTime.now().millisecondsSinceEpoch,
          status: MessageStatus.sending,
        );

      case 'createTextAtMessage':
        return Message(
          clientMsgID: const Uuid().v4(),
          contentType: MessageType.atText,
          textElem: TextElem(content: args['text'] ?? ''),
          sendID: _userID,
          createTime: DateTime.now().millisecondsSinceEpoch,
          status: MessageStatus.sending,
        );

      case 'createImageMessage':
      case 'createImageMessageByURL':
        return Message(
          clientMsgID: const Uuid().v4(),
          contentType: MessageType.picture,
          pictureElem: PictureElem.fromJson(args),
          sendID: _userID,
          createTime: DateTime.now().millisecondsSinceEpoch,
          status: MessageStatus.sending,
        );

      case 'createVoiceMessage':
      case 'createVoiceMessageByURL':
        return Message(
          clientMsgID: const Uuid().v4(),
          contentType: MessageType.voice,
          soundElem: SoundElem.fromJson(args),
          sendID: _userID,
          createTime: DateTime.now().millisecondsSinceEpoch,
          status: MessageStatus.sending,
        );

      case 'createVideoMessage':
      case 'createVideoMessageByURL':
        return Message(
          clientMsgID: const Uuid().v4(),
          contentType: MessageType.video,
          videoElem: VideoElem.fromJson(args),
          sendID: _userID,
          createTime: DateTime.now().millisecondsSinceEpoch,
          status: MessageStatus.sending,
        );

      case 'createFileMessage':
      case 'createFileMessageByURL':
        return Message(
          clientMsgID: const Uuid().v4(),
          contentType: MessageType.file,
          fileElem: FileElem.fromJson(args),
          sendID: _userID,
          createTime: DateTime.now().millisecondsSinceEpoch,
          status: MessageStatus.sending,
        );

      case 'createMergerMessage':
        return Message(
          clientMsgID: const Uuid().v4(),
          contentType: MessageType.merger,
          mergeElem: MergeElem.fromJson(args),
          sendID: _userID,
          createTime: DateTime.now().millisecondsSinceEpoch,
          status: MessageStatus.sending,
        );

      case 'createForwardMessage':
        return Message(
          clientMsgID: const Uuid().v4(),
          contentType: MessageType.merger,
          mergeElem: MergeElem.fromJson(args),
          sendID: _userID,
          createTime: DateTime.now().millisecondsSinceEpoch,
          status: MessageStatus.sending,
        );

      case 'createLocationMessage':
      case 'createLocationMessageByURL':
        return Message(
          clientMsgID: const Uuid().v4(),
          contentType: MessageType.location,
          locationElem: LocationElem.fromJson(args),
          sendID: _userID,
          createTime: DateTime.now().millisecondsSinceEpoch,
          status: MessageStatus.sending,
        );

      case 'createCustomMessage':
        return Message(
          clientMsgID: const Uuid().v4(),
          contentType: MessageType.custom,
          customElem: CustomElem.fromJson(args),
          sendID: _userID,
          createTime: DateTime.now().millisecondsSinceEpoch,
          status: MessageStatus.sending,
        );

      case 'createQuoteMessage':
        return Message(
          clientMsgID: const Uuid().v4(),
          contentType: MessageType.quote,
          quoteElem: QuoteElem.fromJson(args),
          sendID: _userID,
          createTime: DateTime.now().millisecondsSinceEpoch,
          status: MessageStatus.sending,
        );

      case 'createCardMessage':
        return Message(
          clientMsgID: const Uuid().v4(),
          contentType: MessageType.card,
          cardElem: CardElem.fromJson(args),
          sendID: _userID,
          createTime: DateTime.now().millisecondsSinceEpoch,
          status: MessageStatus.sending,
        );

      case 'createFaceMessage':
        return Message(
          clientMsgID: const Uuid().v4(),
          contentType: MessageType.customFace,
          faceElem: FaceElem.fromJson(args),
          sendID: _userID,
          createTime: DateTime.now().millisecondsSinceEpoch,
          status: MessageStatus.sending,
        );

      case 'newestSeq':
        try {
          final resp = await _post('/msg/newest_seq', {});
          return resp?['seq'] as int? ?? 0;
        } catch (_) {
          return 0;
        }

      case 'getServerTime':
        try {
          final resp = await _post('/msg/get_server_time', {});
          return resp?['serverTime'] as int? ?? DateTime.now().millisecondsSinceEpoch;
        } catch (_) {
          return DateTime.now().millisecondsSinceEpoch;
        }

      case 'setMessageLocalEx':
      case 'setMessageReactionExtensions':
      case 'deleteMessageReactionExtensions':
      case 'getMessageListReactionExtensions':
      case 'addMessageReactionExtensions':
      case 'getMessageListSomeReactionExtensions':
      case 'setAppBadge':
        return null;

      default:
        throw UnsupportedError('MessageManager method not implemented: $method');
    }
  }

  // ─── FriendshipManager ───
  Future<dynamic> _handleFriendshipManager(String method, Map<String, dynamic> args, String? operationID) async {
    switch (method) {
      case 'setFriendListener':
        return null;

      case 'getFriendsInfo':
        final userIDs = args['userIDList'] as List<dynamic>? ?? [];
        if (userIDs.isEmpty) return <FriendInfo>[];
        try {
          final resp = await _post('/friend/get_designated_friends', {'userIDs': userIDs});
          final list = resp?['friendsInfo'] as List<dynamic>? ?? resp?['friends'] as List<dynamic>? ?? [];
          final friends = list.map((e) => FriendInfo.fromJson(e as Map<String, dynamic>)).toList();
          await _localDB.insertFriends(friends.map((f) => f.toJson()).toList());
          return friends;
        } catch (_) {
          final local = await _localDB.getFriends();
          return local.where((m) => userIDs.contains(m['user_id'])).map((m) => FriendInfo.fromJson(m)).toList();
        }

      case 'getFriendList':
        try {
          final resp = await _post('/friend/get_friend_list', {});
          final list = resp?['friendsInfo'] as List<dynamic>? ?? resp?['friends'] as List<dynamic>? ?? [];
          final friends = list.map((e) => FriendInfo.fromJson(e as Map<String, dynamic>)).toList();
          await _localDB.insertFriends(friends.map((f) => f.toJson()).toList());
          return friends;
        } catch (_) {
          final local = await _localDB.getFriends();
          return local.map((m) => FriendInfo.fromJson(m)).toList();
        }

      case 'getFriendListPage':
        final offset = args['offset'] as int? ?? 0;
        final count = args['count'] as int? ?? 20;
        try {
          final resp = await _post('/friend/get_friend_list', {});
          final list = resp?['friendsInfo'] as List<dynamic>? ?? [];
          final friends = list.map((e) => FriendInfo.fromJson(e as Map<String, dynamic>)).toList();
          return friends.skip(offset).take(count).toList();
        } catch (_) {
          final local = await _localDB.getFriends();
          return local.skip(offset).take(count).map((m) => FriendInfo.fromJson(m)).toList();
        }

      case 'addFriend':
        try {
          await _post('/friend/add_friend', {
            'toUserID': args['toUserID'],
            'reqMsg': args['reqMsg'] ?? '',
          });
        } catch (_) {}
        return null;

      case 'acceptFriendApplication':
        try {
          await _post('/friend/add_friend_response', {
            'toUserID': args['toUserID'],
            'handleResult': 1,
            'handleMsg': args['handleMsg'] ?? '',
          });
        } catch (_) {}
        return null;

      case 'refuseFriendApplication':
        try {
          await _post('/friend/add_friend_response', {
            'toUserID': args['toUserID'],
            'handleResult': 0,
            'handleMsg': args['handleMsg'] ?? '',
          });
        } catch (_) {}
        return null;

      case 'deleteFriend':
        final userID = args['friendUserID'] as String?;
        if (userID != null) {
          try {
            await _post('/friend/delete_friend', {'friendUserID': userID});
          } catch (_) {}
          await _localDB.deleteFriend(userID);
        }
        return null;

      case 'setFriendRemark':
        try {
          await _post('/friend/set_friend_remark', {
            'friendUserID': args['friendUserID'],
            'remark': args['remark'] ?? '',
          });
        } catch (_) {}
        return null;

      case 'getFriendApplicationListAsRecipient':
        try {
          final resp = await _post('/friend/get_friend_apply_list', {});
          return resp?['friendRequests'] as List<dynamic>? ?? [];
        } catch (_) {
          return [];
        }

      case 'getFriendApplicationListAsApplicant':
        try {
          final resp = await _post('/friend/get_self_friend_apply_list', {});
          return resp?['friendRequests'] as List<dynamic>? ?? [];
        } catch (_) {
          return [];
        }

      case 'addBlacklist':
        try {
          await _post('/friend/add_black', {'toUserID': args['toUserID']});
        } catch (_) {}
        return null;

      case 'removeBlacklist':
        try {
          await _post('/friend/remove_black', {'toUserID': args['toUserID']});
        } catch (_) {}
        return null;

      case 'getBlacklist':
        try {
          final resp = await _post('/friend/get_black_list', {});
          return resp?['blacksInfo'] as List<dynamic>? ?? [];
        } catch (_) {
          return [];
        }

      case 'checkFriend':
        final userIDs = args['userIDList'] as List<dynamic>? ?? [];
        try {
          final resp = await _post('/friend/is_friend', {'userIDList': userIDs});
          return resp?['result'] as List<dynamic>? ?? [];
        } catch (_) {
          return userIDs.map((_) => {'result': 1}).toList();
        }

      case 'updateFriends':
      case 'deleteFriendRequestsFromBoth':
      case 'refuseFriendApplicationByBoth':
      case 'acceptFriendApplicationByBoth':
      case 'getSpecifiedFriendsInfo':
      case 'getFriendIDList':
      case 'getFullFriendUserIDs':
      case 'getIncrementalFriends':
      case 'getIncrementalBlacks':
      case 'setFriendsEx':
        return null;

      default:
        throw UnsupportedError('FriendshipManager method not implemented: $method');
    }
  }

  // ─── GroupManager ───
  Future<dynamic> _handleGroupManager(String method, Map<String, dynamic> args, String? operationID) async {
    switch (method) {
      case 'setGroupListener':
        return null;

      case 'createGroup':
        try {
          final resp = await _post('/group/create_group', {
            'groupInfo': args['groupInfo'],
            'memberUserIDs': args['memberUserIDList'] ?? [],
            'adminUserIDs': args['adminUserIDList'] ?? [],
            'ownerUserID': _userID,
          });
          return GroupInfo.fromJson(resp?['groupInfo'] as Map<String, dynamic>? ?? {});
        } catch (e) {
          rethrow;
        }

      case 'joinGroup':
        try {
          await _post('/group/join_group', {
            'groupID': args['groupID'],
            'reqMsg': args['reqMsg'] ?? '',
            'joinSource': args['joinSource'] ?? 2,
          });
        } catch (_) {}
        return null;

      case 'quitGroup':
        try {
          await _post('/group/quit_group', {'groupID': args['groupID']});
        } catch (_) {}
        return null;

      case 'dismissGroup':
        try {
          await _post('/group/dismiss_group', {'groupID': args['groupID']});
        } catch (_) {}
        return null;

      case 'getJoinedGroupList':
        try {
          final resp = await _post('/group/get_joined_group_list', {});
          final list = resp?['groupsInfo'] as List<dynamic>? ?? resp?['groups'] as List<dynamic>? ?? [];
          final groups = list.map((e) => GroupInfo.fromJson(e as Map<String, dynamic>)).toList();
          await _localDB.insertGroups(groups.map((g) => g.toJson()).toList());
          return groups;
        } catch (_) {
          final local = await _localDB.getGroups();
          return local.map((m) => GroupInfo.fromJson(m)).toList();
        }

      case 'getGroupsInfo':
        final groupIDs = args['groupIDList'] as List<dynamic>? ?? [];
        if (groupIDs.isEmpty) return <GroupInfo>[];
        try {
          final resp = await _post('/group/get_groups_info', {'groupIDs': groupIDs});
          final list = resp?['groupsInfo'] as List<dynamic>? ?? [];
          return list.map((e) => GroupInfo.fromJson(e as Map<String, dynamic>)).toList();
        } catch (_) {
          final result = <GroupInfo>[];
          for (final id in groupIDs) {
            final local = await _localDB.getGroup(id as String);
            if (local != null) result.add(GroupInfo.fromJson(local));
          }
          return result;
        }

      case 'setGroupInfo':
        try {
          await _post('/group/set_group_info', {
            'groupID': args['groupID'],
            'groupInfo': args['groupInfo'],
          });
        } catch (_) {}
        return null;

      case 'getGroupMemberList':
        try {
          final resp = await _post('/group/get_group_member_list', {
            'groupID': args['groupID'],
            'filter': args['filter'] ?? 0,
            'offset': args['offset'] ?? 0,
            'count': args['count'] ?? 100,
          });
          final list = resp?['members'] as List<dynamic>? ?? [];
          return list.map((e) => GroupMembersInfo.fromJson(e as Map<String, dynamic>)).toList();
        } catch (_) {
          return [];
        }

      case 'getGroupMembersInfo':
        try {
          final resp = await _post('/group/get_group_members_info', {
            'groupID': args['groupID'],
            'userIDs': args['userIDList'] ?? [],
          });
          final list = resp?['members'] as List<dynamic>? ?? [];
          return list.map((e) => GroupMembersInfo.fromJson(e as Map<String, dynamic>)).toList();
        } catch (_) {
          return [];
        }

      case 'kickGroupMember':
        try {
          await _post('/group/kick_group', {
            'groupID': args['groupID'],
            'kickedUserIDs': args['reason'] != null ? [args['reason']] : [],
          });
        } catch (_) {}
        return null;

      case 'transferGroupOwner':
        try {
          await _post('/group/transfer_group', {
            'groupID': args['groupID'],
            'newOwnerUserID': args['newOwnerUserID'],
          });
        } catch (_) {}
        return null;

      case 'inviteUserToGroup':
        try {
          await _post('/group/invite_user_to_group', {
            'groupID': args['groupID'],
            'invitedUserIDs': args['invitedUserIDList'] ?? [],
            'reason': args['reason'] ?? '',
          });
        } catch (_) {}
        return null;

      case 'acceptGroupApplication':
        try {
          await _post('/group/group_application_response', {
            'groupID': args['groupID'],
            'fromUserID': args['fromUserID'],
            'handleResult': 1,
            'handleMsg': args['handleMsg'] ?? '',
          });
        } catch (_) {}
        return null;

      case 'refuseGroupApplication':
        try {
          await _post('/group/group_application_response', {
            'groupID': args['groupID'],
            'fromUserID': args['fromUserID'],
            'handleResult': 0,
            'handleMsg': args['handleMsg'] ?? '',
          });
        } catch (_) {}
        return null;

      case 'isJoinedGroup':
        try {
          final resp = await _post('/group/get_joined_group_list', {});
          final list = resp?['groupsInfo'] as List<dynamic>? ?? [];
          return list.any((g) => g['groupID'] == args['groupID']);
        } catch (_) {
          return false;
        }

      case 'muteGroupMember':
        try {
          await _post('/group/mute_group_member', {
            'groupID': args['groupID'],
            'userID': args['userID'],
            'mutedSeconds': args['mutedSeconds'] ?? 0,
          });
        } catch (_) {}
        return null;

      case 'cancelMuteGroupMember':
        try {
          await _post('/group/cancel_mute_group_member', {
            'groupID': args['groupID'],
            'userID': args['userID'],
          });
        } catch (_) {}
        return null;

      case 'muteGroup':
        try {
          await _post('/group/mute_group', {'groupID': args['groupID']});
        } catch (_) {}
        return null;

      case 'cancelMuteGroup':
        try {
          await _post('/group/cancel_mute_group', {'groupID': args['groupID']});
        } catch (_) {}
        return null;

      case 'setGroupMemberNickname':
      case 'setGroupMemberRoleLevel':
      case 'setGroupMemberInfo':
      case 'setGroupVerification':
      case 'setGroupLookMemberInfo':
      case 'setGroupApplyMemberFriend':
      case 'setGroupInfoEx':
      case 'getGroupApplicationListAsRecipient':
      case 'getGroupApplicationListAsApplicant':
      case 'getUserReqGroupApplicationList':
      case 'getGroupMemberOwnerAndAdmin':
      case 'getGroupMemberListByJoinTime':
      case 'getGroupMemberListByJoinTimeFilter':
      case 'getGroupAbstractInfo':
      case 'getUsersInGroup':
      case 'getSpecifiedUserGroupRequestInfo':
      case 'getGroupMemberUserIDList':
      case 'searchGroupMembers':
      case 'searchGroups':
      case 'setGroupMemberInfoEx':
      case 'setGroupMemberRoleLevelBySelf':
      case 'checkGroupMemberFullSync':
      case 'checkLocalGroupFullSync':
      case 'deleteGroupRequestsFromBoth':
      case 'getFullJoinGroupIDs':
      case 'getFullGroupMemberUserIDs':
      case 'getIncrementalJoinGroups':
      case 'getIncrementalGroupMembers':
      case 'getIncrementalGroupMembersBatch':
      case 'setGroupMemberNicknameBySelf':
        return null;

      default:
        throw UnsupportedError('GroupManager method not implemented: $method');
    }
  }

  // ─── UserManager ───
  Future<dynamic> _handleUserManager(String method, Map<String, dynamic> args, String? operationID) async {
    switch (method) {
      case 'setUserListener':
        return null;

      case 'getUsersInfo':
        final userIDs = args['userIDList'] as List<dynamic>? ?? [];
        if (userIDs.isEmpty) return <PublicUserInfo>[];
        try {
          final resp = await _post('/user/get_users_info', {'userIDs': userIDs});
          final list = resp?['usersInfo'] as List<dynamic>? ?? resp?['users'] as List<dynamic>? ?? [];
          return list.map((e) => PublicUserInfo.fromJson(e as Map<String, dynamic>)).toList();
        } catch (_) {
          return userIDs.map((id) => PublicUserInfo(userID: id as String)).toList();
        }

      case 'getSelfUserInfo':
        try {
          final resp = await _post('/user/get_users_info', {'userIDs': [_userID]});
          final list = resp?['usersInfo'] as List<dynamic>? ?? resp?['users'] as List<dynamic>? ?? [];
          if (list.isNotEmpty) return UserInfo.fromJson(list.first as Map<String, dynamic>);
        } catch (_) {}
        return UserInfo(userID: _userID);

      case 'setSelfInfo':
        try {
          await _post('/user/update_user_info', args);
        } catch (_) {}
        return null;

      case 'subscribeUsersStatus':
      case 'getSubscribeUsersStatus':
      case 'getUserStatus':
      case 'setAppBackgroundStatus':
      case 'networkStatusChanged':
      case 'setGlobalRecvMessageOpt':
        return null;

      default:
        throw UnsupportedError('UserManager method not implemented: $method');
    }
  }

  // ─── Helpers ───
  Future<Map<String, dynamic>?> _post(String path, Map<String, dynamic> data) async {
    final resp = await httpClient.postRaw(path, data: data);
    return resp['data'] as Map<String, dynamic>?;
  }

  String _conversationID(String sourceID, int sessionType) {
    if (sessionType == 1) {
      // C2C
      final ids = <String>[_userID ?? '', sourceID]..sort();
      return 'si_${ids[0]}_${ids[1]}';
    } else if (sessionType == 2) {
      return 'sg_$sourceID';
    }
    return sourceID;
  }

  void dispose() {
    _wsClient.dispose();
    _wsSub?.cancel();
  }
}
