# AGENTS.md - Zig IM Server (zim)

## Project Overview

**Goal**: Rewrite OpenIM Server (Go → Zig) using [zmodu](https://github.com/chy3xyz/zmodu) framework.
**Flutter/Expo frontend** (`_ref/openimsdk-open-im-flutter-enterprise/`) does NOT need changes.

## Repository Structure

```
zim/
├── src/                      # Zig application
│   ├── main.zig              # Bootstrap with zmodu Application API
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
│   │   ├── gateway.zig        # HTTP + WebSocket server (188 routes)
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
| gateway | ✓ | zmodu http.Server + ComptimeRouter（188 条声明式路由，含 RTC 会议） |
| queue | ✓ | PGMQ message queue (PostgreSQL-backed) |
| push | ✓ | Online push via WS 2001, offline queue via PGMQ, DND filter |
| third | ✓ | RustFS S3-compatible presigned URLs, FCM token storage, logs, webhook queue |
| crontask | ✓ | Background tasks: message cleanup, auth token cleanup, webhook delivery |
| websocket | ✓ | WebSocket server + OpenIM protobuf protocol |
| office | ✓ | Work Moments (enterprise): publish/like/comment/permissions |
| organization | ✓ | Organization structure (enterprise): departments, recursive query |
| rtc_persistence | ✓ | RTC meeting state in PostgreSQL (Phase 84): rooms survive restarts, TxClient create/close, stale-room archive on start |

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
- INI 风格 `[section]` 段（由 zmodu `YamlParser` 解析）：`[database]`、`[gateway]`、`[jwt]`、`[redis]`、`[queue]`、`[object_storage]`、`[webhook]`，键为 `http_port` / `ws_port` / `secret` 等
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
**Phase 66**: 可观测性 + 契约覆盖 + RTC 内存修复轮 - COMPLETE (①慢查询日志：queryParamsOn/query/exec 三路径计时，>=200ms 输出 `db_slow_query`/`db_slow_exec` JSON；②metrics 扩展：新增 `zim_push_sent_total`/`zim_push_failed_total`/`zim_queue_depth`/`zim_db_query_duration_seconds` 指标（push 发送接线 + DB 延迟直方图），修复 deinitMetrics 漏清理新指针导致的跨测试悬空崩溃；③cross-domain 契约测试：statistics/office/rtc/organization/third 五个域 5 端点（Testkit + token），测试 29→30；④**发现并修复 RTC 3 个真实内存 bug**：RTC 数据用请求 arena（getAllocator）存全局 map → 请求结束悬空（改全局 dupe）；create 的 host_z 同时存入 meetings.host_user_id 与 participants.user_id（同指针）→ deinit 双释放（participant 独立 dupe）；meetings 的 value.room_id 与 key 同指针 → deinit 双释放（只 free 一次）；gw_root.deinit 补 RTC map 完整清理（IntegrationCtx.deinit 调用）；30/30 连续 3 次全过、0 泄漏、CI 6/6 全门禁绿)
**Phase 67**: WS 限流 + 大群分块 + token 评估轮 - COMPLETE (①WS 握手限流：每 IP 每秒 30 次握手窗口（`allowHandshake`，StringHashMap + 命名 HandshakeWindow 类型，key dupe 后 deinit 可释放 —— 踩坑：匿名 struct 类型不匹配、getOrPut key 未 dupe 导致 free 字面量崩溃），onConnect 入口接入（RequestUtil.getRealIp），deinit 在模块 init 检查前清理限流状态（测试未 init 也能释放）；测试：同 IP 30 次内通过/第 31 次拒绝/不同 IP 不受影响，测试 30→31；②大群批量分块：`upsertWithLatestBatch` 按 500 行/块分片执行（防 PG 65535 参数上限与 1MB 语句上限，5000+ 成员群不崩，事务内仍原子）；③token 刷新评估：Go auth 模块无 refresh token 机制（仅 auth.go，token 到期重新登录）→ 对齐 Go 不实现；31/31 全过、0 泄漏、CI 6/6 全门禁绿)
**Phase 70**: 质量提升轮（9.5 分目标）- COMPLETE (①工程：新增 `.github/workflows/ci.yml`（GitHub Actions：PG 服务 + build/test/fmt/audit/deadcode/smoke，zigmodu checkout 路径对齐 build.zig.zon 的 ../../../zig_ws）；②安全：gateway 加 CSP 头（default-src 'none'，JSON API 合理）、`[jwt] require_strong_secret` 配置（true 时弱 secret 拒绝启动）；③可观测：crontask 定期上报 PGMQ 队列深度 metric（queueDepth，pgmq 缺失时 0）；④性能：ReleaseFast 基准对比（login 4→75 ops/s ~19x，friend 2597、group 1770、msg 664 ops/s），生产建议 ReleaseFast 构建；⑤测试：handler 契约测试扩展（user/group/conversation 域，31→32），**抓出并修复真实契约偏差**：get_groups_info 响应 groups→groupInfos（对齐 Go GetGroupsInfoResp）；buildTestServer 移除 requestArenaMiddleware（其 defer 置空 requestAllocator 导致后续 service 结果泄漏）；⑥WS 真实连接测试：`scripts/ws_smoke.py`（标准库自建握手 + GetMaxSeq 1001 protobuf 请求）实测握手 101 + 协议响应，接入 ci.sh [6/6] 冒烟；zigmodu v0.15.16 适配（零代码改动）；32/32 测试全过、0 泄漏、CI 6/6 全门禁绿（含 WS 冒烟）)
**Phase 69**: zimapp 检查与改善轮 - COMPLETE (检查结论：zim_sdk 纯 Dart 直连后端（HTTP 10000 + WS 10001），登录/消息/WS 契约已对齐，架构健康；改善落地：①配置页默认端口修正（IP 模式 authCtrl/imApiCtrl 10008/10002 → 10000 —— 原为 chat 服务端口，连不上 IM 后端）；②splash 首次连接引导（检测无 serverIP 配置 → 自动进入 ServerConfig 页，部署友好）；③密钥可配置化（webKey/webServerKey/githubClientId 硬编码）因 flutter 工具链权限受限（engine.stamp Operation not permitted，无法编译验证）暂缓记录；RTC 会议前端缺失记为最大功能缺口（需会议 UI，工程量大）；flutter analyze 无法运行（环境权限）—— 前端改动需在 Flutter 环境人工验证）
**Phase 68**: 前后端联调轮 - COMPLETE (真实联调：后端启动（10000/10001）+ admin 前端（umi 8001，8000 被 php 占用）+ curl 全链路验证（注册 user 嵌套格式/登录 account 字段 imToken/加好友 add_friend_response/单聊群发/会话列表含群成员同步/pull_msg_by_seq key 为 messages/已读/在线状态）；**联调发现并修复 2 个真实问题**：①CORS 预检拒绝前端 SDK 的 `operationid` 自定义头 → corsMiddleware 白名单补 operationid + 预检回显 `Access-Control-Request-Headers`（任意自定义头放行）；②`/account/login` 的 LoginReq.platform 缺默认值（前端 SDK 省略 platform → bindJson InvalidJson 400）→ 加默认 1（对齐 RegisterReq）；admin 登录密码前端固定 MD5 → 改前端传明文（zim 用 PBKDF2，与 Go chat 的 MD5 存储体系不同）；**联调边界**：admin 6 个 chat 专属管理 API（allow_register/get、block/search、default/user|group/search、application/page_versions、organization/get）缺失 —— chat 服务（open-im-chat）未重写，超出 IM 范围；zimapp（Flutter）需模拟器（headless 不可行）；puppeteer MCP 不可用（启动超时）；31/31 全过、CI 6/6 全门禁绿)

## Phase 71: 前端 zimapp 质量评估 + 提分基础（评估 5.5/10）

- 前端评估：架构分层 7（zim_sdk/openim_common/working_circle 本地包体系）、状态管理 7（get）、
  **测试 3**（zimapp 业务逻辑 0 测试）、质量 5（chat_logic 3191 行）、安全 4（webKey 硬编码）、可观测 6
- **密钥配置化**（已完成）：`openim_common/config.dart` 的 webKey/webServerKey 改 getter（优先 DataSp 读，
  新增 `DataSp.webKeyKey`/`webServerKeyKey`），默认值回退 —— 生产可覆盖
- **协议契约测试**（新增未验证）：`zim_sdk/test/message_model_test.dart`（Message/UserInfo fromJson 契约）
- **拆分方案文档**：`docs/flutter-improvement-plan.md`（chat_logic 3191 行 → 5 个 mixin 拆分清单 + 测试/CI/上报路线）
- 约束：**Flutter 工具链在沙箱不可用**（~/ws_flutter 不可写）—— 前端代码改动需 Flutter 环境
  `flutter analyze` + `flutter test` 验证后合入；当前只合入低风险改动

## Phase 72: 前端 zimapp 提分（工具链恢复 + analyze 清零 + 协议测试 + CI 门禁）

- **沙箱放开**：`reasonix.toml`（项目级）`bash = "off"` + `allow_write` 含 `~/ws_flutter` 与 zigmodu —— flutter/dart 工具链恢复可用
- **analyze 清零**（2211 → 0 error / 21 warning / 117 issues）：
  - 排除死包 `flutter_openim_sdk`/`local_plugin`（无引用残留）；给 openim_common/working_circle/organization/zim_sdk 补 `publish_to: none` + 子包 `analysis_options.yaml`（根包配置不传播）
  - 各子包补 `dart pub get`（缺失 package_config 导致 50 个假 uri_does_not_exist error）
  - 修复真实 bug：chat_input_box `_SubView` 复制粘贴错误（content 分支渲染 `title!`）、apis.getClientConfig 不可达死代码、preview_picture_view 死代码、photo_browser_bottom_bar 参数 `this.` 丢失、3 处 unreachable_switch_default、2 处 catchError 返回 void
  - **注意**：`dart fix --apply` 会引入错误（给 AppNavigator/Apis 加 `Future?` 显式类型、删 const 构造/字段参数）—— 使用后必须 analyze 复核，必要时 `git checkout` 回滚
  - 已知保留：get 4.7.3 `Rx.value` protected lint（analysis_options ignore，get 升级时复评）、unused 死代码（删除需连带赋值语句，风险高，注释说明后 ignore）
- **协议契约测试**：`zim_sdk/test/message_model_test.dart` 4 个测试全过（`flutter test` 可用；`flutter analyze` 自身崩溃（analysis server 退出 64）用 `dart analyze` 替代）
- **CI 前端门禁**：GitHub Actions 新增 `frontend` job（flutter-action 3.35.7 + 各包 pub get + `dart analyze` 0 error 门禁 + zim_sdk flutter test）
- **密钥配置化**（Phase 71 修正）：`DataSp.getWebKey()/getWebServerKey()` 同步静态方法（非 getString）+ config.dart getter 读之（修正了之前不存在的 DataSp.getString 调用）

## Phase 73: chat_logic 3191 行拆分（前端质量 5→8 的 P0 项）

- **拆分完成**：`lib/pages/chat/chat_logic.dart` 3191 → **1880 行**，按职责拆出 4 个 mixin（`part of` 共享库作用域，私有成员可达，零行为变化）：
  - `ChatSendLogic`（chat_send_logic.dart，45 方法/818 行）：发送/转发/媒体/删除/输入状态
  - `ChatMsgDisplayLogic`（chat_msg_display_logic.dart，20 方法/342 行）：消息展示/点击/引用/草稿
  - `ChatHistoryLogic`（chat_history_logic.dart，11 方法/214 行）：分页拉取/滚动监听/未读/在线状态
  - `ChatMentionLogic`（chat_mention_logic.dart，4 方法/70 行）：@提及映射/解析
- **架构**：`abstract class ChatLogicBase extends SuperController`（字段 + 生命周期 + 骨架）→ `class ChatLogic extends ChatLogicBase with ChatSendLogic, ChatMsgDisplayLogic, ChatHistoryLogic, ChatMentionLogic`
- **抽象声明桥**：基类对 mixin 方法声明抽象（`void _sendMessage(...);` 等），运行时 resolve 到 mixin 实现 —— 解决"基类方法调用 mixin 方法"的循环约束
- **过程中修复**：花括号配对提取器（parens/in_str 跨行 + 泛型 record `({...})` 跳过 + 箭头函数单行 + 方法名行号排序），`directionalText` 括号错位导致 exit 方法被嵌（exit 成局部函数）已重排修复
- **结果**：`dart analyze` 0 error / 24 warning（拆分前 0/21，抽象声明 lint 微增）、`flutter test` 4/4 全过、CI 前端门禁（analyze 0 error + flutter test）就绪
- **教训**：dart 方法提取必须处理（多行签名 parens 跨行、字符串字面量花括号、`({` record 类型、`=>` 箭头函数、无返回类型方法）；删除按行号降序；每步 analyze 验证

## Phase 74: Flutter ↔ zim 后端数据打通（zim_sdk 真实集成测试）

- **集成测试**（`zim_sdk/test/backend_integration_test.dart`，flutter test，需后端运行）：注册→登录→加好友→SDK 发消息→会话自动同步→seq 拉取→未读→标记已读，**全链路真实 HTTP(:10000)/WS(:10001) 通过**
- **修复 zim_sdk 真实 bug（6 个）**：
  1. `getLoginStatus` 未登录返回 logging(2) → login 跳过实际登录（token 未设置 → 后续 401）→ 改返回 logout
  2. `invokeMethod` 泛型推断在 `=>` 箭头链退化（`Future<dynamic>` vs `Future<Message>`）→ createTextMessage/sendMessage 改 async/await
  3. `Utils.toObj` 泛型未指定 → 运行时类型错（4 个 manager 补显式 `<T>` + `is T ? value as T`）
  4. `cleanMap` 修改调用方不可变 map → 复制后删除
  5. `local_db` sqflite：嵌套 Map 参数（JSON 序列化 + camel/snake 列名映射（含 ID 缩写）+ PRAGMA table_info 列过滤）
  6. `sendMessage` 参数 `userID` → `recvID`（method_channel 读 recvID，空值 → 后端 NotFriend）
- **契约核对**：后端 SendMsgResp 无 sendID（Go 契约）；get_sorted_conversation_list 的 conversationElems 为平结构（conversationID/msgInfo 平铺）
- **CI**：frontend job 新增"构建后端 + 启动 + E2E 集成测试"门禁
- 测试：zim_sdk 5 个（4 契约 + 1 集成）全过，analyze 0 error

## Phase 75: zigmodu v0.15.16 → v0.15.22 适配

- **升级**：v0.15.22（本地=远程同步）；变更：http AccessLogger/HttpMetrics 线程安全修复、sqlx libpq 超时/中断、outbox/audit/ai 新增 —— **API 面兼容**
- **验证**：zig build 0 error、32/32 测试、CI 6/6 全绿（无代码适配）
- **横幅**：main.zig Framework: zigmodu v0.15.22；CI zigmodu ref 更新 v0.15.22
- **端到端**：v0.15.22 后端 + flutter zim_sdk 集成测试全过（数据打通持续验证）

## Phase 76: zigmodu v0.15.22 → v0.15.36 升级 + zent ORM 接入试点

- **zigmodu v0.15.36 升级**（本地 `zig_ws/zigmodu` 已被用户更新至 66b4b06=v0.15.36，含 1 个向后兼容本地补丁：`Middleware.zig` moduleGate `skip_prefixes` 可配置化，默认行为不变）：v0.15.22..v0.15.36 共 42 commits（accept 循环 concurrent 派发修复 keep-alive 挂死、stop 前 shutdown listener 修复、EventBus/DI 接入 Application、sqlx 读写分离、可插拔 AuthBackend、`bindJsonLoose`/`extractJsonLoose` camelCase+null 容错等）——**API 面兼容零代码改动**；横幅/启动 JSON/CI ref 三处版本号更新；实测 zig build + 32/32 测试 + `scripts/ci.sh` 6/6 全绿
- **zent v0.34.0 接入试点**（评估结论：可行，zent=数据层 ORM 与 zigmodu=应用框架正交，`zmshop_zent` 为参考实现；详见 `docs/zent-migration.md`）：
  - 依赖：`build.zig.zon` 加 `zent` path 依赖（fingerprint 0xc7cc6523fbab2ba2）；`build.zig` exe+tests 模块 `addImport("zent",...)`（libpq 链接复用 zigmodu sqlx 已有的 `-lpq`，头文件 discovery 由 zent 自己的 build 完成）
  - 新文件：`zent_schemas.zig`（users 表 Schema-as-Code 映射，SELECT 按列生成、未声明列不触碰）+ `zent_db.zig`（`ConnPool(PostgresDriver)` min1/max4 + `health_check_on_borrow=false`（zmshop 踩坑：ping-under-mutex 死锁）+ 配置串 dupe 防 config 热加载悬空 + client 持有 + `deinitRow` 内存契约助手）
  - main.zig：`app.start()` 后初始化，**非致命**（失败仅 JSON 告警，db_postgres 仍是权威路径）；停机 LIFO 先关 zent 池；实测启动日志 `zent ORM layer ready (pilot: users)`
  - 测试：新增双向互通集成测试——zent `crud_helpers` create/update/first/delete ↔ `user.getUser` 交叉读写同一 users 表（String 主键 user_id；踩坑：`entity_info` 是类型级声明须经 `@TypeOf(client.user).entity_info` 访问、局部变量名 `u2` 遮蔽 Zig 原生类型），测试后 DB 0 残留；**33/33 全过、CI 6/6 全绿**
- 后续迁移路线（只读域 → 低冲突 CRUD 表 → 核心域事务）见 `docs/zent-migration.md`

## Phase 77: zent 第一批迁移切片 + CI 可移植性修复

- **zent 迁移切片 1**（模式：双路径回退 —— `zent_db.getClient()/getDriver()` 优先，层不可用走 legacy db_postgres，零行为变化；详见 docs/zent-migration.md「迁移模式」）：
  - `collects` 全 CRUD：`addCollect`/`getCollects` → `zent.sql_scan.queryOne/queryAll`（INSERT..RETURNING / 动态 IN 子句，计算列加别名后按列名直接扫进 `model.Collect`，无中间 DTO）；`removeCollect` → `crud_helpers.delete`（Collect schema，id+user_id 双谓词保持归属校验）
  - 统计聚合 4 处手工行解析（dupe+parseInt+freeResult 循环，Phase 60 UAF 高发区）→ `sql_scan.queryAll`：`user.countByDay`、`group.countByDay`、`message.activeDateCount`、`message.activeTopEntities`（JOIN 查询列别名对齐 TopEntity 字段）
  - `zent_schemas.zig` 加 Collect schema（UUID pk；create_time TIMESTAMPTZ 不入实体 —— epoch 读经 RETURNING/SELECT EXTRACT）；`zent_db.zig` 加 `getDriver()`
  - 测试基建：`IntegrationCtx.init` 在 PG 可用时同步初始化 zent 层（全部集成测试自动走 zent 路径，不再静默回退），deinit 幂等；新增 collects 服务层测试（含归属校验：他人行不可删）；**34/34 全过、DB 0 残留、CI 6/6 全绿**
- **zigmodu 本地补丁 2**：`ModuleGraph.zig` findCycle 加 `@setEvalBranchQuota(100_000)`（comptime 环检测 O(modules²·name_len) 超默认 1000 分支预算，17 模块图在重编译时触发；向后兼容、可上游）
- **CI 可移植性**（此前 GitHub CI 从未跑过，workflow 有多处环境错误）：
  - `src/build.zig` libpq include 从硬编码 `/opt/homebrew/opt/libpq/include` 改为发现式（pg_config → Homebrew keg 回退，同 zent build.zig 模式）—— Linux/macOS 通用
  - workflow 重写：zig 改为 ziglang.org 直连 tarball（setup-zig 对 dev 版 404，同 zigmodu CI 模式，pin dev.1970）；补 `apt-get libpq-dev` + zent v0.34.0 checkout（两个 job）；frontend job 补 PG service（e2e 需要）+ zig 安装（原来缺失）；修复 e2e 步骤硬编码 `/Users/runner` macOS 路径 → 相对路径；`kill %1` 跨 step 无效 → `pkill -f`；fmt 清单补 zent_db/zent_schemas（ci.yml 与 scripts/ci.sh 同步）
- **清理**：删除 `src/modules/gateway.zig.bak`（Phase 49 拆分遗留，git 跟踪的死文件）

## Phase 78: zent 迁移切片 2 — auth/third 全量低冲突表

- **迁移范围**（沿用 Phase 77 双路径回退模式，零行为变化）：
  - `auth_tokens`：`storeToken`/`deleteByUser` → `drv.exec`（expire_time 为 `NOW()+INTERVAL` SQL 计算列）；`parseToken` → `sql_scan.queryOne(TokenInfo)`（EXTRACT 加别名按列名扫进模型）
  - `auth_verification_codes`：60s 限流检查 → `queryOne(bool DTO, CASE..AS recent)`；upsert 与一次性消费 DELETE → `drv.exec`；`checkVerificationCode` → `queryOne` + `freeDto` 显式释放一次性 DTO
  - `fcm_tokens`/`app_logs`/`webhook_events`（third 模块）：写入（含 NOW() 计算列的 upsert/INSERT/UPDATE）→ `drv.exec`；`getFCMToken`/`getPendingWebhookEvents` → `sql_scan.queryOne/queryAll`
- **写语句选型确立**：含 SQL 计算列的语句走 `drv.exec(原 SQL, args)`（语义零变化、无需实体 schema）；纯谓词删除/更新才引入 schema 走 `crud_helpers`（见 docs/zent-migration.md「迁移模式」）
- **测试**：新增 token 生命周期（login→parseToken→forceLogout→InvalidToken）、验证码（60s 限流/错码不消费/正码一次性消费/消费后可重发）、FCM（(user,platform) upsert 覆盖 + 跨平台隔离）、webhook（queue→pending→delivered）单测；**35/35 全过、CI 6/6 全绿、Flutter e2e 全过**（登录链路 storeToken/parseToken 现走 zent pool，真实 HTTP/WS 验证）
- 发现保留（未改，零行为变化原则）：`checkVerificationCode` 的手机号 key 硬编码空 area_code（`":phone"`）而 `createVerificationCode` 用 `area_code orelse ""` —— 非空 area_code 发码后 verify 永远对不上，属既有 bug，修复需评估 handler 调用方，记为后续

## Phase 79: area_code 验证码 bug 修复 + office 全量迁移（低冲突层收尾）

- **area_code bug 修复**（Phase 78 发现的既有 bug）：verify 链路把 areaCode 丢了 —— handler `VerifyCodeReq` 无 areaCode 字段、`auth.verifyCode`/`service.verifyCode`/`checkVerificationCode` 均无参数，key 硬编码 `":phone"`，而 send 用 `"{areaCode}:{phone}"` → 带区号发码永远验证失败。修复：四层线程化（handler 请求结构加 areaCode → wrapper → service → persistence key 构造统一 `area_code orelse ""`），新增回归测试（"+86 手机号发码→验证成功"，修复前必挂）
- **office 全量迁移到 zent**（沿用双路径回退，零行为变化）：
  - 工作圈读路径（4 处 12 列 JOIN 查询 get/getRecvList/getSendList/findRelevant）→ `sql_scan.queryAll(model.WorkMoment)`（别名对齐后按列名直扫）；create → `queryOneLenient`（RETURNING 无 JOIN 列，缺席 face_url/nickname 保持 ""）
  - 点赞/取消赞/评论/删评论/清已读（JSONB 追加与数组过滤更新、user_read_times upsert）→ `drv.exec`；unread/recvCount → `queryOne({count:i64})`；getUserReadTime → `queryOne(?i64 DTO)`（NULL 安全）
  - tags CRUD：`TagRow` DTO 中转（model.Tag 的 user_id_list 非列字段）+ tag_members 子查询填充成员；字符串所有权转移给返回值（只释放列表缓冲）
  - clientConfig → `queryOne(model.ClientConfig)`，错误/空行回退默认值
- **踩坑（已记 docs/zent-migration.md）**：①zent 驱动不带类型 OID，`jsonb_build_object('k', $N)` 的 any 形参令 PG 报 `could not determine data type` → zent 分支裸参数加 `$N::text`/`$N::bigint` 显式转型；②PG jsonb 文本输出在冒号后带空格（`"userID": "x"`），断言搜索勿用无空格格式；③`Managed.deinit()/toOwnedSlice()` 均为 0 参（Managed 自带 allocator）
- **测试**：新增工作圈全生命周期（发圈→JOIN 读→点赞幂等→评论→双方 unread→清已读→收/发/相关列表→标签建改删成员）+ area_code 回归，**37/37 全过、CI 6/6 全绿、Flutter e2e 全过**

## Phase 80: zent 迁移切片 4 — conversation 全量（核心域第一片，最佳实践对齐）

- **迁移范围**（对照 zent docs/BEST_PRACTICES.md 决策表逐方法选型）：
  - **typed 旗舰**：`upsertWithLatest` → `SaveOrUpdateOnWith(&.{"owner_user_id","conversation_id"}, exprs)` —— UNIQUE 业务键冲突目标，max_seq/group_at_type 单调列用 `GREATEST({t:col},{x:col})` 模板、update_time 用 `NOW()` expr；**comptime 类型守卫** `@TypeOf(exec) == *db_mod.PostgresClient`（生产调用全 Tx-bound 留 legacy，事务原子性不混池；zent 分支待 TxClient 迁移激活，测试以 plain client 直调覆盖）
  - **typed builder**：`delete` → `crud_helpers.delete`（双谓词）；`count` → `q.Count()`
  - **raw-by-design**（§1 决策表钦定）：`update`（动态 SET + 非 schema 的 update_time 列）与 `updateSeq` → `drv.exec` 原语句过 zent 池；`get`/`getByOwner`/`getByOwnerSince`/`getEncryptionKeys` → `sql_scan` DTO（EXTRACT epoch 表达式投影）；`genEncryptionKey` → queryOne(MAX) + drv.exec
  - **保留 legacy**：`upsertWithLatestBatch`（仅 Tx-bound 调用，批量分块语句留待 TxClient）、`create`（INSERT..RETURNING 无变化需求，惰性）
- **新增 schema**：`Conversation`（22 列；create_time/update_time/latest_msg_destruct_time TIMESTAMPTZ 不入实体）
- **踩坑（记入 zent-migration.md「BEST_PRACTICES 对齐」节）**：①`sql_scan` comptime zeroInit 无法处理无 0 tag 的 enum（ConversationType 从 1 起）→ `ConvRow` i16 中转 DTO + `@enumFromInt` 物化；②`setFieldValue` 类型精确匹配（i16 → `@as(i64, v)`）；③typed `setExprArgs` 对非 schema 列报 UnknownField —— 动态 SET 走 raw 是文档钦定边界而非妥协；④**惰性编译翻出既有 bug**：`ConversationService.delete` bool 签名 + `try` 函数体从未编译（无调用方），首次测试调用即暴露 → 修为 `!bool`（module wrapper 同步）
- **测试**：新增 conversation 生命周期（upsert 插入→**低 seq 不回退**（GREATEST 单调）→latest_msg 前进→group_at_type 3 压 2→部分更新不触 seq→updateSeq 绝对值→列表/增量读（ConvRow 桥）→count→delete）；**38/38 全过、CI 6/6 全绿、Flutter e2e 全过**（get_sorted_conversation_list 会话列表经 zent 路径服务真实 SDK）

## Phase 81: zigmodu v0.15.36 → v0.39.11 + zent v0.34.0 → v0.91.0 双升级适配

- **zigmodu v0.39.11 适配**（4 处 fallible 化 API）：
  - `http_middleware.securityHeaders(null)` → 返回 `error{OutOfMemory}!Middleware`（加 try）
  - `http.openApiFromCatalog(&g_slot, cfg)` → 返回 `error{SlotPoolExhausted}!HandlerFn`（startHttpServer 内 catch 返回）
  - `security.PasswordEncoder.init(allocator)` → `init(allocator, io)`（`core.getIo()` 接线；auth/user service 3 处）
  - `PasswordEncoder.matches` → 返回 `error{MalformedStoredHash,OutOfMemory}!bool`（verifyPassword `catch false`，坏 hash 行按"不匹配"处理 —— auth fail-closed）
  - zigmodu 此前 2 个本地补丁（moduleGate skip_prefixes、ModuleGraph findCycle 配额）已并入上游 tag；本地 HEAD c28ab42 = v0.39.11+5（CI pin v0.39.11 tag，兼容范围内）
- **zent v0.91.0 适配**（1 处策略变化）：**文本主键必须调用方提供**（v0.84+ 跨方言一致性政策：PG 拒绝 NULL 而 SQLite 接受 → RETURNING 拿回 NULL）—— conversation zent upsert 分支补 `generateUuidV4`（OS CSPRNG + RFC 4122 v4 位）显式设 id，upsert 表达式加 `{t:id}` 冲突时保留旧 id（legacy 分支仍走表默认 uuid_generate_v4()，行为不变）；其余 API（ConnPool/PostgresDriver/sql_scan/crud_helpers/SaveOrUpdateOnWith/deinitEntity）零改动兼容
- **验证**：38/38 测试全过、CI 6/6 全绿、冒烟启动横幅 `zigmodu v0.39.11` + `zent ORM layer ready`；**Flutter e2e 本轮未跑**——flutter SDK 已从机器移除（`~/ws_flutter/flutter` 不存在，.zshrc PATH 失效），恢复 SDK 后需复跑（CI frontend job 不受影响）
- **版本引用**：main.zig 横幅/启动 JSON → v0.39.11；ci.yml ZIGMODU_VERSION=v0.39.11、ZENT_VERSION=v0.91.0（含两 job checkout ref）

## Phase 82: ZigModu → zmodu 改名适配（v0.39.11 → v0.42.0）+ zent v0.91.0 → v0.97.0

- **改名适配**（上游 `feat!: rename ZigModu to zmodu`，GitHub 仓库 chy3xyz/zigmodu → chy3xyz/zmodu，包名 `.zmodu`、module 名 `zmodu`、fingerprint 更新为 0xde7987a02b121580）：
  - `build.zig.zon`：依赖键 `.zigmodu` → `.zmodu`（补 fingerprint 字段；path 仍指本地目录 `zig_ws/zigmodu`——目录未改名）
  - `build.zig`：`b.dependency("zmodu")` + 4 处 `addImport("zmodu", zmodu_dep.module("zmodu"))`（exe/tests/bench/core）
  - 43 个源文件 `@import("zigmodu")` → `@import("zmodu")`，本地常量名 `const zigmodu` → `const zmodu` 全量 sed（含注释/日志文案）
- **API 破坏 1 处**：v0.40.0 删除 `http.RouteGroup` 与 `Server.group()`，运行时注册收敛到 `Router.scope()` 的 `Scoped` 面 —— websocket `startServer` 的 `server.group("").ws(...)` 迁移为 `Router(WsState).init(io, allocator, server, &state)` + `scope("").ws(...)`（ws 路由不走 catalog，无需 finish；签名与旧 group.ws 一致）
- **API 兼容确认**：gateway 的 `router.scope("")`+`mountAll`+`finish()`（ComptimeRouter 面）不受 RouteGroup 移除影响；securityHeaders/openApiFromCatalog/PasswordEncoder 等 v0.39.11 适配保持原样
- **zent v0.91.0 → v0.97.0**（本地 pin `snap-2026-10-20-2` snapshot tag；上游确认纯内部重构、导出路径不变）：zim 全部 zent API 面（ConnPool/PostgresDriver/sql_scan/crud_helpers/SaveOrUpdateOnWith/deinitEntity）零改动兼容，38/38 测试直接通过
- **验证**：38/38 全过、CI 6/6 全绿、冒烟横幅 `Framework: zmodu v0.42.0`；Flutter e2e 仍因 SDK 移除未跑（Phase 81 记录）
- **版本引用**：main.zig 横幅/启动 JSON → `zmodu v0.42.0`；ci.yml ZMODU_VERSION=v0.42.0（env 改名）、ZENT_VERSION=snap-2026-10-20-2、checkout repo → chy3xyz/zmodu（path 保持 zigmodu 目录名对齐 build.zig.zon）

## Phase 83: zmodu v0.42.0 → v0.43.9 + zent v0.97.0 → v0.97.3 升级适配

- **零 API 破坏**：v0.43.x 变化集中在 http 性能（connection-buffer zero-copy parse、栈上 H1 读缓冲、响应写合并、idle timeout、smp_allocator）与 sqlx 整数解码修复；zim `zig build` + 38/38 测试直接通过，一行代码没改
- **zent v0.97.1-3**（pool mutex 修复 + oldest-borrow 观测 + outbox 时钟）：零改动兼容
- **修复既有 crontask data race**（升级重编译后暴露，非 zmodu 回归）：`g_io`/`g_running` 是非原子全局——①时序：`crontask.setIo(init.io)` 原在 `app.start()` 之后，模块 start 已 spawn 工作线程，早期 `g_io=null` 时 `if (g_io) |io| sleep` 不成立 → 1s 切片循环**不睡全速空转**（实测 ~70 迭代/秒，几千行日志）；②编译器优化 hoist：线程内非原子加载可被提出循环 → 永远 null。修复：`setIo` 提前到 `app.start()` 前（main.zig，线程 spawn 前保证就绪）+ `g_running` 改 `std.atomic.Value(bool)`（acquire/release 配对）。验证：20 秒日志从数百行 → 1 行（正确节律：内层 300×1s slice = 5 分钟一次外层迭代）
- **CI 冒烟偶发失败排查（非升级问题）**：WS 冒烟两次失败（register timeout / handshake reset）根因是**残留旧实例进程**——SO_REUSEPORT 下新连接被路由到旧进程被 reset（服务器日志明示 `port 10001 is ALREADY BOUND`）。修复：`scripts/ci.sh` 冒烟步骤启动前 `pkill -f zig-out/bin/zim` 清理。教训：SO_REUSEPORT 让"端口占用"从显式失败变成静默抢流量，本地反复起服务调试后必须确认端口干净
- **版本引用**：main.zig 横幅/启动 JSON → v0.43.9；ci.yml ZMODU_VERSION=v0.43.9、ZENT_VERSION=snap-2026-11-20（两 job ref 同步）
- **验证**：38/38 全过、CI 6/6 全绿（含 WS 冒烟）、冒烟横幅 `Framework: zmodu v0.43.9`；Flutter e2e 仍因 SDK 移除未跑（Phase 81 记录）

## Phase 84: RTC 会议持久化（产品级数据可靠性）

- **缺陷**：RTC 19 端点的会议/参与者状态原在进程内存 StringHashMap——重启即全部丢失，且存在 transferHost UAF（请求 arena 字符串赋给全局 map，请求结束悬空；Phase 66 修了 3 个 RTC 内存 bug 漏了这个）
- **持久化**（migrations/014_rtc_persistence.sql）：
  - `rtc_meetings`（room_id PK / host / name / status 1=active 2=ended / layout / record_id / create_time / ended_at）+ `rtc_participants`（BIGSERIAL id + UNIQUE(room_id,user_id)）
  - `gateway/rtc_persistence.zig`：存储选型按 BEST_PRACTICES §1——meeting 走 typed builder（Create/Query，调用方提供文本 pk）、participant 行级小写走 `drv.exec`（UNIQUE 业务键 ON CONFLICT）、读走 sql_scan DTO；DTO 字符串归请求 arena（不用 deinitRow——那是 zent entity 契约，第二次踩后已固化）
  - **首次实战 TxClient**：`createMeeting`（meeting+host 参与者行原子）/`closeMeeting`（host 校验 + 双表删除原子）用 `beginTxFromDriver` + errdefer rollback；RoomExists 从 pk UniqueViolation 映射
  - **重启语义**：gateway start 时 `archiveStaleMeetings()` 把遗留 status=1 全部标 ended（服务重启即散会，无僵尸会议）
- **handler 改造**：19 个函数签名/请求/响应结构不变（snake_case 输出与旧内存实现一致）；错误策略升级为产品级——持久化失败 → 500（原实现吞错），房间不存在保持 200 no-op（契约兼容），create 撞 room_id → 409（原为静默覆盖）
- **顺带根治**：transferHost 的 host 校验进 SQL（`AND host_user_id = $old`）——请求串不再触达持久化，UAF 类缺陷随内存 map 一起退役；gw_root 的两个 map/自旋锁/双释放注释全部删除
- **测试**：新增 RTC 生命周期（create→字段回读→重复建房拒绝→幂等 join→参与者 flag 落库→layout/record 持久→SQL 级 host 转让→非 host close 无效→host close 双删）+ 重启归档（create→archiveStaleMeetings→getMeeting null + status=2/ended_at 非空）；**40/40 全过、CI 6/6 全绿**；真实服务验证 create→join→close 全链路（participant 2 行落库、close 后 0 残留）
- 待办提醒：info 响应仍是 snake_case（与旧实现一致）——RTC 域 camelCase 对齐（`roomID`→响应内嵌 `hostUserID` 等）留作契约轮专项

## Phase 85: RTC 域 camelCase 契约对齐（Go rtc.proto MeetingInfo）

- **契约**：对照 `_ref/.../protocol/rtc/rtc.proto` 的 `MeetingInfo`（roomID/meetingName/hostUserID/createTime camelCase）——`info`/`list` 响应从直接序列化 snake_case 模型改为 `dto.meetingToJson` DTO（roomID/meetingName/hostUserID/status/createTime/layout/recordID，recordID 为 zim 录制扩展的命名风格）；create 端点的 roomID 本就 camelCase 不变，其余 17 端点 data 为 null 无字段面
- **契约测试升级**：原 Testkit 只断言 create 返回 roomID —— 现覆盖 **create→info→list→close 全链路**（走 Phase 84 持久化路径，IntegrationCtx 已初始化 zent）：断言 info 含全部 camelCase 字段 + **负断言 snake_case 泄漏为零**（host_user_id/meeting_name/room_id 不得出现）；close 后房间移除
- **验证**：40/40 全过、CI 6/6 全绿；RTC 域契约缺口闭环
- 顺带：`/rtc-meeting/list` 响应的 `meetings` 数组每项 camelCase 化

## Phase 86: zent 核心域事务迁移切片 A — 发消息事务迁 TxClient

- **事务通道迁移**（`message/service.zig sendInTx` 双轨：zent TxClient 优先，legacy db_postgres Tx 回退，与迁移文档双路径模式一致）：
  - `LegacyExecAdapter`（zent_db.zig）：把 zent Driver/Tx 包装成 legacy 执行器接口（queryParams/execParams/query）——`sendOn`/`getNextSeqOn` 的 legacy SQL（消息 INSERT..RETURNING、seq 原子分配）经适配器跑在**事务连接**上，SQL 零改动；结果字符串 dupe 进调用方 allocator（防 zent Rows deinit 悬空——Phase 60 教训的适配器版）；`string_array` 参数 fail-loud panic（无调用方，防静默写 NULL）
  - **conversation typed upsert 激活**（Phase 80 预留分支）：`upsertWithLatest` 三态化——`@TypeOf(exec)==zent_db.ClientType`（TxClient 的 client 视图）→ `upsertWithLatestOnClient`（typed SaveOrUpdateOnWith，GREATEST 单调表达式）；`*PostgresClient` → 同函数（池直连）；否则 legacy。单聊/通知 upsert 与群扇出 `upsertWithLatestBatchZent`（同 batch SQL、zent Value 参数、`tx.exec`）全部在事务连接上
  - `syncConversationZent`：syncConversationTx 的 zent 孪生（单聊/群/@提及/通知语义逐行对齐）
- **关键踩坑**：`beginTxFromDriver(infos, drv, allocator)` 的 allocator 决定 **tx.client 的 allocator**（TxClient 内部 makeClient(allocator)）——传请求 arena 会让事务内 typed upsert 返回的 entity 字符串落在 arena，而 `deinitRow` 用 zent_db 的 g_allocator 释放 → 跨 allocator free panic（SafeAllocator "free of invalid memory"，40/40 里 7 个发消息事务测试崩）。修复：TxClient 统一用 `zent_db.getAllocator()`。**规则**：TxClient 的 allocator 必须与实体 deinit 用的 allocator 同源
- **验证**：40/40 全过（seq 单调/黑名单拦截/已读推进/已读回执不污染/编辑召回等发消息事务测试全部在 zent 事务路径下通过）；CI 6/6 全绿；真实服务验证 send_msg（zent 事务）→ **双方 conversations 行由 typed upsert 落库**（max_seq=1 同步、group_at_type 正确）
- **范围说明**：本轮为切片 A（发消息事务，最高频路径）。切片 B（建群/删友/解散/注销的 Tx）沿用同一模式（TxClient + adapter）待后续；RTC（Phase 84）已用 TxClient

## Phase 87: zent 核心域事务迁移切片 B — 全部剩余 Tx 绑定路径

- **迁移完成，事务通道切换收官**（模式与切片 A 一致：TxClient + LegacyExecAdapter 跑事务连接上的 legacy SQL，legacy db_postgres Tx 回退保留）：
  - `friend/persistence.zig`：`respondFriendRequest`（请求已处理+双向好友行原子）、`deleteFriend`（双向删除原子）——SQL/params 提到分支外共用
  - `group/persistence.zig`：`addMembersTx`/`transferOwnerTx` 签名 `*db_mod.Tx` → `anytype`（legacy Tx 与 adapter 共享 execParams 接口，**同一函数体跑两种通道**，无逻辑复制）；`dismiss`（群+成员+申请三表）内部双轨
  - `user/persistence.zig`：`delete`（注销 8 表级联）内部双轨
  - `group/service.zig`：`addMembers`/`transferOwner` 入口双轨（TxClient + adapter 传 `&adapter` 给泛型 Tx 函数）
- **真实服务全链路验证**：create_group（建群事务成员行落库）→ dismiss_group（三表清零）→ unregister_user（users/conversations 级联清零）——全部 zent 事务路径；40/40 测试全过（好友事务/建群带成员/级联注销等集成测试自动走 zent 分支）、CI 6/6 全绿
- **迁移状态收官**：全部 8 处多语句原子事务（发消息+会话同步/建群/批量邀请/转让/删好友/接受好友/解散/注销级联）+ RTC create/close 均跑 zent TxClient；**核心域数据栈迁移完成**——剩余 legacy SQL 仅只读/低频路径（惰性迁移，双路径回退长期保留）
- zent-migration.md 后续更新「迁移模式」节的切片 B 记录
- **ReleaseFast 基线复测（Phase 87 后）**：login 75-78 / friend 2667 / group 2632-2740 / msg 1070-1111 ops/s —— 零回归，msg +61~67%、group +49~55%（旧基线的 664/1770 系噪声低估）；docs/benchmark.md 已更新口径表
- 本轮提交：5a70cca（Phase 83-87）

## Phase 88: 首次 GitHub CI 全绿 + 信令收窄落地（干净环境验证）

- **CI 首绿里程碑**（run 45091832445）：7 轮迭代修复后 test + frontend 双 job 全绿——test job（build/test/fmt/audit 0/deadcode 0/smoke+WS 六门禁，2m22s）、frontend job（analyze 零 error 门禁 + zim_sdk 契约测试 + 后端构建启动 + **Flutter↔zim E2E 全链路 1 test passed**，4m1s）。E2E 此前因本地 flutter SDK 移除无法验证，现由 CI 干净 runner 常态保障
- **CI 修复链**（7 处环境差异，均有教训价值）：
  1. postgres service 容器拒绝无密码初始化 → `POSTGRES_HOST_AUTH_METHOD: trust`（本地 trust 配置在 config 外，CI 需显式）
  2. dev.1970 tarball 404（ziglang.org GC 旧 dev 构建）→ pin **0.17.1 stable**（永久 URL；本地隔离验证 0.17.1 干净缓存 41/41 全过——stable 兼容）
  3. actions/checkout 拒绝 workspace 外 path → 依赖 checkout 移入 `zig_ws/` + **symlink 映射** zon 解析层级（src 上跳三级 = workspace 外一级，`$GITHUB_WORKSPACE/../../zig_ws`）
  4. dart analyze exit 2/64 语义混淆（151 issues 全 warning/info 无 error）→ 门禁改显式 `grep "^ *error -"`（级别语义不再依赖 exit code）
  5. **g_clients undefined 全局读 UB**（Linux 对齐断言崩，macOS 碰巧活）：push 测试不经 websocket 模块 init，事件链 push→pushOnlineStatusChange→isUserBackground 读 undefined map——四个公开入口（isUserBackground/pushOnlineStatusChange/pushToUser/pushToUsers）加 `g_initialized` 守卫。教训：跨模块事件订阅链的入口必须对"本模块未启动"防御
  6. **initLogFile open flags 平台 bug**（Linux ENOENT，本地残留文件掩盖）：`0x0200` 是 macOS 的 O_CREAT，Linux 上是 O_TRUNC——flags 按 `builtin.os.tag` 分支。教训：libc 常量禁止跨平台复用数值
  7. zim_sdk 测试步骤 working-directory 解析（per-step 相对 workspace 根）+ frontend job 漏配 Map 步骤（python replace 锚点未命中静默跳过——多次编辑后必须 grep 复核每一处）
- **信令 1004 投递收窄落地**（Phase 88 前尝试回退的专项，干净环境验证方案）：`handleWSSendSignalMsg` 用 `rtc_persistence.getParticipantIds` 收窄投递至房间参与者（未知房间回退广播保持带外信号流动）；`scripts/signal_smoke.py` 三连接探针（房主/参与者收、旁观者不收、发送者回显，手写 SignalReq protobuf 字段 1=room_id/2=signal_type(varint)/3=user_id/4=data）接入 frontend job CI 常态验证
- **注意**：CI 用的 base64 是 **url_safe**（`handleReqMessage` 用 `url_safe.Decoder`）——标准字母表的 `+/` 在长 payload 会让解码失败，探针与客户端需对齐

## 遗留项（Phase 35 之后）

- **gateway handler 已按域拆分**（Phase 49）：`gateway/handlers.zig` 4125 行拆为 298 行骨架 + `handlers/{helpers,auth,account,user,friend,group,message,conversation,encryption,office,organization,third,statistics,rtc,jssdk,health}.zig` 16 个域文件；新增 handler 遵循同结构
- **事务覆盖扩展**：建群/加好友/删好友/解散群/注销用户/发消息+会话同步/群批量邀请已事务化（Phase 49 遗留轮补齐）；office work moment 发布/点赞/评论评估为单语句原子操作无需事务
- **emit payload 释放**：已完成（Phase 49 遗留轮）—— user/friend/group/conversation/message 共 19 处补 `defer core.getAllocator().free(payload)`，websocket/crontask 4 处本就正确释放；新增 emit 调用点沿用该模式
- **zigmodu StructuredLogger**：key 未 dupe 崩溃 bug 已修复（commit 2b265bd，含回归测试），zim 已重新接入（core.getLogger + 启动事件 + HTTP 访问日志 JSON，实测 0 崩溃）；残留 `{any}` 把字符串字段输出成字节数组的格式问题未修 —— 补丁见 `docs/structured-logger-patch.md`，应用后 path/method 可读
- **gateway 路由已按域分组**（Phase 37）：17 个 `*_routes` const；后续如需可继续把 handler 实现拆到 `handlers/{域}.zig`
- **结构化日志**：访问日志已是每请求一行 JSON（std.log 输出）；其余模块仍为 `std.log` 风格，如需要可接 zigmodu `StructuredLogger`（修复其 bug 后）或继续 std.log JSON
- **功能对照**：消息分页/搜索增强、群公告/@提及、RTC 持久化等见 `docs/go-zig-gap-analysis.md` 与 `docs/improvement-plan.md`
- **CI 门禁**：`scripts/ci.sh` 一键五步门禁（build/test/fmt/audit/deadcode），zmodu 优先用 `.zmodu-build/bin/zmodu`（本地构建 v0.15.9，含 audit/deadcode）否则 PATH
- 约束提醒：新增路由直接写原生 `http.Context` 风格；zmodu 本地源码需保持 binary 帧支持（`WsMessageFn(session, msg, kind)`）；`config.yaml` 为 `[section]` INI 风格；新迁移文件放到 `migrations/`，启动时自动应用
- **已落地专项（从遗留清单移除）**：配置热加载（Phase 65）、日志文件+轮转（Phase 64）、WS 真实连接测试（`scripts/ws_smoke.py`，Phase 70 起 CI 冒烟）、zent 迁移核心域事务（Phase 86-87 收官）、RTC 持久化（Phase 84）、可观测性（Phase 66 metrics/慢查询）
- **已落地专项追加**：WS 信令 1004 投递收窄（Phase 88，房间参与者精确投递 + signal_smoke.py CI 常态验证）
- **仍开放专项**：①Webhook 动态回调（BeforeSendMsg 响应驱动）与 attentionIds 之外的过滤；②已读回执通知（Phase 59 遗留的 libpq RETURNING 乱码专项——Phase 60 已修 UAF 根因，可重启尝试）；③chat 管理服务（open-im-chat，超 IM 边界）

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
**Gateway**: zmodu `http.Server`（10000 端口）+ ComptimeRouter 188 条声明式路由；鉴权走 `authMiddleware`（公开路径白名单 + token 校验），CORS/OPTIONS 由 `corsMiddleware` 处理；handler 全部为原生 `http.Context` 风格（Phase 34 起，bridge 适配层已删）  
**User**: 18 endpoints including `/user/get_all_users_id`, `/user/search_users`, `/user/get_users_online_status`  
**Friend**: 22 endpoints including `/friend/add_friend`, `/friend/get_black_list`  
**Group**: 28 endpoints including `/group/create_group`, `/group/transfer_group`  
**Message**: 21 endpoints including `/msg/send_msg`, `/msg/pull_msg_by_seq`  
**Conversation**: 11 endpoints including `/conversation/get_sorted_conversation_list`  
**Office**: 11 endpoints including `/office/work_moment/add`, `/office/work_moment/like`  
**Organization**: 5 endpoints  
**Third**: 7 endpoints (`/third/fcm_update_token` with DB persist, `/object/auth_sign` with presigned URL, `/object/access_url`, `/third/logs/upload`, `/third/logs/search`)  
**Statistics**: 4 endpoints (`/statistics/user/register`, `/statistics/group/create`, etc.)  
**RTC Meeting**: 19 endpoints, room state persisted in PostgreSQL since Phase 84 (`/rtc-meeting/create`, `/rtc-meeting/join`, etc.)  
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
  - `1006` GetConvMaxReadSeq
  - `1007` PullConvLastMessage
  - `1004` SendSignalMsg (RTC signaling relay)
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

[zmodu](https://github.com/chy3xyz/zmodu) v0.43.9 (原名 ZigModu/zigmodu，v0.41.0 改名；local source `~/w4_proj/zig_ws/zigmodu`，目录名未随仓库改；v0.42→43.9 含 http zero-copy 解析/响应写合并/idle timeout/smp_allocator、sqlx 整数解码修复；Zig toolchain 0.17.0-dev.1970) provides:
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

## ORM (zent)

[zent](https://github.com/chy3xyz/zent) v0.97.3 (local pin `snap-2026-11-20`, local source `~/w4_proj/zig_ws/zent`; v0.84+ 文本主键须调用方提供 —— conversation upsert 已适配) — Zig Entity Framework, pilot wired alongside the legacy `db_postgres` client (see `docs/zent-migration.md`):

- `src/zent_schemas.zig` — Schema-as-Code mirrors of existing tables (User, Collect; SELECT is column-list based; undeclared DB columns are never touched; migrations stay the DDL source of truth)
- `src/zent_db.zig` — `ConnPool(PostgresDriver)` + typed client holder (`getClient()`) + pooled driver view (`getDriver()`, for `sql_scan` raw-DTO queries), config strings duped for hot-reload safety
- **Migration pattern (Phase 77)**: dual-path — migrated persistence methods prefer zent (`getClient()`/`getDriver()` non-null) and fall back to legacy db_postgres when the layer is down; `IntegrationCtx` inits zent whenever PG is reachable so integration tests always exercise the zent path
- Concurrency rules: client must sit on the pool (never a shared single driver — wire protocol races); `health_check_on_borrow=false` (ping-under-mutex deadlock)
- Memory contract: entity rows are owned — free via `zent_db.deinitRow(info, &row)`, row `TypeInfo` via `@TypeOf(client.user).entity_info`; `sql_scan.queryAll/queryOne` DTO results duplicate strings into the caller's allocator (request arena in prod — same contract as the legacy dupe loops they replaced)
- Migration status: **all 8 multi-statement transactions on TxClient** (message-send+conversation-sync Phase 86; group create/batch-invite/transfer/dismiss, friend accept/delete, user revoke cascade Phase 87; RTC create/close Phase 84) — `LegacyExecAdapter` runs legacy SQL on the tx connection while conversation upserts use typed `SaveOrUpdateOnWith` in-transaction. Remaining legacy SQL is read-only/low-frequency paths (lazy migration; dual-path fallback retained). **TxClient allocator rule: must match entity-free allocator (`zent_db.getAllocator()`)**. Each step must keep 40 tests + CI gates green

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
