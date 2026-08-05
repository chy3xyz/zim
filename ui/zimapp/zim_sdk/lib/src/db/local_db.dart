import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class ZimLocalDB {
  static final ZimLocalDB _instance = ZimLocalDB._internal();
  factory ZimLocalDB() => _instance;
  ZimLocalDB._internal();

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'zim_sdk.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS conversations (
            conversation_id TEXT PRIMARY KEY,
            conversation_type INTEGER,
            user_id TEXT,
            group_id TEXT,
            show_name TEXT,
            face_url TEXT,
            recv_msg_opt INTEGER DEFAULT 0,
            unread_count INTEGER DEFAULT 0,
            latest_msg TEXT,
            latest_msg_send_time INTEGER DEFAULT 0,
            draft_text TEXT,
            draft_text_time INTEGER DEFAULT 0,
            is_pinned INTEGER DEFAULT 0,
            is_private_chat INTEGER DEFAULT 0,
            group_at_type INTEGER DEFAULT 0,
            attached_info TEXT,
            ex TEXT,
            msg_destruct_time INTEGER DEFAULT 0,
            is_msg_destruct INTEGER DEFAULT 0,
            max_seq INTEGER DEFAULT 0,
            min_seq INTEGER DEFAULT 0,
            has_read_seq INTEGER DEFAULT 0,
            sync_offset INTEGER DEFAULT 0,
            sync_offset_t INTEGER DEFAULT 0
          )
        ''');
        await db.execute('CREATE INDEX idx_conv_time ON conversations(latest_msg_send_time DESC)');
        await db.execute('CREATE INDEX idx_conv_user ON conversations(user_id)');
        await db.execute('CREATE INDEX idx_conv_group ON conversations(group_id)');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS messages (
            client_msg_id TEXT PRIMARY KEY,
            server_msg_id TEXT,
            seq INTEGER DEFAULT 0,
            send_id TEXT,
            recv_id TEXT,
            group_id TEXT,
            sender_platform_id INTEGER DEFAULT 0,
            sender_nickname TEXT,
            sender_face_url TEXT,
            session_type INTEGER DEFAULT 1,
            msg_from INTEGER DEFAULT 0,
            content_type INTEGER DEFAULT 101,
            content TEXT,
            status INTEGER DEFAULT 1,
            send_time INTEGER DEFAULT 0,
            create_time INTEGER DEFAULT 0,
            attached_info TEXT,
            ex TEXT,
            is_read INTEGER DEFAULT 0,
            has_reaction INTEGER DEFAULT 0
          )
        ''');
        await db.execute('CREATE INDEX idx_msg_send_time ON messages(send_time DESC)');
        await db.execute('CREATE INDEX idx_msg_send_id ON messages(send_id)');
        await db.execute('CREATE INDEX idx_msg_recv_id ON messages(recv_id)');
        await db.execute('CREATE INDEX idx_msg_group ON messages(group_id)');
        await db.execute('CREATE INDEX idx_msg_session ON messages(session_type)');
        await db.execute('CREATE INDEX idx_msg_content_type ON messages(content_type)');
        await db.execute('CREATE INDEX idx_msg_server ON messages(server_msg_id)');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS friends (
            user_id TEXT PRIMARY KEY,
            remark TEXT,
            create_time INTEGER DEFAULT 0,
            add_source INTEGER DEFAULT 0,
            operator_user_id TEXT,
            nickname TEXT,
            face_url TEXT,
            ex TEXT,
            is_pinned INTEGER DEFAULT 0,
            attached_info TEXT
          )
        ''');
        await db.execute('CREATE INDEX idx_friend_nickname ON friends(nickname)');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS groups (
            group_id TEXT PRIMARY KEY,
            group_name TEXT,
            notification TEXT,
            introduction TEXT,
            face_url TEXT,
            create_time INTEGER DEFAULT 0,
            status INTEGER DEFAULT 0,
            creator_user_id TEXT,
            group_type INTEGER DEFAULT 0,
            owner_user_id TEXT,
            member_count INTEGER DEFAULT 0,
            ex TEXT,
            attached_info TEXT,
            need_verification INTEGER DEFAULT 0,
            look_member_info INTEGER DEFAULT 0,
            apply_member_friend INTEGER DEFAULT 0,
            notification_update_time INTEGER DEFAULT 0,
            notification_user_id TEXT
          )
        ''');
        await db.execute('CREATE INDEX idx_group_name ON groups(group_name)');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS group_members (
            group_id TEXT,
            user_id TEXT,
            nickname TEXT,
            face_url TEXT,
            role_level INTEGER DEFAULT 1,
            join_time INTEGER DEFAULT 0,
            join_source INTEGER DEFAULT 0,
            operator_user_id TEXT,
            ex TEXT,
            attached_info TEXT,
            group_nickname TEXT,
            user_group_face_url TEXT,
            PRIMARY KEY (group_id, user_id)
          )
        ''');
        await db.execute('CREATE INDEX idx_member_group ON group_members(group_id)');
        await db.execute('CREATE INDEX idx_member_user ON group_members(user_id)');
        await db.execute('CREATE INDEX idx_member_nickname ON group_members(nickname)');
      },
    );
  }

  Database get db {
    if (_db == null) throw StateError('DB not initialized');
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ─── Conversations ───
  Future<void> insertConversation(Map<String, dynamic> data) async {
    await db.insert('conversations', data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertConversations(List<Map<String, dynamic>> list) async {
    final batch = db.batch();
    for (final data in list) {
      batch.insert('conversations', data, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getConversations() async {
    return db.query('conversations', orderBy: 'latest_msg_send_time DESC');
  }

  Future<Map<String, dynamic>?> getConversation(String conversationID) async {
    final list = await db.query('conversations', where: 'conversation_id = ?', whereArgs: [conversationID]);
    return list.isNotEmpty ? list.first : null;
  }

  Future<void> deleteConversation(String conversationID) async {
    await db.delete('conversations', where: 'conversation_id = ?', whereArgs: [conversationID]);
  }

  Future<void> clearAllConversations() async {
    await db.delete('conversations');
  }

  // ─── Messages ───
  Future<void> insertMessage(Map<String, dynamic> data) async {
    await db.insert('messages', data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertMessages(List<Map<String, dynamic>> list) async {
    final batch = db.batch();
    for (final data in list) {
      batch.insert('messages', data, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getMessages({
    String? sendID,
    String? recvID,
    String? groupID,
    int? sessionType,
    int? contentType,
    int limit = 100,
    int offset = 0,
  }) async {
    final where = <String>[];
    final whereArgs = <dynamic>[];

    if (sendID != null) {
      where.add('send_id = ?');
      whereArgs.add(sendID);
    }
    if (recvID != null) {
      where.add('recv_id = ?');
      whereArgs.add(recvID);
    }
    if (groupID != null) {
      where.add('group_id = ?');
      whereArgs.add(groupID);
    }
    if (sessionType != null) {
      where.add('session_type = ?');
      whereArgs.add(sessionType);
    }
    if (contentType != null) {
      where.add('content_type = ?');
      whereArgs.add(contentType);
    }

    return db.query(
      'messages',
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'send_time DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<List<Map<String, dynamic>>> searchMessages(String keyword, {int limit = 100}) async {
    return db.query(
      'messages',
      where: 'content LIKE ?',
      whereArgs: ['%$keyword%'],
      orderBy: 'send_time DESC',
      limit: limit,
    );
  }

  Future<void> deleteMessage(String clientMsgID) async {
    await db.delete('messages', where: 'client_msg_id = ?', whereArgs: [clientMsgID]);
  }

  Future<void> deleteMessagesByConversation(String sendID, String recvID) async {
    await db.delete(
      'messages',
      where: '(send_id = ? AND recv_id = ?) OR (send_id = ? AND recv_id = ?)',
      whereArgs: [sendID, recvID, recvID, sendID],
    );
  }

  Future<void> markMessagesAsRead(String sendID, String recvID) async {
    await db.update(
      'messages',
      {'is_read': 1},
      where: 'send_id = ? AND recv_id = ? AND is_read = 0',
      whereArgs: [sendID, recvID],
    );
  }

  // ─── Friends ───
  Future<void> insertFriend(Map<String, dynamic> data) async {
    await db.insert('friends', data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertFriends(List<Map<String, dynamic>> list) async {
    final batch = db.batch();
    for (final data in list) {
      batch.insert('friends', data, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getFriends() async {
    return db.query('friends');
  }

  Future<List<Map<String, dynamic>>> searchFriends(String keyword) async {
    return db.query(
      'friends',
      where: 'nickname LIKE ? OR remark LIKE ? OR user_id LIKE ?',
      whereArgs: ['%$keyword%', '%$keyword%', '%$keyword%'],
    );
  }

  Future<void> deleteFriend(String userID) async {
    await db.delete('friends', where: 'user_id = ?', whereArgs: [userID]);
  }

  Future<void> clearFriends() async {
    await db.delete('friends');
  }

  // ─── Groups ───
  Future<void> insertGroup(Map<String, dynamic> data) async {
    await db.insert('groups', data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertGroups(List<Map<String, dynamic>> list) async {
    final batch = db.batch();
    for (final data in list) {
      batch.insert('groups', data, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getGroups() async {
    return db.query('groups');
  }

  Future<Map<String, dynamic>?> getGroup(String groupID) async {
    final list = await db.query('groups', where: 'group_id = ?', whereArgs: [groupID]);
    return list.isNotEmpty ? list.first : null;
  }

  Future<void> deleteGroup(String groupID) async {
    await db.delete('groups', where: 'group_id = ?', whereArgs: [groupID]);
  }

  // ─── Group members ───
  Future<void> insertGroupMember(Map<String, dynamic> data) async {
    await db.insert('group_members', data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertGroupMembers(List<Map<String, dynamic>> list) async {
    final batch = db.batch();
    for (final data in list) {
      batch.insert('group_members', data, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getGroupMembers(String groupID) async {
    return db.query('group_members', where: 'group_id = ?', whereArgs: [groupID]);
  }

  Future<void> deleteGroupMember(String groupID, String userID) async {
    await db.delete('group_members', where: 'group_id = ? AND user_id = ?', whereArgs: [groupID, userID]);
  }

  Future<void> deleteGroupMembers(String groupID) async {
    await db.delete('group_members', where: 'group_id = ?', whereArgs: [groupID]);
  }
}
