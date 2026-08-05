# AGENTS.md - Zig IM Server (zim)

## Project Overview

**Goal**: Rewrite OpenIM Server (Go → Zig) using [zigmodu](https://github.com/chy3xyz/zigmodu) framework.
**Flutter/Expo frontend** (`_ref/openimsdk-open-im-flutter-enterprise/`) does NOT need changes.

## Repository Structure

```
zim/
├── src/                      # Zig application
│   ├── main.zig              # Bootstrap with zigmodu Application API
│   ├── core.zig              # Infrastructure layer: allocator, DI container, event bus, logger, validation
│   ├── modules/              # Modulith modules
│   │   ├── event_bus.zig      # Event-driven communication
│   │   ├── config.zig         # Configuration loading
│   │   ├── db_postgres.zig    # PostgreSQL connection pool
│   │   ├── auth.zig           # JWT authentication
│   │   ├── user.zig           # User management
│   │   ├── conversation.zig   # Conversation management
│   │   ├── message.zig        # Message storage + auto conversation sync
│   │   ├── group.zig          # Group chat
│   │   ├── friend.zig         # Friend relationships
│   │   ├── office.zig         # Work moments (enterprise)
│   │   ├── organization.zig   # Organization structure (enterprise)
│   │   ├── third.zig          # Third-party services: RustFS object storage, FCM, logs, webhooks
│   │   ├── gateway.zig        # HTTP + WebSocket server (120+ routes)
│   │   ├── queue.zig          # PGMQ wrapper
│   │   ├── push.zig           # Push notification worker
│   │   ├── crontask.zig       # Background cron tasks: cleanup, webhook delivery
│   │   └── websocket.zig      # WebSocket real-time protocol
│   ├── proto/                 # Protobuf codec
│   │   ├── protobuf.zig       # Protobuf v3 encoder/decoder
│   │   └── sdkws.zig          # OpenIM WebSocket message definitions
│   └── build.zig              # Zig build file
├── config/
│   └── config.yaml            # Runtime configuration
├── migrations/                # PostgreSQL schema migrations
├── docs/                      # Architecture documents
│   └── go-zig-gap-analysis.md # Go vs Zig feature gap analysis
├── _ref/                      # Reference implementations (READ ONLY)
│   ├── openimsdk-open-im-server-enterprise/   # Go IM server
│   ├── openimsdk-chat-enterprise/             # Go chat server
│   └── openimsdk-open-im-flutter-enterprise/  # Flutter SDK (DON'T TOUCH)
└── dev.md                     # Original task description
```

## Implemented Modules (Modulith)

| Module | Status | Description |
|--------|--------|-------------|
| event_bus | ✓ | Event-driven pub/sub for module communication |
| config | ✓ | YAML config loading |
| db_postgres | ✓ | PostgreSQL query builder |
| auth | ✓ | JWT with HMAC-SHA256, PostgreSQL token store |
| user | ✓ | User CRUD, online status, UUID v4, getAllUserIDs |
| conversation | ✓ | Conversation CRUD, seq tracking, auto-create on first message |
| message | ✓ | Message CRUD, recall, delete, auto-sync conversation, options support |
| group | ✓ | Group CRUD, member management |
| friend | ✓ | Friend requests, blacklist (PostgreSQL-backed) |
| gateway | ✓ | zigmodu http.Server + ComptimeRouter（185 条声明式路由，含 RTC 会议） |
| queue | ✓ | PGMQ message queue (PostgreSQL-backed) |
| push | ✓ | Online push via WS 2001, offline queue via PGMQ, DND filter |
| third | ✓ | RustFS S3-compatible presigned URLs, FCM token storage, logs, webhook queue |
| crontask | ✓ | Background tasks: message cleanup, auth token cleanup, webhook delivery |
| websocket | ✓ | WebSocket server + OpenIM protobuf protocol |
| office | ✓ | Work Moments (enterprise): publish/like/comment/permissions |
| organization | ✓ | Organization structure (enterprise): departments, recursive query |

## Architecture (Modulith)

Single-process modular architecture with event-driven communication:

| Original (Go) | New (Zig) |
|----------|-----|
| MongoDB + Redis | PostgreSQL + JSONB |
| Kafka (multi-broker) | PGMQ (single PG) |
| 10+ microservices | 17 modules (single process) |
| gRPC + Protobuf | HTTP/JSON + EventBus + Protobuf (WS) |
| Direct RPC calls | Event-driven pub/sub |

## Development Commands

```bash
# Build
cd src && zig build

# Run
cd src && zig build run

# Test
cd src && zig build test

# Format
zig fmt
```

## Database Setup

```bash
# Run migrations against PostgreSQL
psql -h localhost -U zim -d zim -f migrations/001_initial.sql
```

## Configuration

Edit `config/config.yaml`:
- INI 风格 `[section]` 段（由 zigmodu `YamlParser` 解析）：`[database]`、`[gateway]`、`[jwt]`、`[redis]`、`[queue]`、`[object_storage]`、`[webhook]`，键为 `http_port` / `ws_port` / `secret` 等
- 旧缩进 YAML 格式仍被 `applyLegacy` 回退解析器兼容

## Implementation Status

**Phase 1**: Core modules + EventBus - COMPLETE  
**Phase 2**: Gateway HTTP routing - COMPLETE (165 endpoints)  
**Phase 3**: Database integration - COMPLETE (all modules PostgreSQL-backed)  
**Phase 4**: WebSocket protocol alignment - COMPLETE (ReqIdentifier 1001-1006 + 2001-2100 + protobuf codec + push 2001)  
**Phase 5**: Auth token persistence - COMPLETE (PostgreSQL auth_tokens table + WS handshake auth)  
**Phase 6**: Flutter/Expo frontend alignment - COMPLETE (camelCase JSON responses, JOIN user profiles, Go-compatible conversation_id)  
**Phase 7**: PGMQ integration - COMPLETE  
**Phase 8**: Push notifications - COMPLETE (online push via WS 2001, offline queue via PGMQ, DND filter)  
**Phase 9**: Auto conversation management - COMPLETE (create + update on message send)  
**Phase 10**: Message options - COMPLETE (isHistory, isOfflinePush, isSenderSync, isNotNotification)  
**Phase 11**: Third-party services - COMPLETE (RustFS object storage replacing MinIO, presigned URL auth_sign/access_url)  
**Phase 12**: Content type expansion - COMPLETE (merge/card/location/typing/quote + auto options)  
**Phase 13**: RTC meeting API - COMPLETE (19 endpoints with in-memory room management + atomic locking)  
**Phase 14**: Cron tasks - COMPLETE (hourly cleanup of messages/auth_tokens, webhook delivery every 5min)  
**Phase 15**: Webhook/Callback - COMPLETE (async event queue with curl-based HTTP delivery)
**Phase 16**: SQL parameterization - COMPLETE (all queries migrated to parameterized queries)
**Phase 17**: End-to-end encryption - COMPLETE (`/encryption/get_encryption_key`, `/encryption/gen_encryption_key` with AES-256 key generation)  
**Phase 18**: Message send validation - COMPLETE (friend/blacklist/group membership/mute checks before send)  
**Phase 19**: Seq batch API fixes - COMPLETE (GetMaxSeq returns global max, PullMsgBySeqList respects range/order, PullMsg uses seq query)  
**Phase 20**: Unread count + conversation enrichment - COMPLETE (maxSeq/minSeq/hasReadSeq/unreadCount in all conversation responses)  
**Phase 21**: Incremental sync support - COMPLETE (updated_at+triggers on friends/blacks/group_members, Since queries for all incremental APIs, proper seq return values)  
**Phase 22**: Message editing - COMPLETE (`/msg/modify_message` with `is_edit`/`edit_time` tracking)  
**Phase 23**: Tag system - COMPLETE (`/office/tag/*` CRUD with tag_members)  
**Phase 24**: Favorite/Collect messages - COMPLETE (`/collect/*` add/del/list)  
**Phase 25**: Client config - COMPLETE (`/client_config/get`)  
**Phase 26**: Search APIs - COMPLETE (`/friend/search`, `/user/find/full`, `/user/search/full`)  
**Phase 27**: Deep zigmodu integration - COMPLETE (`core.zig` infrastructure, DI Container, unified allocator, compile-time module validation, event bus backed by core)  
**Phase 28**: Per-request arena allocator - COMPLETE (arena allocator in `handleHttpConnection` for automatic request lifecycle memory cleanup, `core.getGlobalAllocator()` for persistent state)  
**Phase 29**: TODO handler stubs - COMPLETE (`handleUpdateTag` uses `office_mod.updateTag`, `handleSubscribeUsersStatus` returns current status, `handleSetAppBadge` returns unread count, RTC invite/reject/signal relay via WebSocket push)  
**Phase 30**: JSON field name alignment - COMPLETE (systematic audit against Flutter SDK models: `sendID`/`recvID`/`senderFaceUrl` in Message, `appMangerLevel` in UserInfo, `unreadCount` in Conversation, `userID` in FriendInfo; all raw struct responses converted to `*ToJson` helpers for camelCase)  
**Phase 31**: zigmodu v0.14.17 新特性重构 - COMPLETE (core 事件总线改为 zigmodu `ThreadSafeEventBus` + `WorkerPool` 异步分发；`main.zig` 改用 `zmodu.builder` 流式 ApplicationBuilder；全部模块声明 `RuntimeOptions` 获得每模块资源隔离（bulkhead/rate limiter/circuit breaker/worker pool）；密码哈希换成 `zigmodu.security.PasswordEncoder`（PBKDF2-HMAC-SHA256）；`/health` 改用 zigmodu `HealthEndpoint`，`/metrics` 输出真实 Prometheus 文本；所有 `gettimeofday`+`DefaultPrng` 旧模式换成 `core.secureRandomBytes`（OS CSPRNG）与 `core.unixNowSeconds/Millis`；修复 `friend_requests.handled_time`→`handle_time` 列名漂移)
**Phase 32**: HTTP 层迁移 zigmodu http.Server + ComptimeRouter - COMPLETE (自研线程模型 HTTP 服务器替换为 zigmodu `http.Server`（纤维 + trie 路由 + 中间件链）；185 条路由改为声明式 `pub const routes` + `scope.mountAll`；handler 经 `bridge()` 适配层桥接 zigmodu `Context`，OpenIM `{errCode,errMsg,data}` 信封协议不变；CORS/OPTIONS 与 token 鉴权中间件；修复 libpq SQL 非 NUL 结尾越界读、共享连接多线程并发（互斥锁）、crontask `nanosleep` 空转、`stop`/`join` 顺序导致的停机挂起、DI 容器销毁全局服务崩溃等稳定性问题)
**Phase 33**: 内存与配置收尾 - COMPLETE (新增 `core.serviceAllocator()` 请求感知分配器 + `requestArenaMiddleware`，service/persistence 运行期结果自动落入每请求 arena，Debug 退出 0 泄漏；事件 payload 由 `core.emit` 复制到全局并由 WorkerPool 消费后释放，修复异步订阅的 use-after-free；config 改用 zigmodu `YamlParser`（`config.yaml` 转为 `[section]` INI 风格，保留旧缩进 YAML 回退），配置字符串在模块 deinit 时统一释放；auth/account/health/metrics 13 个 handler 迁移到原生 `http.Context`（`ctx.bindJson`/`sendOk`/`sendFail`），其余 172 条仍走 bridge 适配层)
**Phase 34**: HTTP handler 全量原生化 + WS 迁移 zigmodu ws_routes - COMPLETE (185 个 handler 全部迁移到原生 `http.Context` 风格，删除 bridge/invokeLegacy 适配层；WebSocket 自研服务器替换为 zigmodu `http.Server`（10001）+ `ws_routes`，`WSClient` 经 `framer` 字段走 `WsFramer.writeText/writeBinary`，binary protobuf 推送、text JSON 分发、握手 token 鉴权、踢线、断开清理全部保留；修复 WS 事件 payload 非 JSON 导致的异步处理器 panic；修复本地 zigmodu 两处编译错误（`WsFrameKind` 重复声明、`fromOpcode` 参数遮蔽），zigmodu 本地源码新增 binary 帧支持（`WsMessageFn` 增加 `kind` 参数）)
**Phase 35**: 评估清单收尾 - COMPLETE (gateway 按域拆分：`gateway.zig` 143 行骨架 + `gateway/handlers.zig` 4234 行路由表/处理器；死代码清理：event_bus 旧总线、旧 HttpRequest/HttpResponse 模型、core.validateModule 垫片；RuntimeOptions 接线：gateway 请求准入（bulkhead）+ db 熔断统计；DB 连接池（8 连接，`database.max_conns` 驱动）+ `PQreset` 自动重连；启动迁移自动化：schema_migrations 跟踪、按序自动应用、失败显式中止，pgmq 改为可选扩展；可观测性：请求延迟 histogram、访问日志、`GET /openapi.json`；安全：验证码 DB 化（013 迁移）+ 登录限流（5 次/15 分钟/用户）；测试：`zig build test` 扩展到 6 个（core 事件总线 + gateway HTTP 契约 Testkit）)
**Phase 36**: 事务与结构完善 - COMPLETE (PostgresClient 新增 `Tx`（begin/commit/rollback，锁定池连接），参数序列化抽为共享助手；建群（群+群主+成员）与加好友响应（请求更新+双向好友）改为原子事务；修复建群链路既有 bug：RETURNING 列错位/越界、timestamptz 列误传 unix 秒（改 `to_timestamp`）、成员参数数量不匹配、mute_end_time 整数 0→NULL；登录/注册参数显式校验；16 个 DTO 助手抽到 `gateway/dto.zig`；迁移记录 INSERT 并发安全 + applied 键泄漏修复；新增登录限流单测（共 7 个测试）)
**Phase 37**: 事务扩展与路由分组 - COMPLETE (删好友双向删除、解散群（群+成员+申请）、注销用户（令牌/好友/申请/黑名单/会话/命令/在线状态级联）全部改为原子 `Tx`；`/account/code/send` 每目标 60 秒限流；`GatewayRoutes.routes` 拆为 17 个按域 `*_routes` const 后 `++` 合并，186 条路由不变；`zig build test` 7 个测试全过，冒烟 0 泄漏优雅停机)
**Phase 38**: 缺陷审计轮 - COMPLETE (修复工作圈动态创建 RETURNING 列错位/越界（10 列 vs 12 列解析器）；修复工作圈/组织分页 offset 恒错（5 处 `(page-1)*size`）；修复消息搜索 `EXTRACT(EPOCH FROM send_time)`（bigint 毫秒）与 `LIMIT $3` 类型推断；复核 friend 请求/会话时间单位/工作圈 JSON 时间比较均一致)
**Phase 39**: 安全审计轮 - COMPLETE (修复 message 模块 5 处 SQL 注入（client_msg_id/conversation_id/user_id/group_id 拼接，含 INSERT）→ 全参数化；office `getCollects` 类型过滤 `IN (...)` 未转义 → `$N` 参数化；`conversation_id[3..]` 越界守卫；复核 ORDER BY/UPDATE SET/where 子句/列名分支均无注入面)
**Phase 40**: 契约审计轮 - COMPLETE (`/conversation/get_sorted_conversation_list` 按 Go proto 对齐：请求兼容 `userID`/`ownerUserID`，响应新增 `conversationElems`+`conversationTotal`/`unreadTotal`（msgInfo 从 latest_msg 解析），保留旧字段；崩溃风险审计（可选解包均有守卫、无 unreachable）；新增 WS protobuf `MsgData` 往返测试，共 8 个测试)
**Phase 41**: 测试深度轮 - COMPLETE (新增真实 PostgreSQL 服务层集成测试：注册/登录/token/档案/非好友拒收/加好友事务/建群带成员事务/发消息/会话自动同步，PG 不可用优雅跳过；暴露并修复 `registerWithPassword` 双重 PBKDF2 哈希 bug 与 auth deinit 限流 map 泄漏；`zig build test` 共 9 个测试全过)
**Phase 42**: 多终端登录策略 - COMPLETE (对齐 Go 6 种登录策略：DefaultNotKick/AllLoginButSameTermKick(默认)/SingleTerminalLogin/WebAndOther/AllLoginButSameClassKick/PCAndOther/Customize；平台分类按 OpenIM platform id；`[gateway] login_policy` 配置；`shouldKickOld` 纯函数单测覆盖 6 策略 + 运行时实测策略 1 踢线与策略 0 共存)
**Phase 43**: 压测工具 + JSSdk - COMPLETE (`zig build bench` 进程内压测登录/加好友/建群/发消息 ops/s；新增 `/jssdk/get_conversations` 与 `/jssdk/get_active_conversations`（对齐 Go jssdk `ConversationMsg`：conversation+lastMsg+user/group+maxSeq/readSeq+unreadCount），实测两端点正常；8/8 测试，0 泄漏)
**Phase 44**: Friend/Black/Apply 契约对齐轮 - COMPLETE (对照 Go proto `relation.proto`/`sdkws.proto`：`get_friend_list` 增加 `total` 且每项含 Go `FriendInfo` 嵌套 `friendUser`+`isPinned`；`get_black_list` key 从 `blacksInfo` 改为 `blacks`+`total`+嵌套 `blackUserInfo`；`get_friend_apply_list`(收方) key 对齐 Go json tag `FriendRequests`+`total`，`get_self_friend_apply_list`(申请方) `friendRequests`+`total`；`get_specified_friends_info` 重构为 Go `{infos:[{userInfo,friendInfo,blackInfo}]}`；`get_specified_blacks` key 改为 `blacks`；`update_friends` 补齐 `isPinned`/`remark`/`ex` 参数化部分更新；group member/application 列表补 `total`；修复 zigmodu `bindJson` deepCopy 对非 u8 slice（`[]struct`/`[][]const u8`）浅拷贝导致请求内第 2 个元素的悬空指针段错误（第 5 处本地 zigmodu 修复）；8/8 测试，冒烟+优雅停机 0 泄漏)
**Phase 45**: Group/Statistics 契约对齐轮 - COMPLETE (对照 Go `group.proto`：`get_groups_info` key 改为 `groupInfos` 且经 camelCase DTO（原先直接吐蛇形 Group 结构）；`get_groups` 补 `total` + camelCase；`get_joined_group_list` 补 `total`；`get_group_abstract_info` 重构为 Go `{groupAbstractInfos:[{groupID,groupMemberNumber,groupMemberListHash}]}`（请求 `groupIDs` 数组，member list hash 用成员 user_id FNV-1a 64 计算）；statistics `/user/register` 与 `/group/create` 对齐 Go `userRegisterCountResp`/`GroupCreateCountResp` 的 `{total,before,count:<date,数量>}`（新增 `countBefore`/`countByDay` 按天聚合查询 + `sendOkDataJson` 动态 map 响应）；8/8 测试，冒烟+优雅停机 0 泄漏)
**Phase 46**: Statistics Active + 成员/消息字段补齐轮 - COMPLETE (`/statistics/user/active` 与 `/group/active` 对齐 Go `GetActiveUserResp`/`GetActiveGroupResp`：`{msgCount,userCount/groupCount,dateCount:<date,数量>,users/groups:[{user/group,count}]}`，基于 messages 表按 create_time(秒) 聚合，支持分页 top N；`GroupMemberFullInfo` 补 `appMangerLevel`（getMembers 三查询 LEFT JOIN users 取 app_manager_level）；`send_msg` 响应补 Go 的 `modify` 字段；新增 `appendEscapedString` 保证手工 JSON 中昵称/URL 转义；8/8 测试，冒烟+优雅停机 0 泄漏)
**Phase 47**: zigmodu 升级 v0.15.7 + 新特性优化轮 - COMPLETE (本地 zigmodu 升级至 v0.15.7-7-g0d3bff0（远程 master 686d554 同步 + 5 个本地增强提交：queryRow owned/borrowed 契约、audit b10/b17 规则、CORS 大小写修复等）；引入 zmodu 工具链（v0.15.3+ `audit`/`deadcode`/`graph`/`ci`）驱动代码品质审计：`zmodu audit` 架构+业务 0 违规、`zmodu deadcode` 从 44 处死声明清理至 0（移除 `handlers.zig` 中 Phase 34 迁移遗留的 requestArena/cors/auth 三个中间件重复副本 —— 其 authMiddleware 引用未初始化 `g_registered_paths` 属潜在 UB 崩溃点、移除 RTC 死别名与 `g_registered_paths` 重复声明、清理 30+ 处未使用 import）；修复 `zig build test` 缓存陷阱：Zig 0.15+ 默认缓存 Run 步骤导致测试不执行即报 cached pass，`build.zig` 为 test 运行加 `has_side_effects = true` 保证 CI 真实执行；实测 `zig build test` 10/10 通过（zig 0.17-dev build runner 的 `failed command` stderr 噪音不影响退出码 0）；`zmodu ci` 全门禁 PASS)
**Phase 48**: zigmodu 跟进升级 v0.15.9 - COMPLETE (本地 zigmodu 从 v0.15.7-7-g0d3bff0 升级至 v0.15.9（4a70ade，远程 master 同步）；此前 5 个本地增强提交已被官方并入 v0.15.8 发布线；v0.15.8/v0.15.9 新特性为 queryRow owned/borrowed 契约正式发布、audit b10/b17、CrudApi/Outbox/Repository 多租户（zim 用自研 libpq 封装，不适用）与 AiProvider reasoning_content（zim 不用 AI 栈）；`0d3bff0→4a70ade` 源码变化仅 `src/ai/provider.zig`，对 zim 零破坏；实测 `zig build`/`zig build test` 退出码 0、`zmodu audit` 0 违规、`zmodu deadcode` 0 处、`zmodu ci` 全门禁 PASS)
**Phase 49**: 代码品质优化轮（A1-B7 + C9/C8）- COMPLETE (A1 接入 `securityHeaders` 安全响应头中间件，/health 实测 7 个安全头；A2 新增 4 个 PG 集成测试（黑名单双向拦截/解散群禁发/编辑召回语义/seq 单调性），抓出并修复 2 个真实契约偏差：validateMessage 校验顺序（先黑名单后好友，对齐 Go verify.go）、getBySeqList 返回顺序（按请求 seqs 重排，对齐 Go GetMsgBySeqs）；A3 camelCase 契约测试（真实 token + Testkit 断言 user/friend/black/send_msg/conversation 的 Flutter 对齐字段），抓出并修复 get_sorted_conversation_list msgInfo 从 6 字段升级为 Go 17 字段 MsgInfo 契约（faceURL/senderName/groupID/LatestMsgRecvTime 等）+ addBlack/removeBlack emit payload 泄漏；A4 HTTP 访问日志改为每请求一行 JSON（std.log 实现规避跨线程 std.Io；发现 zigmodu StructuredLogger fields key 未 dupe 崩溃 bug 需手动修）；B5 gateway/handlers.zig 4125 行按域拆为 298 行骨架 + 16 个域文件（187 路由/194 handler 逐字等价）；B6 消息发送链路事务化（sendInTx：插入+双方/群会话同步原子化，upsertWithLatest 一条 upsert SQL）+ seq 原子化（修复 SELECT-then-UPDATE 并发重复 seq 竞争）；B7 websocket/push 接入 bulkhead（此前 gateway/db/auth 已生效）；C9 新增 `scripts/ci.sh` 五步门禁（build/test/fmt/audit/deadcode）+ 全量 zig fmt；C8 输出 sqlx 迁移评估 docs/sqlx-migration-assessment.md（不建议近期迁移）；测试从 10 增至 15 全过、0 泄漏、audit/deadcode 全绿)
**Phase 50**: 测试覆盖 + 群权限模型轮（P0/P1）- COMPLETE (P0-a 新增 push 离线接收者决策 4 场景测试（在线不推/离线推/DND 抑制/恢复，getOfflineRecipients 导出）+ queue PGMQ 生命周期测试（探测 pgmq，缺失干净跳过）；P0-b 新增 crontask 清理测试（旧撤回消息+过期 token 实际删除）；P0-c websocket 评估：核心路径依赖 WS 连接状态，多端策略/protobuf/鉴权已覆盖，完整 WS 集成测试记为专项；P1-a 群主转让事务化（transferOwnerTx：旧主降级+新主升级+creator 更新原子化，校验 SameUser/NotOwner/NewOwnerNotMember，提交后发 role_changed 事件）；P1-b 入群验证三模式（need_verification 0 直接加入/1 申请审批/2 拒绝）；P1-c 成员列表权限（look_member_info 0 全员/1 仅成员/2 仅 admin+owner，handler 从 token 解析请求者）；P1-d 消息大小限制（64KB）+ 启动弱 JWT secret 检测（WARN）；修复测试基建全局单例悬空 bug（g_registered_paths 改 page_allocator）；测试从 15 增至 21 全过、0 泄漏、CI 全门禁绿)
**Phase 51**: 群功能收尾 + 可读 JSON 日志轮 - COMPLETE (apply_member_friend 评估：Go 服务端仅字段透传无业务校验，zim 对齐保持现状；群@所有人实现：at_user_id_list 含 "AtAllTag"（Go AtAllString）时发送者群会话 group_at_type 标记为 2（Go constant.AtAll），upsertWithLatest 加 group_at_type 列（GREATEST 单调），顺带修复 rowToConversation 硬编码 group_at_type=0 的解析 bug（4 处 SELECT/RETURNING 补列）；core 新增 `logJson`（std.json.Stringify 序列化，字符串可读、线程安全、无 std.Io 依赖），HTTP 访问日志从 zigmodu StructuredLogger（{any} 字节数组格式）切换到 core.logJson（`{"event":"http_request","path":"/health",...}` 可读）；测试从 21 增至 22 全过、0 泄漏、CI 全门禁绿)
**Phase 52**: 模块错误日志 JSON 化轮 - COMPLETE (db_postgres 5 处错误日志（query/exec/conn 失败）+ push 2 处（recipients/queue 失败）+ crontask 1 处（webhook 表创建）从 std.log.err/warn 改为 core.logJson（含 event/module/level/err 字段，std.log info 级输出避免触发测试 error-log 计数）；queue 测试恢复 pgmq 缺失降级断言（send 返回 error.QueryFailed，不再跳过）；评估：配置热加载（全局单例重建成本高）、日志轮转（stderr 场景无意义，接文件需先修 zigmodu StructuredLogger {s}）、WS 集成测试（需真实连接）记为后续专项；22/22 测试全过、CI 全门禁绿)
**Phase 53**: 群会话同步补齐 + AtAllAtMe + 性能基线轮 - COMPLETE (修复群消息后仅发送者会话更新的缺口：syncConversationTx 群分支现遍历所有群成员 upsert 会话（latest_msg/max_seq，对齐 Go SetConversations 给全部成员）；实现 AtAllAtMe：at_user_id_list 解析（JSON 数组，排除 AtAllTag），@所有人 → 全员会话 group_at_type=2，@具体用户 → 该用户会话 group_at_type=3（GREATEST 单调保证 3>2）；测试扩展：@具体用户标记 3 + 普通群消息同步成员 latest_msg；新增 docs/benchmark.md 性能基线（login 4 ops/s 为 PBKDF2 固有代价、friend 1429、group 1942、msg 866 ops/s Debug 构建）；22/22 测试全过、CI 全门禁绿)
**Phase 54**: 群消息批量 upsert 优化 - COMPLETE (conversation persistence 新增 `upsertWithLatestBatch`：一条多行 INSERT ... ON CONFLICT（每行 11 参数，bufPrint 拼 VALUES），群消息扇出从 N 次 round-trip → 1 次；syncConversationTx 群分支用 StringHashMap 按 owner 去重（解决 PG "ON CONFLICT cannot affect row a second time"：同用户既成员又被@时只出现一次，group_at_type 取最大）；实测 message send 866→971 ops/s（Debug）；⚠️ BLOCKER：用户 commit 2b265bd 使 zigmodu 缓存失效后，zigmodu v0.15.9 的 `src/sqlx/sqlx.zig` 在 zig 0.17-dev 下暴露 2 处编译错误（908 行冗余 comptime、5959 行局部 Row 遮蔽），导致 `zig build`（exe）失败 —— 补丁见 docs/zigmodu-sqlx-patch.md，需用户手动应用（沙箱限制 workspace 外写入）；`zig build test` 仍 22/22 全过（tests 编译图不含 sqlx）)
**Phase 55**: zigmodu v0.15.10 升级 + blocker 解除 - COMPLETE (用户应用 sqlx 补丁并升级 zigmodu 至 v0.15.10（d703dab：sqlx 908 行 comptime 冗余已修、5959 行局部 Row 遮蔽已消；新特性含 semicolon-aware migration splitter、orm 事务租户写）；`zig build`（exe）恢复编译、22/22 测试全过、`scripts/ci.sh` 全门禁绿、服务冒烟 health/msg 200；main.zig 启动日志从 StructuredLogger（{any} 字节数组格式，{s} 补丁仍未应用）统一为 `core.logJson`（`{"event":"zim_startup","version":"0.4.0",...}` 可读），至此所有 JSON 日志（访问/错误/启动）统一可读；AGENTS.md 遗留项同步)
**Phase 56**: WS 协议编解码覆盖 + @功能闭环验证轮 - COMPLETE (新增 WS 协议类型往返测试：PullMessageBySeqsReq（含嵌套 SeqRange 列表）、GetMaxSeqReq、GetSeqMessageReq 三类型 encode/decode 往返（字段值保持）；服务端专用 Resp 类型（UserSendMsgResp/GetMaxSeqResp 仅 encode 无 decode —— 服务端只发不解析，合理不补）验证 encode 正常产出字节；确认 @功能闭环完整：dto.conversationToJson 已输出 groupAtType（Go json tag 对齐），服务端标记 → 前端可读；测试从 22 增至 23 全过、CI 全门禁绿；评估：webhook 消息过滤（Go filterMsg 为 webhook 配置的 allowedTypes/deniedTypes，需回调集成，低优先）、配置热加载、日志轮转、WS 真实连接测试记为后续专项)
**Phase 57**: webhook 消息类型过滤轮 - COMPLETE (对齐 Go filterMsg：config `[webhook]` 新增 `allowed_types`/`denied_types`（逗号分隔单值或 "start-end" 区间，如 "101,201-210"，空=不限制）；message validateMessage 在发送前过滤（allowed 非空且 contentType 不在区间 → error.ContentTypeNotAllowed；denied 含 contentType → error.ContentTypeDenied）；新增 `contentTypeInIntervals` 纯函数（区间/单值/空白容错/畸形条目跳过，对齐 Go isInInterval）+ 单测；config.yaml 补默认值；测试从 23 增至 24 全过、CI 全门禁绿；动态 webhook 回调（BeforeSendMsg 响应驱动配置）与 attentionIds 过滤记为后续)
**Phase 58**: filterMsg attentionIds + 已读推进修复轮 - COMPLETE (补全 Go filterMsg attentionIds：config `[webhook]` 新增 `attention_ids`（逗号分隔用户 ID），非空时类型过滤仅对发送者/接收者在列表中的消息生效，其余放行（listContains helper）；修复真实功能缺口：`/msg/mark_msgs_as_read` 与 `/msg/mark_user_message_read` 原先只更新 messages.is_read 不推进会话 has_read_seq（未读计数永不下降，对齐 Go MarkMsgsAsRead 的 is_read + SetHasReadSeq）—— markMessageRead 签名加 owner_user_id（handler 从 token 解析 getReaderFromToken），persistence 追加会话 has_read_seq 更新（GREATEST 单调）；新增测试：发 2 条消息 → B 标记已读 → B 会话 has_read_seq 推进到最新 seq；测试从 24 增至 25 全过、CI 全门禁绿；已读回执通知（Go HasReadReceipt=2200 发对方）评估：会污染会话 latest_msg 预览，记为后续专项)
**Phase 59**: 已读回执尝试与回退轮 - COMPLETE (尝试实现已读回执通知：ContentType 加 read_receipt=2200、syncConversationTx notification 分支对 read_receipt 跳过会话 upsert（防预览污染）、handleMarkMsgsAsRead 发回执给对话对方、websocket switch 补 2200 分支；调试发现诡异 bug：notification+read_receipt 消息经 zig libpq 路径 INSERT 成功后 RETURNING 的 create_time 列返回二进制乱码（同 SQL 手动 psql 正常、普通消息路径正常，仅此组合异常）→ parseInt InvalidCharacter；经多轮定位（SQL 手动复现正常/参数序列化正常/列序正常）未果，**决定回退**回执通知实现（handler 发回执 + 测试），**保留**：已读推进修复（Phase 58，验证过）、ContentType.read_receipt 枚举、syncConversationTx read_receipt 跳过分支、websocket 2200 分支（均无害）；回执通知与 libpq RETURNING 乱码问题记为专项；25/25 测试全过、CI 全门禁绿)
**Phase 60**: libpq 结果 UAF 根因修复 + 回执功能恢复轮 - COMPLETE (深挖回执乱码：决定性实验证明仅 is_not_notification=true（conv_id 用 n_ 前缀）组合间歇触发，且**当前测试顺序下稳定通过** —— 定位到根因：`queryParamsOn` 用 `std.mem.span(PQgetvalue)` 存储 **libpq 结果内存引用**，随后 `PQclear(result)` 释放 → **所有 DB 查询结果字符串悬空**（普通路径碰巧正常因释放内存未被覆盖，间歇性乱码 = 悬空内存被连接池复用覆盖）—— 修复：结果字符串 `dupe` 到 allocator（调用方 free 语义匹配）；此修复影响**所有 DB 读路径**（潜在生产数据错乱 bug，高价值）；修复后恢复回执功能（handler 发回执 + 测试），**26/26 连续 5 次全过、0 泄漏**（之前间歇性失败不再复现）；CI 全门禁绿)
**Phase 61**: 释放模式配套修复轮 - COMPLETE (UAF 修复（dupe）后审计发现配套缺口：各 persistence 的 `freeResult`/defer 释放块只释放行数组（外层 slice），**dupe 出的内层字符串无人释放**（测试用 request arena 掩盖了泄漏）—— 统一修复 8 个文件（conversation/auth/user/third/friend/group/office/message）的释放循环：先释放行内每个 cell 字符串再释放行数组；26/26 连续 3 次全过、0 泄漏、CI 全门禁绿；剩余专项评估：配置热加载（全局单例重建成本高）、日志轮转（stderr 场景）、WS 真实连接测试（工程量大）均为非阻塞)
**Phase 62**: 非 arena 路径泄漏验证轮 - COMPLETE (新增测试：模拟非请求上下文（crontask/worker，requestAllocator=null → 结果落全局 allocator），调用 getUser 后**手动释放全部字符串字段**，SafeAllocator 验证 0 泄漏 —— 证明 Phase 60 UAF 修复（dupe）+ Phase 61 freeResult 内层释放**真实生效**（非 arena 路径无泄漏，之前测试全在 arena 下掩盖了问题）；zigmodu WebSocketClient 经查为 server 侧连接表示（无独立连接工具），WS 真实连接测试需自建握手 → 保持专项；测试从 26 增至 27 全过、0 泄漏、CI 全门禁绿)
**Phase 63**: query 路径 UAF 修复 + 冒烟门禁轮 - COMPLETE (冒烟暴露**测试未覆盖的启动崩溃**：`PostgresClient.query`（无参版）与 queryParamsOn 同样的 UAF（span libpq 内存 + PQclear 释放），main.zig 启动调 userCount → 崩溃（测试全走 queryParams 路径故未覆盖）—— 修复 query 的 dupe；随之发现 `freeQueryRows`（root.zig）只释放行数组不释放 cell（Phase 61 漏网）→ 补内层释放，根除 ensureMigrations 的 14 处泄漏；调试中尝试 IntegrationCtx arena 提前导致 allocator 不匹配连锁崩溃（模块 init 入 arena vs deinit 路由 g_allocator），**回退**该方向（原顺序下 dupe/free 同源 g_allocator 匹配）；`scripts/ci.sh` 新增 **[6/6] 冒烟门禁**（启动服务 + /health 探测，防启动崩溃回归）；27/27 连续 3 次全过、0 泄漏、服务冒烟 health 200、CI 6/6 全门禁绿)
**Phase 64**: 日志文件输出 + 轮转轮 - COMPLETE (core.logJson 增强：`initLogFile(path, max_size)` 启用 JSON 日志文件落盘（extern libc open/write/close/rename，无 std.Io 依赖、跨线程安全、`std.atomic.Mutex` 保护），写满阈值自动轮转到 `<path>.1`（libc rename）；config 新增 `[log] file`/`max_size` 段（INI + legacy 解析），main.zig 启动按配置初始化；core.deinit 清理日志 fd/路径；测试：小阈值下 logJson 3 行触发轮转（libc 读文件验证 t3 在/t1 不在 —— 踩坑：`std.testing.io` 不支持真实文件 open、extern open 需 variadic 声明 + 显式 cast（非 variadic 导致 mode 权限错乱 0o004））；测试从 27 增至 28 全过、0 泄漏、CI 6/6 全门禁绿)
**Phase 65**: 配置热加载轮 - COMPLETE (有限版热加载：config 模块新增 `reload()`（互斥锁保护，重读 config.yaml 并安全交换字符串分配，解析失败回退默认值）+ `configFileMtime()`（Io.Timestamp 纳秒）；getConfig 加锁；crontask 集成：1s 切片循环每 30s 检查 config.yaml mtime 变化 → reload（基线在启动时设置，避免启动后首个检查窗口内修改被吞）；生效范围：动态读取的值（webhook 过滤规则 allowed/denied/attention_ids、日志路径等）即时生效，连接池/端口需重启；测试：reload 安全（重读现有文件无崩溃无泄漏）；端到端冒烟验证：启动后改 config.yaml 的 allowed_types → ~30s 后 crontask 检测到变化并 reload（日志确认）；测试从 28 增至 29 全过、0 泄漏、CI 6/6 全门禁绿)

## 遗留项（Phase 35 之后）

- **gateway handler 已按域拆分**（Phase 49）：`gateway/handlers.zig` 4125 行拆为 298 行骨架 + `handlers/{helpers,auth,account,user,friend,group,message,conversation,encryption,office,organization,third,statistics,rtc,jssdk,health}.zig` 16 个域文件；新增 handler 遵循同结构
- **事务覆盖扩展**：建群/加好友/删好友/解散群/注销用户/发消息+会话同步/群批量邀请已事务化（Phase 49 遗留轮补齐）；office work moment 发布/点赞/评论评估为单语句原子操作无需事务
- **emit payload 释放**：已完成（Phase 49 遗留轮）—— user/friend/group/conversation/message 共 19 处补 `defer core.getAllocator().free(payload)`，websocket/crontask 4 处本就正确释放；新增 emit 调用点沿用该模式
- **zigmodu StructuredLogger**：key 未 dupe 崩溃 bug 已修复（commit 2b265bd，含回归测试），zim 已重新接入（core.getLogger + 启动事件 + HTTP 访问日志 JSON，实测 0 崩溃）；残留 `{any}` 把字符串字段输出成字节数组的格式问题未修 —— 补丁见 `docs/structured-logger-patch.md`，应用后 path/method 可读
- **gateway 路由已按域分组**（Phase 37）：17 个 `*_routes` const；后续如需可继续把 handler 实现拆到 `handlers/{域}.zig`
- **结构化日志**：访问日志已是每请求一行 JSON（std.log 输出）；其余模块仍为 `std.log` 风格，如需要可接 zigmodu `StructuredLogger`（修复其 bug 后）或继续 std.log JSON
- **功能对照**：消息分页/搜索增强、群公告/@提及、RTC 持久化等见 `docs/go-zig-gap-analysis.md` 与 `docs/improvement-plan.md`
- **CI 门禁**：`scripts/ci.sh` 一键五步门禁（build/test/fmt/audit/deadcode），zmodu 优先用 `.zmodu-build/bin/zmodu`（本地构建 v0.15.9，含 audit/deadcode）否则 PATH
- 约束提醒：新增路由直接写原生 `http.Context` 风格；zigmodu 本地源码需保持 binary 帧支持（`WsMessageFn(session, msg, kind)`）；`config.yaml` 为 `[section]` INI 风格；新迁移文件放到 `migrations/`，启动时自动应用

### Event Bus

Modules communicate via event-driven pub/sub backed by the core infrastructure layer:

```zig
// Emit event (via core event bus, backed by zigmodu ThreadSafeEventBus)
const eb = core.getEventBus();
eb.emit(.user_created, "user", payload);

// Subscribe to event (via core event bus)
try eb.subscribe(.message_sent, handler, "message");

// Async subscription — dispatched on a zigmodu WorkerPool instead of the publisher
try eb.subscribeAsync(.message_sent, handler, "push");
```

Event handlers in `main.zig` now include WebSocket protobuf push for `message_sent` events.
All event types are defined centrally in `core.zig` for type safety across modules.

### API Routes (Gateway)

**Auth**: `POST /auth/get_user_token`, `POST /account/login`, `POST /account/register`, `POST /auth/verify`  
**Gateway**: zigmodu `http.Server`（10000 端口）+ ComptimeRouter 185 条声明式路由；鉴权走 `authMiddleware`（公开路径白名单 + token 校验），CORS/OPTIONS 由 `corsMiddleware` 处理；handler 保持旧 `HttpRequest/HttpResponse` 模型，由 `bridge()` 适配层转发  
**User**: 18 endpoints including `/user/get_all_users_id`, `/user/search_users`, `/user/get_users_online_status`  
**Friend**: 22 endpoints including `/friend/add_friend`, `/friend/get_black_list`  
**Group**: 28 endpoints including `/group/create_group`, `/group/transfer_group`  
**Message**: 21 endpoints including `/msg/send_msg`, `/msg/pull_msg_by_seq`  
**Conversation**: 11 endpoints including `/conversation/get_sorted_conversation_list`  
**Office**: 11 endpoints including `/office/work_moment/add`, `/office/work_moment/like`  
**Organization**: 5 endpoints  
**Third**: 7 endpoints (`/third/fcm_update_token` with DB persist, `/object/auth_sign` with presigned URL, `/object/access_url`, `/third/logs/upload`, `/third/logs/search`)  
**Statistics**: 4 endpoints (`/statistics/user/register`, `/statistics/group/create`, etc.)  
**RTC Meeting**: 19 endpoints with in-memory room state (`/rtc-meeting/create`, `/rtc-meeting/join`, etc.)  
**Prometheus**: `/metrics` endpoint  

## Important Notes

- **DO NOT modify** anything in `_ref/` - it's reference material only
- The Flutter/Expo frontend communicates via WebSocket + REST - keep the same API contracts
- Module dependencies are declared via `zigmodu.api.Module.dependencies`
- `main.zig` uses `zigmodu.Application.init()` builder pattern with graceful shutdown (`app.run()`)
- **Core infrastructure** (`src/core.zig`) provides unified allocator, DI Container, event bus, and logger to all modules
- All modules use `core.getAllocator()` instead of `std.heap.page_allocator` for memory management
- All modules include `comptime { core.validateModule(@This()); }` for compile-time boundary validation
- Events flow via `core.getEventBus().emit()` / `.subscribe()`
- WebSocket connections support handshake token auth via URL query params (`?sendID=xxx&token=xxx`)

## Frontend Integration (Flutter + Expo)

All API responses are camelCase to match OpenIM SDK expectations:

| Zig (PostgreSQL) | Frontend JSON |
|------------------|-------------|
| `user_id` | `userID` |
| `face_url` | `faceURL` |
| `nickname` | `nickname` |
| `conversation_id` | `conversationID` |
| `recv_msg_opt` | `recvMsgOpt` |
| `is_pinned` | `isPinned` |
| `max_seq` | `maxSeq` |
| `latest_msg_send_time` | `latestMsgSendTime` |
| `friend_user_id` | `friendUserID` |
| `owner_user_id` | `ownerUserID` |
| `group_id` | `groupID` |
| `group_name` | `groupName` |
| `creator_user_id` | `creatorUserID` |
| `sender_id` | `sendID` |
| `receiver_id` | `recvID` |
| `sender_face_url` | `senderFaceUrl` |
| `app_manager_level` | `appMangerLevel` |
| `msg_id` | `serverMsgID` / `clientMsgID` |

### Conversation ID Format (Aligned with Go OpenIM)

| Type | Format | Example |
|------|--------|---------|
| Single chat | `si_{sorted(user1, user2)}` | `si_userA_userB` |
| Group chat | `sg_{group_id}` | `sg_group123` |
| Notification single | `n_{sorted(user1, user2)}` | `n_userA_userB` |
| Notification group | `n_{group_id}` | `n_group123` |

### Friend Info JOIN
`GET /friends` and `GET /friend_requests` JOIN the `users` table so frontend gets `nickname` and `faceURL` without extra calls.

### WebSocket Protocol
- **Binary frames**: Protobuf v3 codec (`proto/protobuf.zig`) with full `MsgData`, `PullMessageBySeqsReq/Resp`, `GetMaxSeqReq/Resp`, `UserSendMsgResp`, `GetSeqMessageReq/Resp` support.
- **JSON wrapper**: `{"reqIdentifier":1003,"sendID":"...","data":"base64(protobuf_bytes)"}`
- **Supported identifiers**:
  - `1001` GetMaxSeq
  - `1002` PullMsgBySeqList
  - `1003` SendMsg
  - `1005` PullMsg/GetSeqMessage
  - `2001` PushMsg (server → client protobuf push)
  - `2002` KickOnlineMsg
  - `2003` LogoutMsg
  - `2004` SetBackgroundStatus
  - `2005` SubUserOnlineStatus
  - `2100` ServerConfigMsg (reserved)
  - `3001` DataError
- **Handshake auth**: `ws://host:port?sendID=xxx&token=xxx&platformID=1`

### Integration Test Steps

```bash
# 1. Start PostgreSQL and run migrations
psql -h localhost -U zim -d zim -f migrations/001_initial.sql

# 2. Start zim server
cd src && zig build run

# 3. Configure Flutter SDK
# In your Flutter app's initialization:
#   OpenIM.iMManager.initSDK(
#     apiAddr: 'http://localhost:10000',
#     wsAddr: 'ws://localhost:10001',
#     ...
#   )

# 4. Configure Expo / React Native SDK
#   OpenIM.initSDK({
#     apiAddr: 'http://localhost:10000',
#     wsAddr: 'ws://localhost:10001',
#     platformID: 1, // iOS=1, Android=2, Web=5
#     ...
#   })
```

## Framework

[zigmodu](https://github.com/chy3xyz/zigmodu) v0.15.9 (local source `~/w4_proj/zig_ws/zigmodu`, HEAD 4a70ade = 远程 master 同步；v0.15.7 的 5 个本地增强提交已并入 v0.15.8 官方发布线；Zig toolchain 0.17.0-dev.1422) provides:
- Module system with lifecycle (init/deinit)
- Dependency validation at startup
- Event bus (`TypedEventBus`, `ThreadSafeEventBus`) for decoupled communication
- `ThreadSafeEventBus.subscribeAsync` + `WorkerPool` for async event dispatch
- DI container (`Container`) for services
- `Application` builder pattern with graceful shutdown (`app.run()` handles SIGINT/SIGTERM)
- `ApplicationBuilder` fluent API for step-by-step configuration
- Per-module `RuntimeOptions` (bulkhead / rate limiter / circuit breaker / worker pool) via `zigmodu.ModuleRuntime`
- `ApplicationObserver` for lifecycle events
- `HealthEndpoint` for health checks
- `observability.PrometheusMetrics` for real Prometheus `/metrics` output
- `CircuitBreaker`, `RateLimiter`, `Bulkhead` for resilience patterns
- `sqlx` / `orm` / `SqlxBackend` for data persistence
- `security.PasswordEncoder` (PBKDF2-HMAC-SHA256) / `AppSecurity` for auth
- `Cache` (LRU) for caching
- `IntegrationTest` / `Benchmark` / `ContractTestRunner` for testing

## Code Generator (zmodu)

[zmodu](https://github.com/chy3xyz/zmodu) is the official CLI scaffolding tool for zigmodu:

```bash
# Generate full project from SQL schema
zmodu scaffold --sql schema.sql --name myapp --json-style camel

# Add modules to existing project
zmodu add --sql new_tables.sql

# Generate standalone module
zmodu module user
```

The current zim project was manually crafted but follows zmodu conventions for module structure and API patterns.
