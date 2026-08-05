-- ============================================
-- ZIM Server - Test Data Seed
-- ============================================

-- Clear existing test data (optional, run manually if needed)
-- DELETE FROM messages WHERE sender_id LIKE 'test%' OR receiver_id LIKE 'test%';
-- DELETE FROM conversations WHERE owner_user_id LIKE 'test%';
-- DELETE FROM group_members WHERE user_id LIKE 'test%';
-- DELETE FROM group_requests WHERE user_id LIKE 'test%';
-- DELETE FROM groups WHERE group_id LIKE 'test_group%';
-- DELETE FROM friend_requests WHERE from_user_id LIKE 'test%' OR to_user_id LIKE 'test%';
-- DELETE FROM blacks WHERE owner_user_id LIKE 'test%';
-- DELETE FROM friends WHERE owner_user_id LIKE 'test%';
-- DELETE FROM users WHERE user_id LIKE 'test%' OR user_id = 'admin';

-- ============================================
-- USERS
-- ============================================
INSERT INTO users (user_id, nickname, face_url, gender, level, area_code, telephone, ex, global_recv_msg_opt, register_type, create_time, updated_at) VALUES
('admin', 'Administrator', 'https://example.com/faces/admin.png', 1, 99, '86', '13800000000', '{"role":"admin"}', 0, 0, NOW(), NOW()),
('test_user_1', 'Alice', 'https://example.com/faces/alice.png', 2, 1, '86', '13800000001', '{"bio":"Hello, I am Alice"}', 0, 1, NOW() - INTERVAL '10 days', NOW()),
('test_user_2', 'Bob', 'https://example.com/faces/bob.png', 1, 1, '86', '13800000002', '{"bio":"Hello, I am Bob"}', 0, 1, NOW() - INTERVAL '9 days', NOW()),
('test_user_3', 'Charlie', 'https://example.com/faces/charlie.png', 1, 1, '86', '13800000003', '{"bio":"Hello, I am Charlie"}', 0, 1, NOW() - INTERVAL '8 days', NOW()),
('test_user_4', 'Diana', 'https://example.com/faces/diana.png', 2, 1, '86', '13800000004', '{"bio":"Hello, I am Diana"}', 0, 1, NOW() - INTERVAL '7 days', NOW()),
('test_user_5', 'Eve', 'https://example.com/faces/eve.png', 2, 1, '86', '13800000005', '{"bio":"Hello, I am Eve"}', 0, 1, NOW() - INTERVAL '6 days', NOW()),
('test_user_6', 'Frank', 'https://example.com/faces/frank.png', 1, 1, '86', '13800000006', '{"bio":"Hello, I am Frank"}', 0, 1, NOW() - INTERVAL '5 days', NOW())
ON CONFLICT (user_id) DO UPDATE SET nickname = EXCLUDED.nickname, face_url = EXCLUDED.face_url;

-- ============================================
-- FRIENDS (bidirectional)
-- ============================================
INSERT INTO friends (owner_user_id, friend_user_id, remark, create_time, add_source, operator_user_id, ex) VALUES
('test_user_1', 'test_user_2', 'Best Friend Bob', NOW() - INTERVAL '5 days', 1, 'test_user_1', ''),
('test_user_2', 'test_user_1', 'Best Friend Alice', NOW() - INTERVAL '5 days', 1, 'test_user_1', ''),
('test_user_1', 'test_user_3', 'Colleague Charlie', NOW() - INTERVAL '4 days', 2, 'test_user_1', ''),
('test_user_3', 'test_user_1', 'Colleague Alice', NOW() - INTERVAL '4 days', 2, 'test_user_1', ''),
('test_user_2', 'test_user_3', 'Friend Charlie', NOW() - INTERVAL '3 days', 1, 'test_user_2', ''),
('test_user_3', 'test_user_2', 'Friend Bob', NOW() - INTERVAL '3 days', 1, 'test_user_2', '')
ON CONFLICT (owner_user_id, friend_user_id) DO UPDATE SET remark = EXCLUDED.remark;

-- ============================================
-- BLACKLIST
-- ============================================
INSERT INTO blacks (owner_user_id, block_user_id, create_time, add_source, operator_user_id, ex) VALUES
('test_user_1', 'test_user_4', NOW() - INTERVAL '2 days', 1, 'test_user_1', '')
ON CONFLICT (owner_user_id, block_user_id) DO NOTHING;

-- ============================================
-- FRIEND REQUESTS
-- ============================================
INSERT INTO friend_requests (from_user_id, to_user_id, handle_result, req_msg, create_time, handler_user_id, handle_msg, handle_time, ex) VALUES
('test_user_5', 'test_user_1', 0, 'Hi Alice, can we be friends?', NOW() - INTERVAL '1 day', '', '', NULL, ''),
('test_user_4', 'test_user_2', 1, 'Hello Bob!', NOW() - INTERVAL '3 days', 'test_user_2', 'Sure!', NOW() - INTERVAL '2 days', '')
ON CONFLICT (from_user_id, to_user_id) DO UPDATE SET req_msg = EXCLUDED.req_msg;

-- ============================================
-- GROUPS
-- ============================================
INSERT INTO groups (group_id, group_name, notification, introduction, face_url, ex, status, creator_user_id, group_type, need_verification, look_member_info, apply_member_friend, notification_update_time, notification_user_id, display_is_read, create_time, updated_at) VALUES
('test_group_1', 'ZIM Developers', 'Welcome to ZIM dev group!', 'A group for ZIM developers', 'https://example.com/groups/dev.png', '{"tag":"dev"}', 0, 'test_user_1', 0, 1, 1, 0, NOW(), 'test_user_1', true, NOW() - INTERVAL '7 days', NOW()),
('test_group_2', 'Flutter Fans', 'Welcome Flutter enthusiasts!', 'Discussion about Flutter', 'https://example.com/groups/flutter.png', '{"tag":"flutter"}', 0, 'test_user_2', 0, 0, 1, 1, NOW(), 'test_user_2', false, NOW() - INTERVAL '5 days', NOW())
ON CONFLICT (group_id) DO UPDATE SET group_name = EXCLUDED.group_name;

-- ============================================
-- GROUP MEMBERS
-- ============================================
INSERT INTO group_members (group_id, user_id, nickname, face_url, role_level, join_time, join_source, inviter_user_id, operator_user_id, mute_end_time, ex) VALUES
('test_group_1', 'test_user_1', 'Alice', 'https://example.com/faces/alice.png', 2, NOW() - INTERVAL '7 days', 0, '', 'test_user_1', NULL, ''),
('test_group_1', 'test_user_2', 'Bob', 'https://example.com/faces/bob.png', 1, NOW() - INTERVAL '6 days', 1, 'test_user_1', 'test_user_1', NULL, ''),
('test_group_1', 'test_user_3', 'Charlie', 'https://example.com/faces/charlie.png', 1, NOW() - INTERVAL '5 days', 1, 'test_user_1', 'test_user_1', NULL, ''),
('test_group_2', 'test_user_2', 'Bob', 'https://example.com/faces/bob.png', 2, NOW() - INTERVAL '5 days', 0, '', 'test_user_2', NULL, ''),
('test_group_2', 'test_user_3', 'Charlie', 'https://example.com/faces/charlie.png', 1, NOW() - INTERVAL '4 days', 1, 'test_user_2', 'test_user_2', NULL, ''),
('test_group_2', 'test_user_4', 'Diana', 'https://example.com/faces/diana.png', 1, NOW() - INTERVAL '3 days', 1, 'test_user_2', 'test_user_2', NULL, '')
ON CONFLICT (group_id, user_id) DO UPDATE SET role_level = EXCLUDED.role_level;

-- ============================================
-- GROUP REQUESTS
-- ============================================
INSERT INTO group_requests (user_id, group_id, handle_result, req_msg, req_time, handle_user_id, handled_msg, handled_time, join_source, inviter_user_id, ex) VALUES
('test_user_5', 'test_group_1', 0, 'Can I join the dev group?', NOW() - INTERVAL '1 day', '', '', NULL, 0, '', ''),
('test_user_6', 'test_group_2', 1, 'I love Flutter!', NOW() - INTERVAL '2 days', 'test_user_2', 'Welcome!', NOW() - INTERVAL '1 day', 1, 'test_user_2', '')
ON CONFLICT (user_id, group_id) DO UPDATE SET req_msg = EXCLUDED.req_msg;

-- ============================================
-- CONVERSATIONS
-- ============================================
INSERT INTO conversations (owner_user_id, conversation_id, conversation_type, user_id, group_id, recv_msg_opt, is_pinned, is_private_chat, burn_duration, group_at_type, attached_info, ex, max_seq, min_seq, has_read_seq, latest_msg, latest_msg_send_time, latest_msg_send_id, latest_msg_content_type, create_time, update_time, is_msg_destruct, msg_destruct_time, latest_msg_destruct_time) VALUES
('test_user_1', 'si_test_user_1_test_user_2', 1, 'test_user_2', '', 0, true, false, 30, 0, '', '', 2, 1, 2, '{"text":"Hey Bob, how are you?"}', EXTRACT(EPOCH FROM (NOW() - INTERVAL '1 hour'))::bigint * 1000, 'test_user_2', 101, NOW() - INTERVAL '2 days', NOW(), false, 0, NULL),
('test_user_2', 'si_test_user_2_test_user_1', 1, 'test_user_1', '', 0, false, false, 30, 0, '', '', 2, 1, 2, '{"text":"Hey Bob, how are you?"}', EXTRACT(EPOCH FROM (NOW() - INTERVAL '1 hour'))::bigint * 1000, 'test_user_2', 101, NOW() - INTERVAL '2 days', NOW(), false, 0, NULL),
('test_user_1', 'si_test_user_1_test_user_3', 1, 'test_user_3', '', 0, false, false, 30, 0, '', '', 1, 1, 1, '{"text":"Meeting at 3pm"}', EXTRACT(EPOCH FROM (NOW() - INTERVAL '3 hours'))::bigint * 1000, 'test_user_3', 101, NOW() - INTERVAL '3 days', NOW(), false, 0, NULL),
('test_user_1', 'sg_test_group_1', 2, '', 'test_group_1', 0, true, false, 30, 0, '', '', 3, 1, 3, '{"text":"New release today!"}', EXTRACT(EPOCH FROM (NOW() - INTERVAL '30 minutes'))::bigint * 1000, 'test_user_3', 101, NOW() - INTERVAL '1 day', NOW(), false, 0, NULL)
ON CONFLICT (owner_user_id, conversation_id) DO UPDATE SET latest_msg = EXCLUDED.latest_msg, latest_msg_send_time = EXCLUDED.latest_msg_send_time;

-- ============================================
-- MESSAGES
-- ============================================
INSERT INTO messages (conversation_id, sender_id, receiver_id, group_id, client_msg_id, server_msg_id, sender_platform_id, sender_nickname, sender_face_url, session_type, msg_from, content_type, content, seq, send_time, create_time, status, is_read, options, offline_push, at_user_id_list, attached_info, ex, key_version, is_revoke, revoke_content) VALUES
-- Single chat: test_user_1 <-> test_user_2
('si_test_user_1_test_user_2', 'test_user_2', 'test_user_1', '', 'client_msg_001', 'srv_msg_001', 1, 'Bob', 'https://example.com/faces/bob.png', 1, 100, 101, 'Hey Alice, how are you?', 1, EXTRACT(EPOCH FROM (NOW() - INTERVAL '2 hours'))::bigint * 1000, NOW() - INTERVAL '2 hours', 1, true, '{}', '{}', '[]', '', '', 0, false, ''),
('si_test_user_1_test_user_2', 'test_user_1', 'test_user_2', '', 'client_msg_002', 'srv_msg_002', 1, 'Alice', 'https://example.com/faces/alice.png', 1, 100, 101, 'I am good, thanks Bob!', 2, EXTRACT(EPOCH FROM (NOW() - INTERVAL '1 hour'))::bigint * 1000, NOW() - INTERVAL '1 hour', 1, true, '{}', '{}', '[]', '', '', 0, false, ''),

-- Single chat: test_user_1 <-> test_user_3
('si_test_user_1_test_user_3', 'test_user_3', 'test_user_1', '', 'client_msg_003', 'srv_msg_003', 1, 'Charlie', 'https://example.com/faces/charlie.png', 1, 100, 101, 'Meeting at 3pm', 1, EXTRACT(EPOCH FROM (NOW() - INTERVAL '3 hours'))::bigint * 1000, NOW() - INTERVAL '3 hours', 1, true, '{}', '{}', '[]', '', '', 0, false, ''),

-- Group chat: test_group_1
('sg_test_group_1', 'test_user_1', '', 'test_group_1', 'client_msg_004', 'srv_msg_004', 1, 'Alice', 'https://example.com/faces/alice.png', 2, 100, 101, 'Welcome everyone!', 1, EXTRACT(EPOCH FROM (NOW() - INTERVAL '5 hours'))::bigint * 1000, NOW() - INTERVAL '5 hours', 1, true, '{}', '{}', '[]', '', '', 0, false, ''),
('sg_test_group_1', 'test_user_2', '', 'test_group_1', 'client_msg_005', 'srv_msg_005', 1, 'Bob', 'https://example.com/faces/bob.png', 2, 100, 101, 'Thanks Alice!', 2, EXTRACT(EPOCH FROM (NOW() - INTERVAL '4 hours'))::bigint * 1000, NOW() - INTERVAL '4 hours', 1, true, '{}', '{}', '[]', '', '', 0, false, ''),
('sg_test_group_1', 'test_user_3', '', 'test_group_1', 'client_msg_006', 'srv_msg_006', 1, 'Charlie', 'https://example.com/faces/charlie.png', 2, 100, 101, 'New release today!', 3, EXTRACT(EPOCH FROM (NOW() - INTERVAL '30 minutes'))::bigint * 1000, NOW() - INTERVAL '30 minutes', 1, false, '{}', '{}', '[]', '', '', 0, false, '')
ON CONFLICT (conversation_id, client_msg_id) DO UPDATE SET content = EXCLUDED.content;

-- ============================================
-- SEQ TRACKING
-- ============================================
INSERT INTO seq_conversations (conversation_id, max_seq, min_seq, updated_at) VALUES
('si_test_user_1_test_user_2', 2, 1, NOW()),
('si_test_user_1_test_user_3', 1, 1, NOW()),
('sg_test_group_1', 3, 1, NOW())
ON CONFLICT (conversation_id) DO UPDATE SET max_seq = EXCLUDED.max_seq;

INSERT INTO seq_users (user_id, conversation_id, has_read_seq, seq) VALUES
('test_user_1', 'si_test_user_1_test_user_2', 2, 2),
('test_user_1', 'si_test_user_1_test_user_3', 1, 1),
('test_user_1', 'sg_test_group_1', 3, 3),
('test_user_2', 'si_test_user_2_test_user_1', 2, 2),
('test_user_3', 'sg_test_group_1', 2, 2)
ON CONFLICT (user_id, conversation_id) DO UPDATE SET has_read_seq = EXCLUDED.has_read_seq;
