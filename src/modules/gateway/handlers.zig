// ============================================================
// Gateway route table + domain handler entry points.
// Handlers live per-domain in gateway/handlers/*.zig; this file
// keeps the declarative route table and the public surface used by
// modules/gateway.zig (GatewayRoutes / sendFail / isPublicPath / getBearerToken).
// ============================================================

const zmodu = @import("zmodu");
const http = zmodu.http;

const helpers = @import("handlers/helpers.zig");
const auth_h = @import("handlers/auth.zig");
const account_h = @import("handlers/account.zig");
const health_h = @import("handlers/health.zig");
const user_h = @import("handlers/user.zig");
const friend_h = @import("handlers/friend.zig");
const group_h = @import("handlers/group.zig");
const message_h = @import("handlers/message.zig");
const conversation_h = @import("handlers/conversation.zig");
const encryption_h = @import("handlers/encryption.zig");
const office_h = @import("handlers/office.zig");
const organization_h = @import("handlers/organization.zig");
const third_h = @import("handlers/third.zig");
const statistics_h = @import("handlers/statistics.zig");
const rtc_h = @import("handlers/rtc.zig");
const jssdk_h = @import("handlers/jssdk.zig");
const admin_h = @import("handlers/adminapi.zig");

// Forwarded for modules/gateway.zig (keeps the public surface unchanged).
pub const sendFail = helpers.sendFail;
pub const isPublicPath = helpers.isPublicPath;
pub const getBearerToken = helpers.getBearerToken;

pub const GatewayRoutes = struct {
    pub const module_name = "gateway";
    pub const nest = .{};
    pub const State = struct {};

    const auth_routes = [_]http.RouteSpec(State){
        // Auth
        .{ .method = .POST, .path = "/auth/get_user_token", .handler = auth_h.handleGetUserToken, .meta = .{ .auth = .public } },
        .{ .method = .POST, .path = "/auth/get_admin_token", .handler = auth_h.handleGetAdminToken, .meta = .{ .auth = .public } },
        .{ .method = .POST, .path = "/auth/parse_token", .handler = auth_h.handleParseToken, .meta = .{ .auth = .public } },
        .{ .method = .POST, .path = "/auth/force_logout", .handler = auth_h.handleForceLogout, .meta = .{} },
    };

    const account_routes = [_]http.RouteSpec(State){
        // Account
        .{ .method = .POST, .path = "/account/login", .handler = account_h.handleAccountLogin, .meta = .{ .auth = .public } },
        .{ .method = .POST, .path = "/account/register", .handler = account_h.handleAccountRegister, .meta = .{ .auth = .public } },
        .{ .method = .POST, .path = "/account/code/send", .handler = account_h.handleSendVerificationCode, .meta = .{ .auth = .public } },
        .{ .method = .POST, .path = "/account/code/verify", .handler = account_h.handleVerifyCode, .meta = .{ .auth = .public } },
        .{ .method = .POST, .path = "/account/password/reset", .handler = account_h.handleResetPassword, .meta = .{ .auth = .public } },
        .{ .method = .POST, .path = "/account/password/change", .handler = account_h.handleChangePassword, .meta = .{} },
        .{ .method = .POST, .path = "/account/info", .handler = account_h.handleAccountInfo, .meta = .{} },
    };

    const health_routes = [_]http.RouteSpec(State){
        // Health
        .{ .method = .GET, .path = "/health", .handler = health_h.handleHealth, .meta = .{ .auth = .public } },
    };

    const user_routes = [_]http.RouteSpec(State){
        // User
        .{ .method = .POST, .path = "/user/user_register", .handler = user_h.handleUserRegister, .meta = .{ .auth = .public } },
        .{ .method = .POST, .path = "/user/unregister_user", .handler = user_h.handleUnregisterUser, .meta = .{} },
        .{ .method = .POST, .path = "/user/update_user_info", .handler = user_h.handleUpdateUserInfo, .meta = .{} },
        .{ .method = .POST, .path = "/user/update_user_info_ex", .handler = user_h.handleUpdateUserInfoEx, .meta = .{} },
        .{ .method = .POST, .path = "/user/get_users_info", .handler = user_h.handleGetUsersInfo, .meta = .{} },
        .{ .method = .POST, .path = "/user/get_all_users_uid", .handler = user_h.handleGetAllUsersID, .meta = .{} },
        .{ .method = .POST, .path = "/user/account_check", .handler = user_h.handleAccountCheck, .meta = .{} },
        .{ .method = .POST, .path = "/user/get_users", .handler = user_h.handleGetUsers, .meta = .{} },
        .{ .method = .POST, .path = "/user/find/full", .handler = user_h.handleGetUsersFullInfo, .meta = .{} },
        .{ .method = .POST, .path = "/user/search/full", .handler = user_h.handleSearchUsersFullInfo, .meta = .{} },
        .{ .method = .POST, .path = "/user/get_users_online_status", .handler = user_h.handleGetUsersOnlineStatus, .meta = .{} },
        .{ .method = .POST, .path = "/user/get_users_online_token_detail", .handler = user_h.handleGetUsersOnlineTokenDetail, .meta = .{} },
        .{ .method = .POST, .path = "/user/set_global_msg_recv_opt", .handler = user_h.handleSetGlobalRecvMsgOpt, .meta = .{} },
        .{ .method = .POST, .path = "/user/subscribe_users_status", .handler = user_h.handleSubscribeUsersStatus, .meta = .{} },
        .{ .method = .POST, .path = "/user/get_users_status", .handler = user_h.handleGetUsersStatus, .meta = .{} },
        .{ .method = .POST, .path = "/user/get_subscribe_users_status", .handler = user_h.handleGetSubscribeUsersStatus, .meta = .{} },
        .{ .method = .POST, .path = "/user/user_register_count", .handler = user_h.handleUserRegisterCount, .meta = .{} },
        .{ .method = .POST, .path = "/user/process_user_command_add", .handler = user_h.handleProcessUserCommandAdd, .meta = .{} },
        .{ .method = .POST, .path = "/user/process_user_command_delete", .handler = user_h.handleProcessUserCommandDelete, .meta = .{} },
        .{ .method = .POST, .path = "/user/process_user_command_update", .handler = user_h.handleProcessUserCommandUpdate, .meta = .{} },
        .{ .method = .POST, .path = "/user/process_user_command_get", .handler = user_h.handleProcessUserCommandGet, .meta = .{} },
        .{ .method = .POST, .path = "/user/process_user_command_get_all", .handler = user_h.handleProcessUserCommandGetAll, .meta = .{} },
    };

    const friend_routes = [_]http.RouteSpec(State){
        // Friend
        .{ .method = .POST, .path = "/friend/add_friend", .handler = friend_h.handleAddFriend, .meta = .{} },
        .{ .method = .POST, .path = "/friend/add_friend_response", .handler = friend_h.handleFriendResponse, .meta = .{} },
        .{ .method = .POST, .path = "/friend/get_friend_list", .handler = friend_h.handleGetFriendList, .meta = .{} },
        .{ .method = .POST, .path = "/friend/get_friend_apply_list", .handler = friend_h.handleGetFriendApplyList, .meta = .{} },
        .{ .method = .POST, .path = "/friend/get_designated_friend_apply", .handler = friend_h.handleGetDesignatedFriendApply, .meta = .{} },
        .{ .method = .POST, .path = "/friend/get_self_friend_apply_list", .handler = friend_h.handleGetSelfApplyList, .meta = .{} },
        .{ .method = .POST, .path = "/friend/get_designated_friends", .handler = friend_h.handleGetDesignatedFriends, .meta = .{} },
        .{ .method = .POST, .path = "/friend/delete_friend", .handler = friend_h.handleDeleteFriend, .meta = .{} },
        .{ .method = .POST, .path = "/friend/set_friend_remark", .handler = friend_h.handleSetFriendRemark, .meta = .{} },
        .{ .method = .POST, .path = "/friend/add_black", .handler = friend_h.handleAddBlack, .meta = .{} },
        .{ .method = .POST, .path = "/friend/get_black_list", .handler = friend_h.handleGetBlackList, .meta = .{} },
        .{ .method = .POST, .path = "/friend/get_specified_blacks", .handler = friend_h.handleGetSpecifiedBlacks, .meta = .{} },
        .{ .method = .POST, .path = "/friend/remove_black", .handler = friend_h.handleRemoveBlack, .meta = .{} },
        .{ .method = .POST, .path = "/friend/get_incremental_blacks", .handler = friend_h.handleGetIncrementalBlacks, .meta = .{} },
        .{ .method = .POST, .path = "/friend/import_friend", .handler = friend_h.handleImportFriend, .meta = .{} },
        .{ .method = .POST, .path = "/friend/is_friend", .handler = friend_h.handleIsFriend, .meta = .{} },
        .{ .method = .POST, .path = "/friend/get_friend_id", .handler = friend_h.handleGetFriendID, .meta = .{} },
        .{ .method = .POST, .path = "/friend/get_specified_friends_info", .handler = friend_h.handleGetSpecifiedFriendsInfo, .meta = .{} },
        .{ .method = .POST, .path = "/friend/update_friends", .handler = friend_h.handleUpdateFriends, .meta = .{} },
        .{ .method = .POST, .path = "/friend/search", .handler = friend_h.handleSearchFriendInfo, .meta = .{} },
        .{ .method = .POST, .path = "/friend/get_incremental_friends", .handler = friend_h.handleGetIncrementalFriends, .meta = .{} },
        .{ .method = .POST, .path = "/friend/get_full_friend_user_ids", .handler = friend_h.handleGetFullFriendUserIDs, .meta = .{} },
        .{ .method = .POST, .path = "/friend/get_self_unhandled_apply_count", .handler = friend_h.handleGetSelfUnhandledApplyCount, .meta = .{} },
        .{ .method = .POST, .path = "/friend/delete_friend_requests_from_user", .handler = friend_h.handleDeleteFriendRequestsFromUser, .meta = .{} },
        .{ .method = .POST, .path = "/friend/delete_friend_requests_to_user", .handler = friend_h.handleDeleteFriendRequestsToUser, .meta = .{} },
    };

    const group_routes = [_]http.RouteSpec(State){
        // Group
        .{ .method = .POST, .path = "/group/create_group", .handler = group_h.handleCreateGroup, .meta = .{} },
        .{ .method = .POST, .path = "/group/set_group_info", .handler = group_h.handleSetGroupInfo, .meta = .{} },
        .{ .method = .POST, .path = "/group/get_groups_info", .handler = group_h.handleGetGroupsInfo, .meta = .{} },
        .{ .method = .POST, .path = "/group/get_group_member_list", .handler = group_h.handleGetGroupMemberList, .meta = .{} },
        .{ .method = .POST, .path = "/group/get_group_members_info", .handler = group_h.handleGetGroupMembersInfo, .meta = .{} },
        .{ .method = .POST, .path = "/group/invite_user_to_group", .handler = group_h.handleInviteToGroup, .meta = .{} },
        .{ .method = .POST, .path = "/group/kick_group", .handler = group_h.handleKickFromGroup, .meta = .{} },
        .{ .method = .POST, .path = "/group/quit_group", .handler = group_h.handleQuitGroup, .meta = .{} },
        .{ .method = .POST, .path = "/group/dismiss_group", .handler = group_h.handleDismissGroup, .meta = .{} },
        .{ .method = .POST, .path = "/group/get_joined_group_list", .handler = group_h.handleGetJoinedGroupList, .meta = .{} },
        .{ .method = .POST, .path = "/group/transfer_group", .handler = group_h.handleTransferGroup, .meta = .{} },
        .{ .method = .POST, .path = "/group/set_group_member_info", .handler = group_h.handleSetGroupMemberInfo, .meta = .{} },
        .{ .method = .POST, .path = "/group/mute_group_member", .handler = group_h.handleMuteGroupMember, .meta = .{} },
        .{ .method = .POST, .path = "/group/cancel_mute_group_member", .handler = group_h.handleCancelMuteGroupMember, .meta = .{} },
        .{ .method = .POST, .path = "/group/mute_group", .handler = group_h.handleMuteGroup, .meta = .{} },
        .{ .method = .POST, .path = "/group/cancel_mute_group", .handler = group_h.handleCancelMuteGroup, .meta = .{} },
        .{ .method = .POST, .path = "/group/join_group", .handler = group_h.handleJoinGroup, .meta = .{} },
        .{ .method = .POST, .path = "/group/group_application_response", .handler = group_h.handleGroupApplicationResponse, .meta = .{} },
        .{ .method = .POST, .path = "/group/get_recv_group_applicationList", .handler = group_h.handleGetRecvGroupApplications, .meta = .{} },
        .{ .method = .POST, .path = "/group/get_user_req_group_applicationList", .handler = group_h.handleGetUserReqGroupApplications, .meta = .{} },
        .{ .method = .POST, .path = "/group/get_group_users_req_application_list", .handler = group_h.handleGetGroupUsersReqApplicationList, .meta = .{} },
        .{ .method = .POST, .path = "/group/get_specified_user_group_request_info", .handler = group_h.handleGetSpecifiedUserGroupRequestInfo, .meta = .{} },
        .{ .method = .POST, .path = "/group/set_group_info_ex", .handler = group_h.handleSetGroupInfoEx, .meta = .{} },
        .{ .method = .POST, .path = "/group/get_group_abstract_info", .handler = group_h.handleGetGroupAbstractInfo, .meta = .{} },
        .{ .method = .POST, .path = "/group/get_groups", .handler = group_h.handleGetGroups, .meta = .{} },
        .{ .method = .POST, .path = "/group/get_group_member_user_id", .handler = group_h.handleGetGroupMemberUserIDs, .meta = .{} },
        .{ .method = .POST, .path = "/group/get_incremental_join_groups", .handler = group_h.handleGetIncrementalJoinGroups, .meta = .{} },
        .{ .method = .POST, .path = "/group/get_incremental_group_members", .handler = group_h.handleGetIncrementalGroupMembers, .meta = .{} },
        .{ .method = .POST, .path = "/group/get_incremental_group_members_batch", .handler = group_h.handleGetIncrementalGroupMembersBatch, .meta = .{} },
        .{ .method = .POST, .path = "/group/get_full_group_member_user_ids", .handler = group_h.handleGetFullGroupMemberUserIDs, .meta = .{} },
        .{ .method = .POST, .path = "/group/get_full_join_group_ids", .handler = group_h.handleGetFullJoinGroupIDs, .meta = .{} },
        .{ .method = .POST, .path = "/group/get_group_application_unhandled_count", .handler = group_h.handleGetGroupApplicationUnheandledCount, .meta = .{} },
        .{ .method = .POST, .path = "/group/delete_group_requests_from_user", .handler = group_h.handleDeleteGroupRequestsFromUser, .meta = .{} },
        .{ .method = .POST, .path = "/group/delete_group_requests_to_group", .handler = group_h.handleDeleteGroupRequestsToGroup, .meta = .{} },
    };

    const message_routes = [_]http.RouteSpec(State){
        // Message
        .{ .method = .POST, .path = "/msg/send_msg", .handler = message_h.handleSendMessage, .meta = .{} },
        .{ .method = .POST, .path = "/msg/send_business_notification", .handler = message_h.handleSendBusinessNotification, .meta = .{} },
        .{ .method = .POST, .path = "/msg/batch_send_msg", .handler = message_h.handleBatchSendMsg, .meta = .{} },
        .{ .method = .POST, .path = "/msg/pull_msg_by_seq", .handler = message_h.handlePullMsgBySeqs, .meta = .{} },
        .{ .method = .POST, .path = "/msg/revoke_msg", .handler = message_h.handleRevokeMsg, .meta = .{} },
        .{ .method = .POST, .path = "/msg/modify_message", .handler = message_h.handleModifyMessage, .meta = .{} },
        .{ .method = .POST, .path = "/msg/delete_msgs", .handler = message_h.handleDeleteMsgs, .meta = .{} },
        .{ .method = .POST, .path = "/msg/mark_msgs_as_read", .handler = message_h.handleMarkMsgsAsRead, .meta = .{} },
        .{ .method = .POST, .path = "/msg/mark_conversation_as_read", .handler = message_h.handleMarkConversationAsRead, .meta = .{} },
        .{ .method = .POST, .path = "/msg/get_conversations_has_read_and_max_seq", .handler = message_h.handleGetConversationsHasReadAndMaxSeq, .meta = .{} },
        .{ .method = .POST, .path = "/msg/set_conversation_has_read_seq", .handler = message_h.handleSetConversationHasReadSeq, .meta = .{} },
        .{ .method = .POST, .path = "/msg/clear_conversation_msg", .handler = message_h.handleClearConversationMsg, .meta = .{} },
        .{ .method = .POST, .path = "/msg/user_clear_all_msg", .handler = message_h.handleUserClearAllMsg, .meta = .{} },
        .{ .method = .POST, .path = "/msg/delete_msg_phsical_by_seq", .handler = message_h.handleDeleteMsgPhysicalBySeq, .meta = .{} },
        .{ .method = .POST, .path = "/msg/delete_msg_physical", .handler = message_h.handleDeleteMsgPhysical, .meta = .{} },
        .{ .method = .POST, .path = "/msg/search_msg", .handler = message_h.handleSearchMsg, .meta = .{} },
        .{ .method = .POST, .path = "/msg/newest_seq", .handler = message_h.handleGetSeq, .meta = .{} },
        .{ .method = .POST, .path = "/msg/check_msg_is_send_success", .handler = message_h.handleCheckMsgIsSendSuccess, .meta = .{} },
        .{ .method = .POST, .path = "/msg/get_server_time", .handler = message_h.handleGetServerTime, .meta = .{ .auth = .public } },
        .{ .method = .POST, .path = "/msg/mark_group_message_read", .handler = message_h.handleMarkGroupMessageRead, .meta = .{} },
        .{ .method = .POST, .path = "/msg/get_group_message_read_num", .handler = message_h.handleGetGroupMessageReadNum, .meta = .{} },
        .{ .method = .POST, .path = "/msg/get_group_message_has_read", .handler = message_h.handleGetGroupMessageHasRead, .meta = .{} },
        .{ .method = .POST, .path = "/msg/mark_user_message_read", .handler = message_h.handleMarkUserMessageRead, .meta = .{} },
        .{ .method = .POST, .path = "/msg/mark_conversation_read", .handler = message_h.handleMarkConversationRead, .meta = .{} },
    };

    const conversation_routes = [_]http.RouteSpec(State){
        // Conversation
        .{ .method = .POST, .path = "/conversation/get_sorted_conversation_list", .handler = conversation_h.handleGetSortedConversationList, .meta = .{} },
        .{ .method = .POST, .path = "/conversation/get_all_conversations", .handler = conversation_h.handleGetAllConversations, .meta = .{} },
        .{ .method = .POST, .path = "/conversation/get_conversation", .handler = conversation_h.handleGetConversation, .meta = .{} },
        .{ .method = .POST, .path = "/conversation/get_conversations", .handler = conversation_h.handleGetConversations, .meta = .{} },
        .{ .method = .POST, .path = "/conversation/set_conversations", .handler = conversation_h.handleSetConversations, .meta = .{} },
        .{ .method = .POST, .path = "/conversation/get_conversation_offline_push_user_ids", .handler = conversation_h.handleGetConversationOfflinePushUserIDs, .meta = .{} },
        .{ .method = .POST, .path = "/conversation/get_full_conversation_ids", .handler = conversation_h.handleGetFullConversationIDs, .meta = .{} },
        .{ .method = .POST, .path = "/conversation/get_incremental_conversations", .handler = conversation_h.handleGetIncrementalConversations, .meta = .{} },
        .{ .method = .POST, .path = "/conversation/get_owner_conversation", .handler = conversation_h.handleGetOwnerConversation, .meta = .{} },
        .{ .method = .POST, .path = "/conversation/get_not_notify_conversation_ids", .handler = conversation_h.handleGetNotNotifyConversationIDs, .meta = .{} },
        .{ .method = .POST, .path = "/conversation/get_pinned_conversation_ids", .handler = conversation_h.handleGetPinnedConversationIDs, .meta = .{} },
    };

    const encryption_routes = [_]http.RouteSpec(State){
        // Encryption
        .{ .method = .POST, .path = "/encryption/get_encryption_key", .handler = encryption_h.handleGetEncryptionKey, .meta = .{} },
        .{ .method = .POST, .path = "/encryption/gen_encryption_key", .handler = encryption_h.handleGenEncryptionKey, .meta = .{} },
    };

    const office_routes = [_]http.RouteSpec(State){
        // Office
        .{ .method = .POST, .path = "/office/work_moment/add", .handler = office_h.handleCreateWorkMoment, .meta = .{} },
        .{ .method = .POST, .path = "/office/work_moment/del", .handler = office_h.handleDeleteWorkMoment, .meta = .{} },
        .{ .method = .POST, .path = "/office/work_moment/get", .handler = office_h.handleGetWorkMoment, .meta = .{} },
        .{ .method = .POST, .path = "/office/work_moment/find/recv", .handler = office_h.handleGetRecvWorkMoments, .meta = .{} },
        .{ .method = .POST, .path = "/office/work_moment/find/send", .handler = office_h.handleGetSendWorkMoments, .meta = .{} },
        .{ .method = .POST, .path = "/office/work_moment/like", .handler = office_h.handleLikeWorkMoment, .meta = .{} },
        .{ .method = .POST, .path = "/office/work_moment/comment/add", .handler = office_h.handleAddComment, .meta = .{} },
        .{ .method = .POST, .path = "/office/work_moment/comment/del", .handler = office_h.handleDeleteComment, .meta = .{} },
        .{ .method = .POST, .path = "/office/work_moment/logs", .handler = office_h.handleGetWorkMomentLogs, .meta = .{} },
        .{ .method = .POST, .path = "/office/work_moment/unread/clear", .handler = office_h.handleClearUnreadWorkMoments, .meta = .{} },
        .{ .method = .POST, .path = "/office/work_moment/unread/count", .handler = office_h.handleGetUnreadWorkMomentsCount, .meta = .{} },
        .{ .method = .POST, .path = "/office/tag/find/user", .handler = office_h.handleGetUserTags, .meta = .{} },
        .{ .method = .POST, .path = "/office/tag/add", .handler = office_h.handleCreateTag, .meta = .{} },
        .{ .method = .POST, .path = "/office/tag/del", .handler = office_h.handleDeleteTag, .meta = .{} },
        .{ .method = .POST, .path = "/office/tag/set", .handler = office_h.handleUpdateTag, .meta = .{} },
    };

    const collect_routes = [_]http.RouteSpec(State){
        // Collect / Favorite
        .{ .method = .POST, .path = "/collect/add", .handler = office_h.handleAddFavoriteMessage, .meta = .{} },
        .{ .method = .POST, .path = "/collect/del", .handler = office_h.handleRemoveFavoriteMessage, .meta = .{} },
        .{ .method = .POST, .path = "/collect/list", .handler = office_h.handleGetFavoriteMessages, .meta = .{} },
    };

    const client_config_routes = [_]http.RouteSpec(State){
        // Client config
        .{ .method = .POST, .path = "/client_config/get", .handler = office_h.handleGetClientConfig, .meta = .{} },
    };

    const organization_routes = [_]http.RouteSpec(State){
        // Organization
        .{ .method = .POST, .path = "/organization/info", .handler = organization_h.handleGetOrganization, .meta = .{} },
        .{ .method = .POST, .path = "/organization/department/find", .handler = organization_h.handleGetDepartments, .meta = .{} },
        .{ .method = .POST, .path = "/organization/user/department", .handler = organization_h.handleGetUsersInDepartments, .meta = .{} },
        .{ .method = .POST, .path = "/organization/department/child", .handler = organization_h.handleGetSubDepartmentsAndMembers, .meta = .{} },
        .{ .method = .POST, .path = "/user/search/organization/full", .handler = organization_h.handleSearchOrganizationUsers, .meta = .{} },
    };

    const third_routes = [_]http.RouteSpec(State){
        // Third-party
        .{ .method = .POST, .path = "/third/fcm_update_token", .handler = third_h.handleFCMUpdateToken, .meta = .{} },
        .{ .method = .POST, .path = "/third/set_app_badge", .handler = third_h.handleSetAppBadge, .meta = .{} },
        .{ .method = .POST, .path = "/third/logs/upload", .handler = third_h.handleUploadLogs, .meta = .{} },
        .{ .method = .POST, .path = "/third/logs/search", .handler = third_h.handleSearchLogs, .meta = .{} },
        .{ .method = .POST, .path = "/object/part_limit", .handler = third_h.handleObjectPartLimit, .meta = .{} },
        .{ .method = .POST, .path = "/object/auth_sign", .handler = third_h.handleObjectAuthSign, .meta = .{} },
        .{ .method = .POST, .path = "/object/access_url", .handler = third_h.handleObjectAccessUrl, .meta = .{} },
    };

    const statistics_routes = [_]http.RouteSpec(State){
        // Statistics
        .{ .method = .POST, .path = "/statistics/user/register", .handler = statistics_h.handleStatisticsUserRegister, .meta = .{} },
        .{ .method = .POST, .path = "/statistics/user/active", .handler = statistics_h.handleStatisticsUserActive, .meta = .{} },
        .{ .method = .POST, .path = "/statistics/group/create", .handler = statistics_h.handleStatisticsGroupCreate, .meta = .{} },
        .{ .method = .POST, .path = "/statistics/group/active", .handler = statistics_h.handleStatisticsGroupActive, .meta = .{} },
    };

    const rtc_routes = [_]http.RouteSpec(State){
        // RTC meetings
        .{ .method = .POST, .path = "/rtc-meeting/create", .handler = rtc_h.handleRTCMeetingCreate, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/join", .handler = rtc_h.handleRTCMeetingJoin, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/leave", .handler = rtc_h.handleRTCMeetingLeave, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/close", .handler = rtc_h.handleRTCMeetingClose, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/info", .handler = rtc_h.handleRTCMeetingInfo, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/list", .handler = rtc_h.handleRTCMeetingList, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/mute", .handler = rtc_h.handleRTCMeetingMute, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/unmute", .handler = rtc_h.handleRTCMeetingUnmute, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/video_on", .handler = rtc_h.handleRTCMeetingVideoOn, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/video_off", .handler = rtc_h.handleRTCMeetingVideoOff, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/kick", .handler = rtc_h.handleRTCMeetingKick, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/transfer_host", .handler = rtc_h.handleRTCMeetingTransferHost, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/set_layout", .handler = rtc_h.handleRTCMeetingSetLayout, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/record/start", .handler = rtc_h.handleRTCMeetingRecordStart, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/record/stop", .handler = rtc_h.handleRTCMeetingRecordStop, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/signal", .handler = rtc_h.handleRTCMeetingSignal, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/invite", .handler = rtc_h.handleRTCMeetingInvite, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/reject", .handler = rtc_h.handleRTCMeetingReject, .meta = .{} },
        .{ .method = .POST, .path = "/rtc-meeting/accept", .handler = rtc_h.handleRTCMeetingAccept, .meta = .{} },
    };

    const metrics_routes = [_]http.RouteSpec(State){
        // Metrics
        .{ .method = .GET, .path = "/metrics", .handler = health_h.handlePrometheusMetrics, .meta = .{ .auth = .public } },
    };

    const admin_routes = [_]http.RouteSpec(State){
        .{ .method = .POST, .path = "/admin/login", .handler = admin_h.handleAdminLogin, .meta = .{} },
        .{ .method = .GET, .path = "/user/allow_register", .handler = admin_h.handleGetAllowRegister, .meta = .{} },
        .{ .method = .PUT, .path = "/user/allow_register", .handler = admin_h.handleSetAllowRegister, .meta = .{} },
        .{ .method = .POST, .path = "/block/add", .handler = admin_h.handleBlockAdd, .meta = .{} },
        .{ .method = .POST, .path = "/block/del", .handler = admin_h.handleBlockDel, .meta = .{} },
        .{ .method = .POST, .path = "/block/search", .handler = admin_h.handleBlockSearch, .meta = .{} },
    };
    const jssdk_routes = [_]http.RouteSpec(State){
        // JSSdk (web session aggregation)
        .{ .method = .POST, .path = "/jssdk/get_conversations", .handler = jssdk_h.handleJssdkGetConversations, .meta = .{} },
        .{ .method = .POST, .path = "/jssdk/get_active_conversations", .handler = jssdk_h.handleJssdkGetActiveConversations, .meta = .{} },
    };

    pub const routes = auth_routes ++ account_routes ++ health_routes ++ user_routes ++ friend_routes ++ group_routes ++ message_routes ++ conversation_routes ++ encryption_routes ++ office_routes ++ collect_routes ++ client_config_routes ++ organization_routes ++ third_routes ++ statistics_routes ++ rtc_routes ++ metrics_routes ++ jssdk_routes ++ admin_routes;
};
