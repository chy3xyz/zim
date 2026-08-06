const user_mod = @import("../user.zig");
const group_mod = @import("../group.zig");
const message_mod = @import("../message.zig");
const conversation_mod = @import("../conversation.zig");
const friend_mod = @import("../friend.zig");
const office_mod = @import("../office.zig");
const organization_mod = @import("../organization.zig");
const third_mod = @import("../third.zig");

// JSON DTO helpers for camelCase serialization (shared by gateway handlers)
pub fn userToJson(user: user_mod.User) struct {
    userID: []const u8,
    nickname: []const u8,
    faceURL: []const u8,
    gender: i16,
    level: i16,
    birth: ?i64,
    areaCode: []const u8,
    telephone: []const u8,
    ex: []const u8,
    appMangerLevel: i16,
    globalRecvMsgOpt: i16,
    createTime: i64,
} {
    return .{
        .userID = user.user_id,
        .nickname = user.nickname,
        .faceURL = user.face_url,
        .gender = user.gender,
        .level = user.level,
        .birth = user.birth,
        .areaCode = user.area_code,
        .telephone = user.telephone,
        .ex = user.ex,
        .appMangerLevel = user.app_manager_level,
        .globalRecvMsgOpt = user.global_recv_msg_opt,
        .createTime = user.create_time,
    };
}

pub fn groupToJson(g: group_mod.Group) struct {
    groupID: []const u8,
    groupName: []const u8,
    notification: []const u8,
    introduction: []const u8,
    faceURL: []const u8,
    ex: []const u8,
    status: i16,
    creatorUserID: []const u8,
    groupType: i16,
    needVerification: i16,
    lookMemberInfo: i16,
    applyMemberFriend: i16,
    notificationUpdateTime: i64,
    notificationUserID: []const u8,
    displayIsRead: bool,
    memberCount: u32,
    createTime: i64,
    updatedAt: i64,
} {
    return .{
        .groupID = g.group_id,
        .groupName = g.group_name,
        .notification = g.notification,
        .introduction = g.introduction,
        .faceURL = g.face_url,
        .ex = g.ex,
        .status = @backingInt(g.status),
        .creatorUserID = g.creator_user_id,
        .groupType = @backingInt(g.group_type),
        .needVerification = g.need_verification,
        .lookMemberInfo = g.look_member_info,
        .applyMemberFriend = g.apply_member_friend,
        .notificationUpdateTime = g.notification_update_time,
        .notificationUserID = g.notification_user_id,
        .displayIsRead = g.display_is_read,
        .memberCount = g.member_count,
        .createTime = g.create_time,
        .updatedAt = g.updated_at,
    };
}

pub fn messageToJson(m: message_mod.Message) struct {
    msgID: []const u8,
    conversationID: []const u8,
    sendID: []const u8,
    recvID: []const u8,
    groupID: []const u8,
    clientMsgID: []const u8,
    serverMsgID: []const u8,
    senderPlatformID: i16,
    senderNickname: []const u8,
    senderFaceUrl: []const u8,
    sessionType: i16,
    msgFrom: i16,
    contentType: i16,
    content: []const u8,
    seq: i64,
    sendTime: i64,
    createTime: i64,
    status: i16,
    isRead: bool,
    options: []const u8,
    offlinePush: []const u8,
    atUserIDList: []const u8,
    attachedInfo: []const u8,
    ex: []const u8,
    keyVersion: i16,
    isRevoke: bool,
    revokeContent: []const u8,
    isEdit: bool,
    editTime: i64,
} {
    return .{
        .msgID = m.msg_id,
        .conversationID = m.conversation_id,
        .sendID = m.sender_id,
        .recvID = m.receiver_id,
        .groupID = m.group_id,
        .clientMsgID = m.client_msg_id,
        .serverMsgID = m.server_msg_id,
        .senderPlatformID = m.sender_platform_id,
        .senderNickname = m.sender_nickname,
        .senderFaceUrl = m.sender_face_url,
        .sessionType = @backingInt(m.session_type),
        .msgFrom = m.msg_from,
        .contentType = @backingInt(m.content_type),
        .content = m.content,
        .seq = m.seq,
        .sendTime = m.send_time,
        .createTime = m.create_time,
        .status = m.status,
        .isRead = m.is_read,
        .options = m.options,
        .offlinePush = m.offline_push,
        .atUserIDList = m.at_user_id_list,
        .attachedInfo = m.attached_info,
        .ex = m.ex,
        .keyVersion = m.key_version,
        .isRevoke = m.is_revoke,
        .revokeContent = m.revoke_content,
        .isEdit = m.is_edit,
        .editTime = m.edit_time,
    };
}

pub fn conversationToJson(c: conversation_mod.Conversation) struct {
    id: []const u8,
    ownerUserID: []const u8,
    conversationID: []const u8,
    conversationType: i16,
    userID: []const u8,
    groupID: []const u8,
    recvMsgOpt: i16,
    isPinned: bool,
    isPrivateChat: bool,
    burnDuration: i32,
    groupAtType: i16,
    attachedInfo: []const u8,
    ex: []const u8,
    maxSeq: i64,
    minSeq: i64,
    hasReadSeq: i64,
    latestMsg: []const u8,
    latestMsgSendTime: i64,
    latestMsgSendID: []const u8,
    latestMsgContentType: i16,
    createTime: i64,
    updateTime: i64,
    isMsgDestruct: bool,
    msgDestructTime: i64,
    unreadCount: i64,
} {
    return .{
        .id = c.id,
        .ownerUserID = c.owner_user_id,
        .conversationID = c.conversation_id,
        .conversationType = @backingInt(c.conversation_type),
        .userID = c.user_id,
        .groupID = c.group_id,
        .recvMsgOpt = c.recv_msg_opt,
        .isPinned = c.is_pinned,
        .isPrivateChat = c.is_private_chat,
        .burnDuration = c.burn_duration,
        .groupAtType = c.group_at_type,
        .attachedInfo = c.attached_info,
        .ex = c.ex,
        .maxSeq = c.max_seq,
        .minSeq = c.min_seq,
        .hasReadSeq = c.has_read_seq,
        .latestMsg = c.latest_msg,
        .latestMsgSendTime = c.latest_msg_send_time,
        .latestMsgSendID = c.latest_msg_send_id,
        .latestMsgContentType = c.latest_msg_content_type,
        .createTime = c.create_time,
        .updateTime = c.update_time,
        .isMsgDestruct = c.is_msg_destruct,
        .msgDestructTime = c.msg_destruct_time,
        .unreadCount = c.max_seq - c.has_read_seq,
    };
}

pub fn friendInfoToJson(f: friend_mod.FriendInfo) struct {
    ownerUserID: []const u8,
    friendUserID: []const u8,
    userID: []const u8,
    nickname: []const u8,
    faceURL: []const u8,
    remark: []const u8,
    createTime: i64,
    addSource: i16,
    operatorUserID: []const u8,
    ex: []const u8,
    updatedAt: i64,
    isPinned: bool,
    friendUser: struct {
        userID: []const u8,
        nickname: []const u8,
        faceURL: []const u8,
    },
} {
    return .{
        .ownerUserID = f.owner_user_id,
        .friendUserID = f.friend_user_id,
        .userID = f.friend_user_id,
        .nickname = f.nickname,
        .faceURL = f.face_url,
        .remark = f.remark,
        .createTime = f.create_time,
        .addSource = f.add_source,
        .operatorUserID = f.operator_user_id,
        .ex = f.ex,
        .updatedAt = f.updated_at,
        .isPinned = f.is_pinned,
        .friendUser = .{
            .userID = f.friend_user_id,
            .nickname = f.nickname,
            .faceURL = f.face_url,
        },
    };
}

pub fn blackInfoToJson(b: friend_mod.BlackInfo) struct {
    ownerUserID: []const u8,
    blockUserID: []const u8,
    userID: []const u8,
    nickname: []const u8,
    faceURL: []const u8,
    gender: i16,
    createTime: i64,
    addSource: i16,
    operatorUserID: []const u8,
    ex: []const u8,
    updatedAt: i64,
    blackUserInfo: struct {
        userID: []const u8,
        nickname: []const u8,
        faceURL: []const u8,
    },
} {
    return .{
        .ownerUserID = b.owner_user_id,
        .blockUserID = b.block_user_id,
        .userID = b.user_id,
        .nickname = b.nickname,
        .faceURL = b.face_url,
        .gender = b.gender,
        .createTime = b.create_time,
        .addSource = b.add_source,
        .operatorUserID = b.operator_user_id,
        .ex = b.ex,
        .updatedAt = b.updated_at,
        .blackUserInfo = .{
            .userID = b.user_id,
            .nickname = b.nickname,
            .faceURL = b.face_url,
        },
    };
}

pub fn groupMemberToJson(m: group_mod.GroupMember) struct {
    groupID: []const u8,
    userID: []const u8,
    nickname: []const u8,
    faceURL: []const u8,
    appMangerLevel: i16,
    roleLevel: i16,
    joinTime: i64,
    joinSource: i16,
    inviterUserID: []const u8,
    operatorUserID: []const u8,
    muteEndTime: i64,
    ex: []const u8,
    updatedAt: i64,
} {
    return .{
        .groupID = m.group_id,
        .userID = m.user_id,
        .nickname = m.nickname,
        .faceURL = m.face_url,
        .appMangerLevel = m.app_manager_level,
        .roleLevel = m.role_level,
        .joinTime = m.join_time,
        .joinSource = m.join_source,
        .inviterUserID = m.inviter_user_id,
        .operatorUserID = m.operator_user_id,
        .muteEndTime = m.mute_end_time,
        .ex = m.ex,
        .updatedAt = m.updated_at,
    };
}

pub fn groupRequestToJson(r: group_mod.GroupRequest) struct {
    userID: []const u8,
    groupID: []const u8,
    handleResult: i16,
    reqMsg: []const u8,
    handledMsg: []const u8,
    reqTime: i64,
    handleUserID: []const u8,
    handledTime: i64,
    joinSource: i16,
    inviterUserID: []const u8,
    ex: []const u8,
} {
    return .{
        .userID = r.user_id,
        .groupID = r.group_id,
        .handleResult = r.handle_result,
        .reqMsg = r.req_msg,
        .handledMsg = r.handled_msg,
        .reqTime = r.req_time,
        .handleUserID = r.handle_user_id,
        .handledTime = r.handled_time,
        .joinSource = r.join_source,
        .inviterUserID = r.inviter_user_id,
        .ex = r.ex,
    };
}

pub fn friendRequestToJson(r: friend_mod.FriendRequestInfo) struct {
    fromUserID: []const u8,
    fromNickname: []const u8,
    fromFaceURL: []const u8,
    toUserID: []const u8,
    toNickname: []const u8,
    toFaceURL: []const u8,
    handleResult: i16,
    reqMsg: []const u8,
    createTime: i64,
    handlerUserID: []const u8,
    handleMsg: []const u8,
    handleTime: i64,
    ex: []const u8,
} {
    return .{
        .fromUserID = r.from_user_id,
        .fromNickname = r.from_nickname,
        .fromFaceURL = r.from_face_url,
        .toUserID = r.to_user_id,
        .toNickname = r.to_nickname,
        .toFaceURL = r.to_face_url,
        .handleResult = @backingInt(r.handle_result),
        .reqMsg = r.req_msg,
        .createTime = r.create_time,
        .handlerUserID = r.handler_user_id,
        .handleMsg = r.handle_msg,
        .handleTime = r.handle_time,
        .ex = r.ex,
    };
}

pub fn workMomentToJson(m: office_mod.WorkMoment) struct {
    id: []const u8,
    userID: []const u8,
    faceURL: []const u8,
    nickname: []const u8,
    content: []const u8,
    metas: []const u8,
    permission: []const u8,
    atUserIDs: []const u8,
    permissionUserIDs: []const u8,
    likeUsers: []const u8,
    comments: []const u8,
    createTime: i64,
} {
    return .{
        .id = m.id,
        .userID = m.user_id,
        .faceURL = m.face_url,
        .nickname = m.nickname,
        .content = m.content,
        .metas = m.metas,
        .permission = m.permission,
        .atUserIDs = m.at_user_ids,
        .permissionUserIDs = m.permission_user_ids,
        .likeUsers = m.like_users,
        .comments = m.comments,
        .createTime = m.create_time,
    };
}

pub fn collectToJson(c: office_mod.Collect) struct {
    id: []const u8,
    userID: []const u8,
    collectType: []const u8,
    content: []const u8,
    uuid: []const u8,
    createTime: i64,
} {
    return .{
        .id = c.id,
        .userID = c.user_id,
        .collectType = c.collect_type,
        .content = c.content,
        .uuid = c.uuid,
        .createTime = c.create_time,
    };
}

pub fn tagToJson(t: office_mod.Tag) struct {
    id: []const u8,
    userID: []const u8,
    tagName: []const u8,
    userIDList: []const []const u8,
    createTime: i64,
} {
    return .{
        .id = t.id,
        .userID = t.user_id,
        .tagName = t.tag_name,
        .userIDList = t.user_id_list,
        .createTime = t.create_time,
    };
}

pub fn orgMemberToJson(m: organization_mod.DepartmentMember) struct {
    userID: []const u8,
    nickname: []const u8,
    faceURL: []const u8,
    departmentID: []const u8,
    departmentName: []const u8,
    order: i32,
    position: []const u8,
} {
    return .{
        .userID = m.user_id,
        .nickname = m.nickname,
        .faceURL = m.face_url,
        .departmentID = m.department_id,
        .departmentName = m.department_name,
        .order = m.order,
        .position = m.position,
    };
}

pub fn departmentToJson(d: organization_mod.Department) struct {
    departmentID: []const u8,
    name: []const u8,
    faceURL: []const u8,
    parentDepartmentID: []const u8,
    order: i32,
    createTime: i64,
    subDepartmentNum: i32,
    memberNum: i32,
} {
    return .{
        .departmentID = d.department_id,
        .name = d.name,
        .faceURL = d.face_url,
        .parentDepartmentID = d.parent_department_id,
        .order = d.order,
        .createTime = d.create_time,
        .subDepartmentNum = d.sub_department_num,
        .memberNum = d.member_num,
    };
}

pub fn organizationToJson(o: organization_mod.Organization) struct {
    id: []const u8,
    logoURL: []const u8,
    name: []const u8,
    homepage: []const u8,
    introduction: []const u8,
    createTime: i64,
} {
    return .{
        .id = o.id,
        .logoURL = o.logo_url,
        .name = o.name,
        .homepage = o.homepage,
        .introduction = o.introduction,
        .createTime = o.create_time,
    };
}

pub fn logEntryToJson(l: third_mod.LogEntry) struct {
    userID: []const u8,
    platform: i32,
    fileURL: []const u8,
    createdAt: i64,
} {
    return .{
        .userID = l.user_id,
        .platform = l.platform,
        .fileURL = l.file_url,
        .createdAt = l.created_at,
    };
}

pub fn userCommandToJson(c: user_mod.UserCommand) struct {
    commandID: []const u8,
    commandValue: []const u8,
    createTime: i64,
} {
    return .{
        .commandID = c.command_id,
        .commandValue = c.command_value,
        .createTime = c.create_time,
    };
}
