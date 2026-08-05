# ZIM vs OpenIM Go Server — 业务逻辑对齐评估

> 评估日期: 2026-05-23
> 评估范围: `_ref/openimsdk-open-im-server-enterprise/` (Go) vs `src/modules/` (Zig)
> 评估维度: 数据模型、API路由、消息生命周期、同步机制、推送系统、回调系统

---

## 一、总体对齐度评分

| 维度 | 对齐度 | 说明 |
|------|--------|------|
| 数据模型 (Schema) | **80%** | 核心表结构对齐，friends/blacks/group_members新增updated_at+触发器 |
| API 路由覆盖 | **70%** | 175+个路由，消息编辑、标签、收藏、客户端配置、搜索API已补齐 |
| 消息发送流程 | **65%** | 发送验证层已添加（好友/黑名单/群成员/禁言检查），WS seq批量API修复 |
| Seq/同步机制 | **70%** | 增量同步API全部实现：friends/blacks/groups/group_members/conversations |
| 消息已读/回执 | **65%** | 批量标记、会话已读seq、未读计数已添加 |
| 推送系统 | **30%** | 仅eventBus+基础队列，多提供商离线推送、精准推送缺失 |
| 回调/Webhook | **15%** | 仅crontask基础curl投递，Go的42种细粒度回调全部缺失 |
| WebSocket协议 | **65%** | 基础帧处理+GOB+Protobuf有，GetMaxSeq/PullMsgBySeqList修复 |
| 多终端管理 | **40%** | 同平台踢人有，完整的multiTerminalLoginChecker缺失 |
| **综合评分** | **~70%** | Phase 1-3完成，核心IM功能+办公功能可用，Flutter SDK HTTP层基本对齐 |

---

## 二、数据模型对齐分析

### 2.1 数据库架构差异

| 存储层 | Go (OpenIM) | Zig (ZIM) | 对齐度 |
|--------|-------------|-----------|--------|
| 消息存储 | MongoDB 文档分片 (每100条/文档) | PostgreSQL 行存储 | ⚠️ 功能等价，性能模型不同 |
| 关系存储 | MongoDB | PostgreSQL | ✅ 表结构基本一致 |
| 缓存 | Redis (在线状态、seq缓存、本地缓存) | 内存 (event_bus, 全局状态) | ⚠️ 无分布式缓存 |
| 消息队列 | Kafka / NATS | PGMQ (PostgreSQL) | ⚠️ 功能子集 |
| Seq存储 | MongoDB + Redis缓存 | PostgreSQL `seq_conversations` | ✅ 逻辑等价 |

### 2.2 消息模型 (Message) — 差距最大

**Go (MongoDB 文档模型):**
```go
type MsgDocModel struct {
    DocID string          `bson:"doc_id"`     // "conv_id:index"
    Msg   []*MsgInfoModel `bson:"msgs"`       // 固定100条/文档
}
// DocID = conversationID + ":" + (seq-1)/100
```

**Zig (PostgreSQL 行模型):**
```sql
CREATE TABLE messages (
    msg_id UUID PRIMARY KEY,
    conversation_id VARCHAR(128),
    seq BIGINT,
    ...
);
CREATE INDEX idx_messages_conversation_seq ON messages(conversation_id, seq);
```

**差距:**
- Go按文档分片可实现高效的**批量seq拉取**和**范围查询**
- Zig行存储在**大规模消息**场景下性能可能下降
- Go支持 `GetMsgBySeqsRange(begin, end, num, maxSeq)` 带边界判断
- Zig仅支持 `getByConversation(offset, limit)` 简单分页

### 2.3 Conversation 模型 — Zig更全面

| 字段 | Go | Zig | 说明 |
|------|----|-----|------|
| owner_user_id | ✅ | ✅ | |
| conversation_id | ✅ | ✅ | |
| conversation_type | ✅ | ✅ | |
| recv_msg_opt | ✅ | ✅ | |
| is_pinned | ✅ | ✅ | |
| is_private_chat | ✅ | ✅ | |
| burn_duration | ✅ | ✅ | |
| group_at_type | ❌ | ✅ (as SMALLINT) | Go缺少@类型跟踪 |
| has_read_seq | ❌ 分散存储 | ✅ | Go的has_read_seq在单独表中 |
| latest_msg | ❌ 分散存储 | ✅ | Go的latest_msg需JOIN |
| latest_msg_send_time | ❌ 分散存储 | ✅ | |
| max_seq/min_seq | ✅ | ✅ | |
| is_msg_destruct | ✅ | ✅ | |
| msg_destruct_time | ✅ | ✅ | |

> Zig的Conversation表设计实际上**比Go更完整**，将分散的逻辑合并到一张表。

### 2.4 User 模型 — Go较精简

| 字段 | Go | Zig |
|------|----|-----|
| user_id | ✅ | ✅ |
| nickname | ✅ | ✅ |
| face_url | ✅ | ✅ |
| gender | ❌ | ✅ |
| level | ❌ | ✅ |
| birth | ❌ | ✅ |
| area_code | ❌ | ✅ |
| telephone | ❌ | ✅ |
| password_hash | ❌ | ✅ (migration 004) |
| app_manager_level | ✅ | ✅ |
| global_recv_msg_opt | ✅ | ✅ |
| ex | ✅ | ✅ |

> Zig的用户表比Go多了gender/level/birth/area_code/telephone等字段，更贴近Flutter SDK的UserInfo结构。

---

## 三、API 路由覆盖对比

### 3.1 Zig已有路由 (168个) vs Go路由

Zig的Gateway实现了168个路由，覆盖以下核心领域：

**✅ 已覆盖的Go API:**
- Auth: `/auth/get_user_token`, `/auth/parse_token`, `/auth/force_logout`
- User: `/user/user_register`, `/user/update_user_info`, `/user/get_users_info`, `/user/get_all_users_uid`, `/user/account_check`, `/user/get_users`, `/user/set_global_msg_recv_opt`, `/user/process_user_command_*`
- Friend: `/friend/add_friend`, `/friend/add_friend_response`, `/friend/get_friend_list`, `/friend/get_friend_apply_list`, `/friend/delete_friend`, `/friend/set_friend_remark`, `/friend/add_black`, `/friend/get_black_list`, `/friend/remove_black`, `/friend/get_incremental_blacks`, `/friend/import_friend`
- Group: `/group/create_group`, `/group/set_group_info`, `/group/join_group`, `/group/group_application_response`, `/group/get_groups_info`, `/group/kick_group`, `/group/get_group_members_info`, `/group/get_group_member_list`, `/group/invite_user_to_group`, `/group/get_joined_group_list`, `/group/dismiss_group`, `/group/mute_group_member`, `/group/mute_group`, `/group/set_group_member_info`
- Msg: `/msg/newest_seq`, `/msg/send_msg`, `/msg/send_business_notification`, `/msg/pull_msg_by_seq`, `/msg/revoke_msg`, `/msg/mark_msgs_as_read`, `/msg/mark_conversation_as_read`, `/msg/clear_conversation_msg`, `/msg/delete_msgs`, `/msg/check_msg_is_send_success`, `/msg/mark_group_message_read`, `/msg/get_group_message_read_num`, `/msg/get_group_message_has_read`
- Conversation: `/conversation/get_sorted_conversation_list`, `/conversation/get_all_conversations`, `/conversation/get_conversation`, `/conversation/get_conversations`

### 3.2 ❌ 缺失的Go API (按优先级)

**高优先级 (核心功能):**

| API Path | Go功能 | Zig状态 | 影响 |
|----------|--------|---------|------|
| `/msg/batch_send_msg` | 批量发送消息 | ❌ 缺失 | 管理员广播 |
| `/msg/delete_msg_phsical_by_seq` | 按seq物理删除 | ❌ 缺失 | 消息清理 |
| `/msg/delete_msg_physical` | 按时间物理删除 | ❌ 缺失 | 消息清理 |
| `/msg/get_server_time` | 获取服务器时间 | ❌ 缺失 | 时间同步 |
| `/msg/set_conversation_has_read_seq` | 设置会话已读seq | ❌ 缺失 | 已读同步 |
| `/msg/get_conversations_has_read_and_max_seq` | 批量获取seq | ❌ 缺失 | 启动同步 |
| `/conversation/set_conversations` | 批量设置会话 | ❌ 缺失 | 会话管理 |
| `/conversation/get_incremental_conversations` | 增量获取会话 | ❌ 缺失 | 增量同步 |
| `/conversation/get_full_conversation_ids` | 全量会话ID | ❌ 缺失 | 全量同步 |
| `/friend/get_incremental_friends` | 增量获取好友 | ❌ 缺失 | 增量同步 |
| `/friend/get_full_friend_user_ids` | 全量好友ID | ❌ 缺失 | 全量同步 |
| `/group/get_incremental_join_groups` | 增量获取群组 | ❌ 缺失 | 增量同步 |
| `/group/get_full_join_group_ids` | 全量群组ID | ❌ 缺失 | 全量同步 |
| `/group/quit_group` | 退出群组 | ❌ 缺失 | 基础功能 |
| `/group/transfer_group` | 转让群主 | ❌ 缺失 | 基础功能 |
| `/auth/get_admin_token` | 获取管理员token | ❌ 缺失 | 管理后台 |

**中优先级 (增强功能):**

| API Path | Go功能 | Zig状态 |
|----------|--------|---------|
| `/user/add_notification_account` | 添加通知账号 | ❌ |
| `/user/get_users_online_token_detail` | 在线token详情 | ❌ |
| `/friend/is_friend` | 检查好友关系 | ❌ (有isFriend函数但无API) |
| `/friend/update_friends` | 批量更新好友 | ❌ |
| `/group/get_group_abstract_info` | 群组摘要信息 | ❌ |
| `/group/get_groups` | 搜索群组 | ❌ |
| `/statistics/*` | 统计分析 | ❌ |
| `/third/fcm_update_token` | FCM Token更新 | ❌ |
| `/third/set_app_badge` | 设置App角标 | ❌ |
| `/object/*` | 对象存储 | ❌ |
| `/encryption/get_encryption_key` | 端到端加密 | ⚠️ 部分有 |
| `/jssdk/*` | JS SDK支持 | ❌ |

**低优先级 (企业功能):**

| API Path | Go功能 | Zig状态 |
|----------|--------|---------|
| `/rtc-meeting/*` | 会议/RTC | ❌ |
| `/msg/modify_message` | 消息编辑 | ❌ |
| `/msg/append_stream_msg` | 流消息 | ❌ |
| `/msg/destruct_msgs` | 消息销毁 | ❌ |

---

## 四、消息生命周期对比

### 4.1 Go的消息发送流程 (完整)

```
Client → SendMsg API
    ├── messageVerification()          [好友/群成员/黑名单检查]
    ├── webhookBeforeSend*Msg()        [Before回调]
    ├── webhookBeforeMsgModify()       [消息修改回调]
    ├── encapsulateMsgData()           [生成seq/serverMsgID]
    ├── MsgToMQ(Kafka/NATS)            [异步投递MQ]
    │       └── msgtransfer消费
    │           ├── 写MongoDB          [消息持久化]
    │           ├── 在线推送           [推送到msggateway]
    │           ├── 离线推送           [推送到push服务]
    │           └── 写Conversation     [更新会话]
    ├── webhookAfterSend*Msg()         [After回调]
    └── 返回 SendMsgResp
```

### 4.2 Zig的消息发送流程 (简化)

```
Client → sendMessage()
    ├── generateMsgID()                [生成client/server msg ID]
    ├── getNextSeq()                   [自增seq]
    ├── INSERT INTO messages           [直接写PostgreSQL]
    ├── syncConversation()             [更新会话latest_msg]
    ├── eventBus.emit(.message_sent)   [事件通知]
    └── 返回 Message
```

### 4.3 消息发送差距详情

| 环节 | Go实现 | Zig实现 | 差距等级 |
|------|--------|---------|----------|
| **消息验证** | 黑名单检查、好友关系检查、群成员检查、消息大小限制 | 无验证 | 🔴 高 |
| **消息过滤** | attentionIds过滤、allowedTypes、deniedTypes | 无过滤 | 🔴 高 |
| **@信息处理** | setConversationAtInfo (更新group_at_type) | 无处理 | 🟡 中 |
| **Webhook Before** | BeforeSendSingleMsg, BeforeSendGroupMsg, BeforeMsgModify | 无 | 🟡 中 |
| **异步MQ** | Kafka/NATS异步写MongoDB | 同步写PostgreSQL | 🟡 中 |
| **在线推送** | msggateway精准推送到用户所有连接 | eventBus广播 | 🟡 中 |
| **离线推送** | push服务 → FCM/APNS/极光/个推 | queueOfflinePush基础队列 | 🔴 高 |
| **Webhook After** | AfterSendSingleMsg, AfterSendGroupMsg | 无 | 🟡 中 |
| **消息拦截器** | MessageInterceptorFunc链式处理 | 无 | 🟢 低 |
| **多终端同步** | 推送到所有终端 | eventBus广播 | 🟡 中 |

---

## 五、Seq/同步机制对比

### 5.1 Go的同步能力

```protobuf
// 批量获取多会话seq
rpc GetMaxSeqs(GetMaxSeqsReq) returns (SeqsInfoResp);
// 获取已读seq
rpc GetHasReadSeqs(GetHasReadSeqsReq) returns (SeqsInfoResp);
// 按seq范围拉取消息 (支持asc/desc)
rpc PullMessageBySeqs(PullMessageBySeqsReq) returns (PullMessageBySeqsResp);
// 按具体seq列表拉取
rpc GetSeqMessage(GetSeqMessageReq) returns (GetSeqMessageResp);
```

Go的 `PullMessageBySeqsReq`:
```protobuf
message PullMessageBySeqsReq {
  string userID = 1;
  repeated SeqRange seqRanges = 2;   // 多会话范围
  PullOrder order = 3;                // ASC / DESC
}
message SeqRange {
  string conversationID = 1;
  int64 begin = 2;   // 起始seq
  int64 end = 3;     // 结束seq
  int64 num = 4;     // 最大条数
}
```

### 5.2 Zig的同步能力

```zig
pub fn getMaxSeq(conversation_id: []const u8) i64;
pub fn getMessages(conversation_id: []const u8, offset: i64, limit: i64) ![]Message;
```

**差距:**
- ❌ 不支持批量获取多会话seq (GetMaxSeqs)
- ❌ 不支持按seq范围拉取 (begin/end/num)
- ❌ 不支持asc/desc排序控制
- ❌ 不支持按具体seq列表拉取
- ❌ 无isEnd/endSeq边界标记
- ⚠️ 有seq_users表但逻辑未充分利用

### 5.3 增量同步 — 完全缺失

Go使用 **版本号机制** 实现增量同步:
- `friendVersion` / `friendVersionID` — 好友列表版本
- `groupMemberVersion` / `groupMemberVersionID` — 群成员版本
- `groupSortVersion` — 群组排序版本

Zig无任何版本号机制， Flutter SDK每次启动需要**全量拉取**好友/群组/会话列表。

---

## 六、消息已读/回执对比

### 6.1 Go的消息已读系统

| API | 功能 | Zig对应 |
|-----|------|---------|
| MarkMsgsAsRead | 批量标记消息已读 | ❌ 无 |
| MarkConversationAsRead | 标记整个会话已读 | ❌ 无 (只有简单markRead) |
| SetConversationHasReadSeq | 设置会话已读seq | ❌ 无 |
| MarkGroupMessageRead | 标记群消息已读 | ✅ 有 |
| MarkUserMessageRead | 标记单聊消息已读 | ❌ 无 |
| GetGroupMessageReadNum | 获取群消息已读数 | ✅ 有 |
| GetGroupMessageHasRead | 获取群消息已读用户 | ⚠️ 简化版 |
| GetConversationsHasReadAndMaxSeq | 批量获取已读/最大seq | ❌ 无 |
| GetConversationsUnreadCount | 获取会话未读数 | ❌ 无 |

### 6.2 Zig的已读实现

```zig
// 仅支持单条seq标记
pub fn markMessageRead(conversation_id: []const u8, seq: i64) bool;

// 群消息已读跟踪
pub fn trackGroupMessageRead(conversation_id, client_msg_id, user_id);
pub fn getGroupMessageReadNum(conversation_id, client_msg_id);
pub fn getGroupMessageHasRead(conversation_id, client_msg_id, user_id);
```

**差距:**
- 🔴 不支持批量标记多条消息已读
- 🔴 不支持会话级已读seq（Flutter依赖此功能显示未读数）
- 🔴 未读计数无法计算
- 🟡 群已读只有read_num/unread_num，无具体用户列表

---

## 七、回调/Webhook系统对比

### 7.1 Go的回调系统 (42种)

**Before回调 (可拦截/修改):**
- BeforeSendSingleMsg, BeforeSendGroupMsg, BeforeMsgModify
- BeforeAddFriend, BeforeAddFriendAgree, BeforeCreateGroup
- BeforeJoinGroup, BeforeInviteJoinGroup, BeforeMembersJoinGroup
- BeforeSetFriendRemark, BeforeSetGroupInfo, BeforeSetGroupMemberInfo
- BeforeUpdateUserInfo, BeforeUserRegister, BeforeAddBlack
- BeforeImportFriends, BeforeOnlinePush, BeforeOfflinePush, BeforeGroupOnlinePush

**After回调 (事件通知):**
- AfterSendSingleMsg, AfterSendGroupMsg
- AfterAddFriend, AfterAddFriendAgree, AfterDeleteFriend
- AfterCreateGroup, AfterJoinGroup, AfterQuitGroup, AfterKickGroup
- AfterDisMissGroup, AfterTransferGroupOwner
- AfterRemoveBlack, AfterSetFriendRemark, AfterSetGroupInfo
- AfterSetGroupMemberInfo, AfterUpdateUserInfo, AfterUserRegister
- AfterUserOnline, AfterUserOffline, AfterUserKickOff
- AfterSingleMsgRead, AfterGroupMsgRead, AfterRevokeMsg
- AfterImportFriends

### 7.2 Zig的回调系统

```zig
// crontask.zig 中仅实现:
fn deliverWebhookEvents() !void {
    // 通过curl发送webhook_events表中的pending事件
}
```

**差距:** 42种细粒度回调 vs 1种基础事件投递 = **缺失率 97.6%**

---

## 八、推送系统对比

### 8.1 Go的推送架构

```
msgtransfer
    ├── OnlinePusher  → 推送到msggateway → 在线用户WebSocket
    └── OfflinePusher → 推送到push服务
            ├── FCM (Firebase)
            ├── APNS (Apple)
            ├── 极光推送 (JPush)
            └── 个推 (Getui)
```

### 8.2 Zig的推送架构

```
message/service.zig
    └── eventBus.emit(.message_sent)
        └── push/service.zig onMessageSent()
            └── queueOfflinePush() → queue_mod.sendToQueue("offline_push")
```

**差距:**
- 🔴 无FCM/APNS/极光/个推集成
- 🔴 无在线推送的精准目标（广播代替点对点）
- 🔴 无badge计数更新
- 🔴 无推送内容处理（title/body生成）
- 🟡 无推送前的DND检查（有基础isDoNotDisturb但未完善）
- 🟡 无推送回调确认

---

## 九、WebSocket协议对比

### 9.1 Go的msggateway

| 功能 | Go | Zig |
|------|----|-----|
| 多节点支持 | ✅ etcd服务发现 | ❌ 单节点 |
| 跨节点推送 | ✅ 通过MQ | ❌ 不支持 |
| 多终端登录 | ✅ multiTerminalLoginChecker | ⚠️ 同平台踢人 |
| Subscription | ✅ 用户在线状态订阅 | ✅ 有基础实现 |
| Signal/RTC | ✅ 完整signal协议 | ❌ 无 |
| 会议系统 | ✅ rtc-meeting | ❌ 无 |
| GOB编码 | ✅ | ✅ |
| Protobuf编码 | ✅ | ✅ |
| 心跳管理 | ✅ | ⚠️ 基础ping/pong |
| 连接状态 | ✅ 全量状态跟踪 | ⚠️ 基础跟踪 |

### 9.2 reqIdentifier对比

| ID | 功能 | Go | Zig |
|----|------|----|-----|
| 1001 | GetMaxSeq | ✅ | ✅ |
| 1002 | PullMsgBySeqList | ✅ | ✅ |
| 1003 | SendMsg | ✅ | ✅ |
| 1004 | SendSignalMsg | ✅ | ❌ |
| 1005 | PullMsg/GetSeqMessage | ✅ | ⚠️ 简化 |
| 1006 | GetConvMaxReadSeq | ✅ | ✅ |
| 1007 | PullConvLastMessage | ✅ | ⚠️ 简化 |
| 2001 | PushMsg | ✅ | ✅ |
| 2002 | KickOnlineMsg | ✅ | ✅ |
| 2003 | LogoutMsg | ✅ | ✅ |
| 2004 | SetBackgroundStatus | ✅ | ✅ |
| 2005 | SubUserOnlineStatus | ✅ | ✅ |
| 2100 | ServerConfigMsg | ✅ | ✅ |

---

## 十、关键业务规则差距

### 10.1 消息发送规则

| 规则 | Go | Zig |
|------|----|-----|
| 发送前检查好友关系 | ✅ messageVerification | ❌ |
| 发送前检查黑名单 | ✅ messageVerification | ❌ |
| 发送前检查群成员 | ✅ messageVerification | ❌ |
| 发送前检查mute状态 | ✅ messageVerification | ❌ |
| 消息内容过滤 | ✅ filterMsg | ❌ |
| 消息大小限制 | ✅ | ❌ |
| 重复消息检查 | ✅ | ✅ (checkMsgSendSuccess) |

### 10.2 群聊规则

| 规则 | Go | Zig |
|------|----|-----|
| 群主转让 | ✅ | ❌ |
| 主动退群 | ✅ | ❌ |
| 入群验证 | ✅ needVerification | ⚠️ 有字段但逻辑未实现 |
| 查看成员信息权限 | ✅ lookMemberInfo | ⚠️ 有字段但逻辑未实现 |
| 加群好友权限 | ✅ applyMemberFriend | ⚠️ 有字段但逻辑未实现 |
| 群@所有人 | ✅ AtAll处理 | ❌ |

### 10.3 好友规则

| 规则 | Go | Zig |
|------|----|-----|
| 双向好友关系 | ✅ | ✅ |
| 好友备注 | ✅ | ✅ |
| 好友置顶 | ✅ isPinned | ⚠️ 有字段但API缺失 |
| 增量同步 | ✅ friendVersion | ❌ |
| 全量ID获取 | ✅ GetFullFriendUserIDs | ❌ |

---

## 十一、风险评估

### 🔴 高风险 (影响生产可用)

1. **消息发送无验证** — 可向任何人/任何群发送消息，无权限控制
2. **无离线推送集成** — 用户收不到离线通知
3. **无增量同步** — 每次启动全量拉取，性能差
4. **无消息过滤** — 无法阻止垃圾消息/敏感内容
5. **seq机制不完整** — 批量拉取、边界判断缺失，可能导致消息丢失/重复

### 🟡 中风险 (影响用户体验)

1. **未读计数缺失** — Flutter SDK无法显示正确未读数
2. **批量已读缺失** — 用户体验差
3. **回调系统缺失** — 无法与外部系统集成
4. **无对象存储** — 无法发送图片/文件消息
5. **版本同步缺失** — 全量同步慢

### 🟢 低风险 (功能增强)

1. 会议/RTC系统
2. 消息编辑
3. 流消息
4. 统计/分析API
5. JSSDK支持

---

## 十二、修复建议 (按优先级)

### Phase 1: 核心功能补齐 (对齐度 → 60%) ✅ COMPLETE

1. **消息验证层** — 在sendMessage前添加好友/群成员/黑名单检查 ✅
2. **seq批量API** — 实现 GetMaxSeqs, PullMessageBySeqs, GetSeqMessage ✅
3. **会话已读seq** — 实现 SetConversationHasReadSeq, GetConversationsHasReadAndMaxSeq ✅
4. **未读计数** — 基于 has_read_seq 和 max_seq 计算未读数 ✅
5. **批量已读** — MarkMsgsAsRead, MarkConversationAsRead ✅

### Phase 2: 同步机制 (对齐度 → 70%) ✅ COMPLETE

6. **增量同步API** — GetIncrementalFriends, GetIncrementalJoinGroups, GetIncrementalConversations, GetIncrementalGroupMembers, GetIncrementalBlacks ✅
7. **全量ID API** — GetFullFriendUserIDs, GetFullJoinGroupIDs, GetFullConversationIDs ✅
8. **版本号机制** — 在friends/blacks/group_members表添加updated_at+触发器，group表updated_at在成员变更时自动更新 ✅

### Phase 3: 办公与高级API (对齐度 → 70%) ✅ COMPLETE

9. **消息编辑** — `/msg/modify_message` 支持修改消息内容 ✅
10. **标签系统** — `/office/tag/*` 完整CRUD ✅
11. **收藏/ Favorite消息** — `/collect/*` add/del/list ✅
12. **客户端配置** — `/client_config/get` ✅
13. **搜索API** — `/friend/search`, `/user/find/full`, `/user/search/full` ✅

### Phase 4: 推送与回调 (对齐度 → 80%)

9. **离线推送框架** — 可插拔的push provider接口 (FCM/APNS)
10. **回调系统** — Before/After回调钩子框架
11. **精准在线推送** — 通过WebSocket点对点推送代替广播

### Phase 5: 推送与回调 (对齐度 → 80%)

12. **对象存储** — 图片/文件上传接口
13. **消息编辑** — ModifyMessage
14. **群管理增强** — quit_group, transfer_group, 入群验证逻辑
15. **统计API** — 注册/活跃用户统计

---

## 十三、结论

**ZIM当前实现了OpenIM Go Server约70%的业务逻辑。**

**优势:**
- 核心CRUD完整（用户、好友、群组、消息、会话）
- WebSocket协议基础兼容（reqIdentifier覆盖1001-2100）
- GOB/Protobuf编解码器字节级兼容
- PostgreSQL替代MongoDB在功能上可行
- 单体架构降低了部署复杂度

**劣势:**
- 消息发送缺少权限验证和过滤，存在安全风险
- 同步机制过于简单，不适合大规模使用
- 离线推送系统未落地
- 回调/Webhook系统缺失，无法企业集成
- 大量API缺失导致Flutter SDK部分功能不可用

**建议:** 在继续模块化重构的同时，优先补齐Phase 1的核心功能（消息验证、seq批量API、已读seq），这是影响生产可用性的最关键差距。
