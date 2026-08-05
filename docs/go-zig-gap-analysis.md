# Go 参考代码 vs Zig 实现 — 功能缺失分析报告

> 基于对 `_ref/openimsdk-open-im-server-enterprise` (Go) 和 `src/` (Zig) 的深入代码对比
> 生成时间: 2026-05-21

---

## 1. 核心模块对比

### Go (OpenIM Enterprise) — 10+ 微服务
| 服务 | 说明 |
|------|------|
| `openim-api` | HTTP API 网关 |
| `openim-msggateway` | WebSocket 长连接网关 |
| `openim-msgtransfer` | 消息流转服务 (Kafka → Redis → MongoDB → Push) |
| `openim-push` | 推送服务 (在线/离线推送) |
| `openim-rpc-auth` | 认证 RPC |
| `openim-rpc-user` | 用户 RPC |
| `openim-rpc-friend` | 好友 RPC |
| `openim-rpc-group` | 群组 RPC |
| `openim-rpc-msg` | 消息 RPC |
| `openim-rpc-conversation` | 会话 RPC |
| `openim-rpc-third` | 第三方服务 RPC (S3/日志) |
| `openim-rpc-encryption` | 端到端加密 RPC |
| `openim-rpc-extendmsg` | 扩展消息 RPC |
| `openim-crontask` | 定时任务 |
| `openim-cmdutils` | 管理工具 |

### Zig (zim) — 11 个 Modulith 模块
| 模块 | 状态 | 说明 |
|------|------|------|
| `event_bus` | ✅ | 事件驱动通信 |
| `config` | ✅ | YAML 配置加载 |
| `db_postgres` | ✅ | PostgreSQL 连接池 |
| `auth` | ✅ | JWT 认证 |
| `user` | ✅ | 用户 CRUD |
| `conversation` | ✅ | 会话管理 |
| `message` | ✅ | 消息存储/撤回/删除 |
| `group` | ✅ | 群组 CRUD/成员管理 |
| `friend` | ✅ | 好友请求/黑名单 |
| `gateway` | ✅ | HTTP 路由 (93 端点) |
| `queue` | ✅ | PGMQ 队列包装器 |
| `push` | ⚠️ Stub | 推送通知骨架 |
| `websocket` | ⚠️ 基础 | WebSocket 服务器 |
| `office` | ⚠️ 部分 | 工作圈/评论/点赞 |
| `organization` | ⚠️ 部分 | 组织架构 |

### ❌ 完全缺失的模块
1. **`msgtransfer` 消息流转管道** — Go 中独立的 Kafka 消费者服务，负责消息从接入层到存储层再到推送层的完整流转。Zig 中无独立消息处理管道，消息发送后直接写 PostgreSQL，缺少异步处理和解耦。
2. **`third` 第三方服务** — S3/MinIO 对象存储、客户端日志上传/检索、FCM token 管理、App Badge 设置。
3. **`encryption` 端到端加密** — 加密密钥生成与管理。
4. **`extendmsg` 扩展消息** — 扩展消息回调与处理。
5. **`meeting` / `signal` RTC 会议服务** — 音视频会议室、信令邀请。
6. **`statistics` 统计服务** — 活跃用户、活跃群组统计（Zig 只有用户注册数统计）。
7. **`jssdk` 浏览器 SDK 支持** — 专为 Web 客户端优化的会话聚合 API。
8. **`prometheus_discovery` 服务发现** — Prometheus 服务发现端点。

---

## 2. API 路由对比

### Go 路由总数: ~110+ 端点
### Zig 路由总数: ~93 端点 (已注册)

### Zig 缺失的 Go API 路由

#### `/third/*` — 第三方服务 (完全缺失)
| 路由 | 说明 |
|------|------|
| `POST /third/fcm_update_token` | 更新 FCM 推送令牌 |
| `POST /third/set_app_badge` | 设置 App 角标 |
| `POST /third/logs/upload` | 上传客户端日志 |
| `POST /third/logs/delete` | 删除客户端日志 |
| `POST /third/logs/search` | 检索客户端日志 |
| `POST /object/part_limit` | S3 分片限制 |
| `POST /object/part_size` | S3 分片大小 |
| `POST /object/initiate_multipart_upload` | 初始化分片上传 |
| `POST /object/auth_sign` | 获取签名 URL |
| `POST /object/complete_multipart_upload` | 完成分片上传 |
| `POST /object/access_url` | 获取对象访问 URL |
| `POST /object/initiate_form_data` | 表单上传初始化 |
| `POST /object/complete_form_data` | 表单上传完成 |
| `GET /object/*name` | 对象重定向下载 |
| `GET /third/prometheus` | Grafana 跳转 |

#### `/rtc-meeting/*` — 会议/信令 (完全缺失)
| 路由 | 说明 |
|------|------|
| `POST /rtc-meeting/book_meeting` | 预约会议 |
| `POST /rtc-meeting/create_immediate_meeting` | 即时会议 |
| `POST /rtc-meeting/join_meeting` | 加入会议 |
| `POST /rtc-meeting/get_meeting_token` | 获取会议 Token |
| `POST /rtc-meeting/update_meeting` | 更新会议 |
| `POST /rtc-meeting/get_meeting` | 获取会议信息 |
| `POST /rtc-meeting/get_meetings` | 获取会议列表 |
| `POST /rtc-meeting/leave_meeting` | 离开会议 |
| `POST /rtc-meeting/end_meeting` | 结束会议 |
| `POST /rtc-meeting/set_personal_setting` | 设置个人会议配置 |
| `POST /rtc-meeting/get_personal_setting` | 获取个人会议配置 |
| `POST /rtc-meeting/operate_meeting_all_stream` | 操作会议流 |
| `POST /rtc-meeting/modify_meeting_participant_name` | 修改参会者昵称 |
| `POST /rtc-meeting/remove_participants` | 移除参会者 |
| `POST /rtc-meeting/set_meeting_host_info` | 设置主持人 |
| `POST /rtc-meeting/signal_get_room_by_group_id` | 信令获取房间 |
| `POST /rtc-meeting/signal_get_rooms` | 信令获取房间列表 |
| `POST /rtc-meeting/get_signal_invitation_info` | 获取信令邀请信息 |
| `POST /rtc-meeting/get_signal_invitation_info_start_app` | 启动 App 信令邀请 |

#### `/encryption/*` — 加密 (完全缺失)
| 路由 | 说明 |
|------|------|
| `POST /encryption/get_encryption_key` | 获取加密密钥 |

#### `/jssdk/*` — JS SDK (完全缺失)
| 路由 | 说明 |
|------|------|
| `POST /jssdk/get_conversations` | 获取浏览器端会话 |
| `POST /jssdk/get_active_conversations` | 获取活跃会话 |

#### `/prometheus_discovery/*` — 监控发现 (完全缺失)
| 路由 | 说明 |
|------|------|
| `GET /prometheus_discovery/api` | API 服务发现 |
| `GET /prometheus_discovery/user` | User 服务发现 |
| ... (共 10 个端点) | |

#### `/statistics/*` — 统计 (部分缺失)
| 路由 | Zig 状态 |
|------|----------|
| `POST /statistics/user/register` | ✅ 有 |
| `POST /statistics/user/active` | ❌ 缺失 |
| `POST /statistics/group/create` | ❌ 缺失 |
| `POST /statistics/group/active` | ❌ 缺失 |

---

## 3. WebSocket 协议和消息格式

### 协议常量对比

| ReqIdentifier | Go 支持 | Zig 支持 | 说明 |
|---------------|---------|----------|------|
| `1001` GetNewestSeq | ✅ | ✅ | 获取最大 Seq |
| `1002` PullMsgBySeqList | ✅ | ✅ | 按 Seq 拉取消息 |
| `1003` SendMsg | ✅ | ✅ | 发送消息 |
| `1004` SendSignalMsg | ✅ | ❌ | 发送信令消息 (RTC) |
| `1005` PullMsg / GetSeqMessage | ✅ | ✅ | 获取 Seq 消息 |
| `1006` GetConvMaxReadSeq | ✅ | ❌ | 获取会话已读 Seq |
| `1007` PullConvLastMessage | ✅ | ❌ | 拉取会话最新消息 |
| `2001` PushMsg | ✅ | ❌ | 服务端推送消息 |
| `2002` KickOnlineMsg | ✅ | ❌ | 踢用户下线 |
| `2003` LogoutMsg | ✅ | ❌ | 用户登出 |
| `2004` SetBackgroundStatus | ✅ | ❌ | 设置后台状态 |
| `2005` SubUserOnlineStatus | ✅ | ❌ | 订阅用户在线状态 |
| `2100` ServerConfigMsg | ✅ | ❌ | 服务端配置消息 |
| `3001` DataError | ✅ | ✅ | 数据错误 |

### ❌ Zig WebSocket 缺失的关键功能

1. **消息推送 (WSPushMsg = 2001)**
   - Go: 服务端主动推送消息到客户端，支持按会话分组 (normal + notification)
   - Zig: 只有 `pushToUser` 文本推送，无 protobuf 封装，无按会话分组

2. **踢人下线 (WSKickOnlineMsg = 2002)**
   - Go: 多终端登录冲突时主动踢出旧连接
   - Zig: 完全缺失

3. **用户登出 (WsLogoutMsg = 2003)**
   - Go: 处理客户端主动登出，清理 push token
   - Zig: 完全缺失

4. **后台状态同步 (WsSetBackgroundStatus = 2004)**
   - Go: 客户端切前后台时通知服务端，影响推送策略
   - Zig: 完全缺失

5. **在线状态订阅 (WsSubUserOnlineStatus = 2005)**
   - Go: 支持订阅指定用户的在线状态变更
   - Zig: 完全缺失

6. **服务端配置下发 (WSServerConfigMsg = 2100)**
   - Go: 连接建立后立即下发加密配置等
   - Zig: 完全缺失

7. **连接认证机制**
   - Go: WebSocket 握手时通过 URL query 参数传递 token，authClient.ParseToken 验证
   - Zig: 仅支持通过 JSON `Login` 消息认证，无握手阶段 token 验证

8. **压缩支持**
   - Go: 支持 gzip 压缩 (`GzipCompressionProtocol`)，按 SDK 类型选择编码
   - Zig: 无压缩支持

9. **多终端登录策略**
   - Go: 支持 6 种策略 (`DefalutNotKick`, `WebAndOther`, `PCAndOther`, `AllLoginButSameTermKick`, `AllLoginButSameClassKick`, `SingleTerminalLogin`, `Customize`)
   - Zig: 无多终端管理，同一用户可无限连接

10. **心跳/保活**
    - Go: 支持 Web 端 ping/pong (`pingPeriod = 27s`)
    - Zig: 仅响应客户端 ping，无服务端主动心跳

---

## 4. 数据库模型和表结构

### 已对齐的表
- `users`, `conversations`, `messages`, `groups`, `group_members`, `group_requests`, `friends`, `friend_requests`, `blacks`, `auth_tokens`

### Go 有、Zig 缺失/不完整的表/模型

| Go 模型 | Zig 状态 | 说明 |
|---------|----------|------|
| `seq_user.go` | ⚠️ 简化 | Go 有独立的 seq 管理模型，Zig 只有 `seq_conversations` 和 `seq_users` |
| `msg_pinned.go` | ✅ 有表 | `msg_pinned` 表存在但可能未在业务中充分使用 |
| `stream_msg.go` | ❌ 缺失 | 流式消息模型 |
| `subscribe.go` | ✅ 有表 | `subscribe_users` 表存在 |
| `version_log.go` | ❌ 缺失 | 增量同步版本日志 |
| `object.go` | ❌ 缺失 | S3 对象存储元数据 |
| `log.go` | ❌ 缺失 | 客户端日志模型 |
| `application.go` | ❌ 缺失 | 应用级数据模型 |

### 字段差异

#### messages 表
- Go: 使用 MongoDB `MsgDocModel` 文档模型，支持 `doc_id` 分桶存储 (每 100 条一个文档)
- Zig: PostgreSQL 行存储，无文档分桶，大数据量时性能可能下降
- Go: `options` 为 `map[string]bool`，`offline_push` 为结构化对象
- Zig: `options` 和 `offline_push` 为 JSONB，但业务层未充分利用

#### conversations 表
- Go: 支持 `latest_msg` 完整存储最新消息
- Zig: 有 `latest_msg` 字段但未在发送消息时自动更新

#### user_online_status
- Go: 使用 Redis 缓存 + MongoDB 持久化
- Zig: PostgreSQL 表存储，无 Redis 缓存层

---

## 5. 业务逻辑中 Zig 尚未实现的部分

### 消息发送管道 (Message Pipeline)

#### Go 的完整流程:
```
Client → msggateway (WS) → rpc-msg (SendMsg) → Kafka (ToRedisTopic)
  → msgtransfer (Kafka Consumer) → Redis Cache → Kafka (ToMongoTopic)
  → MongoDB + Kafka (ToPushTopic) → push service → Online/Offline Push
```

#### Zig 的当前流程:
```
Client → gateway (HTTP/WS) → message.zig → PostgreSQL (直接写入)
```

**缺失环节:**
1. ❌ 消息队列异步处理 (PGMQ 已集成但未在消息发送链路中使用)
2. ❌ 消息缓存层 (Redis 替代)
3. ❌ 消息分桶存储 (MongoDB doc model)
4. ❌ 发送后自动更新会话 `latest_msg` / `max_seq`
5. ❌ 发送后自动创建会话 (单聊首次发消息时应创建 conversation)
6. ❌ @消息解析和群聊 `group_at_type` 更新
7. ❌ 消息选项处理 (`IsHistory`, `IsPersistent`, `IsSenderSync`, `IsOfflinePush`, `IsUnreadCount`)

### 消息阅读回执

| 功能 | Go | Zig |
|------|-----|-----|
| 单聊已读回执 | ✅ | ✅ (mark_user_message_read) |
| 群聊已读回执 | ✅ | ✅ (mark_group_message_read) |
| 群聊已读人数统计 | ✅ | ✅ (get_group_message_read_num) |
| 群聊已读成员列表 | ✅ | ✅ (get_group_message_has_read) |
| 已读 Seq 持久化到 MongoDB | ✅ | ❌ |
| 已读回执消息通知发送方 | ✅ | ❌ |

### 消息撤回

- Go: 撤回后发送撤回通知给所有相关方，更新消息状态
- Zig: 数据库标记 `is_revoke = true`，但缺少通知推送

### 增量同步 (Incremental Sync)

- Go: 完善的增量同步机制，基于 `version_log` 表记录变更版本
- Zig: 有 API 端点 (`get_incremental_*`)，但底层实现可能不完整

### 会话管理

| 功能 | Go | Zig |
|------|-----|-----|
| 创建单聊会话 | ✅ (msgtransfer 自动创建) | ❌ |
| 创建群聊会话 | ✅ (msgtransfer 自动创建) | ❌ |
| 设置会话最大 Seq | ✅ | ⚠️ 部分 |
| 获取会话离线推送用户列表 | ✅ | ✅ |
| 获取免打扰会话 ID 列表 | ✅ | ✅ |
| 获取置顶会话 ID 列表 | ✅ | ✅ |
| 获取排序会话列表 | ✅ | ✅ |
| Conversation Pinned Msg | ⚠️ 注释掉 | ❌ |

---

## 6. 认证、授权、消息推送、群聊等高级功能

### 认证 (Auth)

| 功能 | Go | Zig |
|------|-----|-----|
| JWT Token 生成/解析 | ✅ | ✅ |
| Token 持久化到 PostgreSQL | ✅ | ✅ |
| 强制登出 (ForceLogout) | ✅ | ✅ |
| Token 失效/踢出 (InvalidateToken) | ✅ | ❌ |
| 多平台 Token 管理 | ✅ | ❌ |
| 管理员 Token 获取 | ✅ | ✅ |
| Token 解析返回平台信息 | ✅ | ✅ |

### 授权 (Authorization)

| 功能 | Go | Zig |
|------|-----|-----|
| AppManager 权限检查 | ✅ | ⚠️ 简单检查 |
| 发送消息权限校验 | ✅ | ❌ |
| 群成员角色权限 (Owner/Admin/Member) | ✅ | ⚠️ 基础 |
| 群禁言权限 | ✅ | ✅ |

### 消息推送 (Push)

#### 在线推送 (Online Push)
| 功能 | Go | Zig |
|------|-----|-----|
| WebSocket 实时推送 | ✅ | ⚠️ 基础文本推送 |
| 按会话分组推送 | ✅ | ❌ |
| 批量推送 (BatchPush) | ✅ | ❌ |
| 多 Gateway 节点推送 | ✅ | ❌ (单进程) |
| 推送前 Webhook 回调 | ✅ | ❌ |
| 推送结果统计 | ✅ | ❌ |

#### 离线推送 (Offline Push)
| 功能 | Go | Zig |
|------|-----|-----|
| FCM (Firebase) | ✅ | ❌ |
| APNs (Apple) | ✅ | ❌ |
| 极光推送 (JPush) | ✅ | ❌ |
| 个推 (Getui) | ✅ | ❌ |
| 自定义推送内容 (标题/内容/角标/声音) | ✅ | ⚠️ Stub |
| 离线推送队列 (Kafka) | ✅ | ⚠️ PGMQ 有但未接通 |
| 免打扰过滤 | ✅ | ❌ |
| 在线用户免离线推 | ✅ | ❌ |

### 群聊高级功能

| 功能 | Go | Zig |
|------|-----|-----|
| 群组创建/解散 | ✅ | ✅ |
| 群成员邀请/踢出/退出 | ✅ | ✅ |
| 群主转让 | ✅ | ✅ |
| 群成员禁言/取消禁言 | ✅ | ✅ |
| 全员禁言 | ✅ | ✅ |
| 进群验证设置 | ✅ | ✅ |
| 群成员角色 (Owner/Admin) | ✅ | ✅ |
| 群公告管理 | ✅ | ⚠️ 有字段 |
| 群聊 @所有人/部分人 | ✅ | ❌ |
| 群聊已读状态显示 (`display_is_read`) | ✅ | ✅ |
| 群聊邀请确认 | ✅ | ✅ |
| 群成员信息自定义 | ✅ | ✅ |
| 群聊申请处理 (HandleResult) | ✅ | ✅ |
| 群解散后自动清理成员 | ✅ | ❌ |
| 群成员退出/被踢后自动更新会话 Seq | ✅ | ❌ |

### 好友高级功能

| 功能 | Go | Zig |
|------|-----|-----|
| 添加好友/响应 | ✅ | ✅ |
| 删除好友 | ✅ | ✅ |
| 设置备注 | ✅ | ✅ |
| 黑名单 | ✅ | ✅ |
| 好友置顶 (`is_pinned`) | ✅ | ✅ |
| 批量导入好友 | ✅ | ✅ |
| 增量获取好友列表 | ✅ | ✅ |
| 增量获取黑名单 | ✅ | ✅ |
| 获取全部好友用户 ID | ✅ | ✅ |
| 未处理申请数量 | ✅ | ✅ |
| 双向删除好友申请 | ✅ | ✅ |

### 用户高级功能

| 功能 | Go | Zig |
|------|-----|-----|
| 用户注册/信息更新 | ✅ | ✅ |
| 全局消息接收设置 | ✅ | ✅ |
| 在线状态查询 (多平台) | ✅ | ⚠️ 简化 |
| 在线 Token 详情 | ✅ | ⚠️ 简化 |
| 用户状态订阅/取消订阅 | ✅ | ⚠️ 简化 |
| 用户自定义命令 (UserCommand) | ✅ | ✅ |
| 通知账号管理 | ✅ | ✅ |
| 用户搜索/分页 | ✅ | ✅ |
| 账号检查 | ✅ | ✅ |

---

## 7. 其他重要缺失功能

### Webhooks / Callbacks
Go 实现了完整的 webhook 机制，Zig 完全缺失：
- `BeforeSendSingleMsg` / `AfterSendSingleMsg`
- `BeforeSendGroupMsg` / `AfterSendGroupMsg`
- `BeforeMsgModify`
- `BeforeOnlinePush` / `BeforeGroupOnlinePush`
- `BeforeOfflinePush`
- `AfterUserOnline` / `AfterUserOffline`
- `FriendApplication` / `BeforeAddFriend` / `BeforeCreateGroup`

### 消息内容类型支持

| ContentType | Go | Zig |
|-------------|-----|-----|
| Text (101) | ✅ | ✅ |
| Picture (102) | ✅ | ✅ |
| Voice (103) | ✅ | ✅ |
| Video (104) | ✅ | ✅ |
| File (105) | ✅ | ✅ |
| AtText (106) | ✅ | ⚠️ |
| Merge (107) | ✅ | ❌ |
| Card (108) | ✅ | ❌ |
| Location (109) | ✅ | ❌ |
| Custom (110) | ✅ | ✅ |
| Recall (111) | ✅ | ✅ |
| Typing (113) | ✅ | ❌ |
| Quote (114) | ✅ | ❌ |
| CustomFace (115) | ✅ | ❌ |
| GroupAnnouncement (116) | ✅ | ❌ |
| GroupCall (117) | ✅ | ❌ |
| OANotification (1200) | ✅ | ❌ |
| BusinessNotification (1300) | ✅ | ✅ |

### 配置管理
- Go: 支持动态配置管理 (`config_manager.go`)
- Zig: 静态 YAML 配置加载

### 日志与监控
- Go: Prometheus 指标采集 (在线人数、消息推送成功率、MongoDB 写入成功率等)
- Zig: 无指标采集

### 消息搜索
- Go: 支持按关键词搜索消息，有复杂的搜索条件构建
- Zig: 基础 SQL `LIKE` 搜索

### 消息清理策略
- Go: 支持按会话清空、用户级全部清空、物理删除、按 Seq 物理删除
- Zig: 有对应 API 但底层实现较简单

### 定时任务 (Crontask)
- Go: 独立的 `openim-crontask` 服务，用于定时清理、统计等
- Zig: 无定时任务模块

---

## 8. 总结: 关键缺失清单 (按优先级排序)

### 🔴 P0 — 核心功能缺失 (影响基本可用性)
1. **消息推送管道** — WebSocket 服务端主动推送 (PushMsg) 未实现
2. **多终端登录管理** — 无踢人下线、无设备管理
3. **消息选项处理** — `IsHistory`, `IsOfflinePush`, `IsSenderSync` 等未处理
4. **发送消息后自动更新会话** — `latest_msg`, `max_seq`, `latest_msg_send_time`
5. **首次发消息自动创建会话** — 单聊/群聊首次消息应自动创建 conversation

### 🟠 P1 — 重要功能缺失 (影响完整体验)
6. **离线推送集成** — FCM/APNs/极光/个推实际接入
7. **消息撤回通知** — 撤回后应推送给相关方
8. **已读回执通知** — 已读后应通知发送方
9. **@消息解析** — 群聊 @消息应解析并更新 `group_at_type`
10. **WebSocket 压缩** — gzip 压缩支持
11. **信令消息 (1004)** — RTC 相关信令
12. **后台状态管理 (2004)** — 影响推送策略

### 🟡 P2 — 企业级功能缺失
13. **对象存储 (S3/MinIO)** — 图片/文件/视频上传
14. **端到端加密** — Encryption RPC
15. **RTC 会议** — 音视频会议室全套 API
16. **客户端日志** — 日志上传/检索
17. **JSSDK 支持** — Web 端优化 API
18. **Webhooks/Callbacks** — 业务回调机制
19. **统计报表** — 活跃用户、活跃群组
20. **消息内容类型扩展** — Merge、Card、Location、Typing、Quote 等
21. **Prometheus 监控** — 服务指标采集
22. **流式消息** — StreamMsg 支持
23. **定时任务** — 数据清理、统计

---

*报告结束*
