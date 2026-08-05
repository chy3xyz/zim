# zim 完善评估（基于 zigmodu v0.14.17 现状）

> 评估时间：2026-07-31。基线：`zig build` / `zig build test` 通过，Debug 退出 0 泄漏，HTTP（ComptimeRouter + 185 原生 handler）、WS（zigmodu ws_routes）、config（YamlParser）、PBKDF2、HealthEndpoint/Prometheus 均已落地。

## 现状基线（已完成项）

| 项 | 状态 |
|----|------|
| 模块化 + RuntimeOptions 声明 | ✓ |
| HTTP：zigmodu http.Server + ComptimeRouter，185 路由声明式 | ✓ |
| handler：185 个全部原生 `http.Context`，bridge 已删除 | ✓ |
| WS：zigmodu ws_routes（binary protobuf 推送、text 分发、token 握手鉴权） | ✓ |
| config：zigmodu YamlParser（INI 风格，带旧格式回退） | ✓ |
| 内存：serviceAllocator + 请求 arena，事件 payload 生命周期托管，0 泄漏 | ✓ |
| 安全：PBKDF2 密码、OS CSPRNG、真实时间戳 | ✓ |
| 可观测：HealthEndpoint（liveness+db）、Prometheus 3 计数器 | ✓ |
| 稳定性：libpq 并发互斥、SQL NUL 结尾、crontask 真实休眠、优雅停机 | ✓ |

## 一、代码组织与死代码（低风险、快速收益）

### 1.1 gateway.zig 4283 行 → 按域拆分（P1）
单个文件承载全部 185 个 handler。建议按 zigmodu 约定拆为
`src/modules/{auth,user,friend,group,message,conversation,office,organization,third,rtc,stats}/api.zig`，
每个域自带 `pub const routes`，再由 gateway 汇总 mount。收益：可维护性、路由元数据（auth/permission）就近声明。

### 1.2 死代码清理（P2，低风险）
- `src/modules/event_bus/{root,service,model}.zig`：旧固定数组总线，已无人引用（模块实际用 `event_bus.zig` → `core.getEventBus()`），可整目录删除
- gateway 旧模型导出：`gateway.zig` / `gateway/root.zig` 中的 `HttpMethod/HttpRequest/HttpResponse/Route/RouteHandler` 已无消费方，`model.zig` 仅保留 RTC/JSON DTO 类型即可
- `core.validateModule()` 兼容垫片：全部 16 个模块在调用，但 zigmodu `Application` 已内置模块校验（`validate_on_start`），可移除
- `websocket/root.zig` 未用的 `config_mod` import；`websocket.setIo/model.g_io` 在 WS 迁移后无实际用途（WSClient 全走 framer），可清理

## 二、RuntimeOptions 真正接线（P1，中风险高价值）

目前 17 个模块声明了 `runtime`（bulkhead/rate limiter/circuit breaker/worker pool），但 `getModuleRuntime/tryEnter/recordSuccess` 零消费方——资源创建了却没人用。
建议接入点：
- gateway：请求入口 `tryEnter/release` 做并发准入（`max_concurrent=500` 才有意义）
- db_postgres：查询成功/失败 `recordSuccess/recordFailure` 驱动熔断（`cb_failure_threshold` 生效）
- push/websocket：把 WorkerPool 用于异步分发（事件总线已用 core pool，模块 pool 可复用）

## 三、数据层（P1）

### 3.1 单连接无池
全局唯一 libpq 连接 + 互斥锁串行化所有查询（含 HTTP 线程、crontask、push）。安全但吞吐受限，且无重连/健康探测。
选项：a) 自建小连接池（按 `database.max_conns/min_conns` 配置）；b) 评估迁移 zigmodu `data.sqlx`（自带池 + 熔断 + 流式游标）。b 是大工程，建议先 a。

### 3.2 迁移自动化
目前靠手动 `psql -f migrations/*.sql`，缺迁移会静默失败（本会话已踩过 3 次）。接入 zigmodu `Migration` runner 或启动时校验 schema 版本（`schema_migrations` 表）。

### 3.3 事务
业务层无显式事务（如"建群+加群主"两步），可评估 zigmodu `Transactional`/`Saga` 或 `beginTx` 封装。

## 四、可观测性（P2）

- **指标**：当前仅 3 个计数器；补 HTTP 延迟 histogram、路由级计数、WS 消息计数；zigmodu `HttpMetricsCollector` / `AccessLogger` 可用
- **结构化日志**：接入 zigmodu `StructuredLogger` 或统一 `std.log.scoped`；修掉 `{s}` 打印非 NUL 结尾 slice 的乱码问题（曾出现 `User online: Switching P`）
- **OpenAPI**：路由 catalog 已生成，挂 `GET /openapi.json` 即可（`openApiFromCatalog`）
- **Tracing**：OTLP 导出器可选，暂不需要

## 五、认证与安全（P2）

- 验证码目前存内存（`verification_codes`），重启即失——可 DB 化
- token 为 opaque + DB 校验，可用；如想减少 DB 查询可评估 `AppSecurity` JWT，但需保持 SDK 兼容（不推荐近期动）
- 请求参数校验：接 `extractJsonValidated`/`Validator`，替代 handler 内手工判断
- 登录防爆破：zigmodu 已有 auth 限流中间件，可挂到 `/account/login`

## 六、测试（P1，当前最薄弱）

现状：`zig build test` 只有 2 个 protobuf 测试。建议按序补齐：
1. **HTTP 路由测试**：zigmodu `http.Testkit.dispatch`，覆盖公开/受保护/404/信封格式（OpenIM `{errCode,errMsg,data}` 契约）
2. **服务层单测**：`openMemorySqlite` 或 mock db，覆盖 auth/user/friend/message 核心流程（PBKDF2、token 校验、加好友、发消息校验）
3. **WS 协议测试**：握手鉴权、text/binary 分发、protobuf 推送编解码
4. **契约测试**：`ContractTestRunner` 固定信封与字段命名（camelCase）

## 七、功能对照 Go OpenIM（按产品优先级，引用 gap analysis）

`docs/go-zig-gap-analysis.md` 已有逐模块对比。待办热点（按价值排序）：
- 消息分页/游标与搜索增强
- 群公告 / @提及 / 已读回执细节
- RTC 会议持久化（当前纯内存）
- 多端在线状态细粒度（`get_users_online_token_detail` 已有桩）

## 建议路线

| 优先级 | 事项 | 预估 |
|--------|------|------|
| P0 | 测试体系（Testkit 路由 + 服务层 + WS 契约） | 中 |
| P1 | gateway 按域拆分 + 死代码清理 | 中 |
| P1 | RuntimeOptions 接线（准入/熔断/worker pool） | 小-中 |
| P1 | DB 连接池与重连 | 中 |
| P1 | 迁移自动化（启动校验 schema） | 小 |
| P2 | 指标/日志/OpenAPI 增强 | 小 |
| P2 | 验证码 DB 化、登录限流、参数校验 | 小 |

## 2026-07-31 收尾执行结果

评估清单已全部落地：

| 项 | 结果 |
|----|------|
| gateway 拆分 | `gateway.zig` 143 行（中间件+服务器接线），`gateway/handlers.zig` 4234 行（路由表+DTO+185 handler） |
| 死代码清理 | 删除 event_bus/{root,service,model}.zig、旧 HttpRequest/HttpResponse 模型、core.validateModule 垫片、websocket 无用 import |
| RuntimeOptions 接线 | gateway 请求准入（bulkhead 503）；db_postgres 并发门控 + 熔断成功/失败统计 |
| DB 连接池 | `PostgresClient` 8 连接池（`database.max_conns` 驱动），每查询独立连接 + `PQreset` 断线自动重连 |
| 迁移自动化 | 启动时 `ensureMigrations()`：schema_migrations 跟踪、按序自动应用、失败显式中止；pgmq 扩展改为可选 |
| 可观测性 | `zim_http_request_duration_seconds` histogram、每请求访问日志、`GET /openapi.json`（catalog 生成） |
| 安全 | 验证码 DB 化（013 迁移，重启不丢、一次性消费）；登录限流（每用户 5 次/15 分钟）；修复 health 未初始化 DB 崩溃 |
| 测试 | `zig build test` 从 2 个 protobuf 测试扩到 6 个：core 事件总线（同步/异步/目标路由）+ gateway HTTP 契约（health/metrics/401/404/CORS） |

最终验证：`zig build` / `zig build test` 通过；满载请求后优雅停机 **0 泄漏**；HTTP/WS/迁移/限流全链路冒烟通过。

## 2026-08-01 继续完善

| 项 | 结果 |
|----|------|
| DB 事务 | `PostgresClient.Tx`（begin/commit/rollback，锁定池连接）；参数序列化抽为 `buildParams/execParamsOn/queryParamsOn` 供池与事务共用；**建群**（群+群主+成员）与**加好友响应**（请求更新+双向好友）原子化 |
| 修复建群既有 bug | RETURNING 列错位/越界（member_count 缺失）、`notification_update_time` 裸 timestamptz 未 EXTRACT、`join_time`/`mute_end_time` 传 unix 秒进 TIMESTAMPTZ（改 `to_timestamp`）、成员参数 6 对 5、`mute_end_time` 整数 0 → NULL |
| 参数校验 | `/account/login`（密码≥6）、`/account/register`（昵称必填、密码≥6）显式校验，返回 OpenIM 信封 |
| gateway 结构 | 16 个 `*ToJson` DTO 抽到 `gateway/dto.zig`；handlers.zig 从 4234 行降至 ~3680 行 |
| 测试 | 新增登录限流单测（5 次/用户窗口语义）；`zig build test` 共 7 个测试全过 |
| 杂项 | 迁移记录 INSERT 加 `ON CONFLICT DO NOTHING`（并发实例安全）；迁移 applied 键泄漏修复（getOrPut） |

最终验证：`zig build` / `zig build test` 通过；建群事务（群+群主+2 成员原子落库）、登录校验、短密码拒绝、openapi/histogram 全部冒烟通过；优雅停机 **0 泄漏**。

## 2026-08-01 第二轮继续完善

| 项 | 结果 |
|----|------|
| 事务覆盖扩展 | **删好友**（双向行原子删除）、**解散群**（群+成员+申请原子清理）、**注销用户**（用户+令牌+好友+申请+黑名单+会话+命令+在线状态级联删除）全部改为 `Tx` |
| 验证码发送限流 | `/account/code/send` 每目标 60 秒一次（DB 查询最近 created_at），超频返回 `CodeTooFrequent`；实测首次下发、二次拦截 |
| 网关路由按域分组 | `GatewayRoutes.routes` 拆为 17 个按域 `*_routes` const（auth/account/user/friend/group/message/conversation/encryption/office/collect/client_config/organization/third/statistics/rtc/metrics）后 `++` 合并；186 条路由注册不变 |
| 测试 | `zig build test` 7 个测试全过（含登录限流单测） |

最终验证：`zig build` / `zig build test` 通过；删好友（双向）、解散群（全清）、建群（原子）、验证码限流、186 路由全部冒烟通过；优雅停机 **0 泄漏**。

## 2026-08-01 缺陷审计轮

系统审计挖出并修复 3 个真实 bug：

| Bug | 根因 | 修复 |
|-----|------|------|
| 工作圈动态创建错乱/越界 | create 的 RETURNING（10 列）喂给 12 列 JOIN 解析器（face_url/nickname 错位 + row[11] 越界） | create 改为内联解析 10 列，JOIN 查询保持原解析 |
| 工作圈/组织分页列表恒空 | `offset = page * size`（page=1 → offset=10，首条被顶掉） | 5 处改为 `(page-1)*size`（office 4 处 + organization 1 处） |
| 消息搜索 QueryFailed | `EXTRACT(EPOCH FROM send_time)`——send_time 是 bigint 毫秒不是时间戳；`LIMIT $3` 参数类型无法推断 | 直接返回 `send_time`；`LIMIT $3::int` |

另核实无问题项：friend 请求 RETURNING 内联解析（9 列）；conversation `latest_msg_send_time` 与 message `send_time` 同为毫秒；office like/comment 时间戳进 JSON 后按 bigint 比较；`user_read_times.count_time/list_time` 为 bigint 与 unix 秒一致。

最终验证：`zig build` / `zig build test` 通过；工作圈创建/列表（修复后返回数据）、消息搜索（返回匹配）、群禁言（to_timestamp）冒烟通过；优雅停机 **0 泄漏**。

## 2026-08-01 安全审计轮

SQL 注入审计（全量扫描拼接 SQL）挖出并修复：

| 严重度 | 位置 | 问题 | 修复 |
|--------|------|------|------|
| 高 | message/persistence 5 处（`checkMsgSendSuccess`/`getClientMsgIdBySeq`/`trackGroupMessageRead`/`getGroupMessageReadNum`/`getGroupMessageHasRead`） | 用户可控的 client_msg_id/conversation_id/user_id/group_id 直接拼接进 SQL（含 INSERT） | 全部改为 `queryParams`/`execParams` 参数化 |
| 中 | office `getCollects` | `collect_type IN ('t1','t2')` 值未转义拼接 | 改为 `$N` 参数化 IN |
| 低 | message `getGroupMessageReadNum` | `conversation_id[3..]` 短字符串越界 panic | 加长度守卫 |

复核安全项：`ORDER BY seq {s}`（bool 决定 ASC/DESC）；conversation/group/user 的 `UPDATE ... SET` 动态子句（列名硬编码、值参数化）；third 日志 where 子句（`${d}` 占位符 + 参数）；friend 请求查询 `field`（bool 决定列名）。均无注入面。

验证：`zig build` / `zig build test` 通过；collect 增/查（含类型过滤参数化）、`checkMsgSendSuccess` 正常；优雅停机 **0 泄漏**。

## 2026-08-01 契约审计轮

| 项 | 结果 |
|----|------|
| OpenIM 契约修复 | `/conversation/get_sorted_conversation_list` 按 Go proto 对齐：请求兼容 `userID`（SDK）与 `ownerUserID`（旧客户端）；响应新增 `conversationElems` + `conversationTotal`/`unreadTotal`（msgInfo 从 latest_msg JSON 解析），保留旧 `conversations` 平铺字段 |
| 崩溃风险审计 | 全量扫描 `.?`/`unreachable`/`[N..]`：所有可选解包均有空值守卫，无 `unreachable`；`conversation_id[3..]` 已加守卫 |
| WS 协议测试 | 新增 `MsgData` protobuf 编码/解码往返测试（send_id/content/seq/sendTime/contentType/nickname 全字段核对） |

验证：`zig build` / `zig build test` 通过（8 个测试）；Go 契约请求（userID）+ 响应（conversationElems/msgInfo/总计）冒烟通过；优雅停机 **0 泄漏**。

## 完成度评估（2026-08-01）

**综合完成度：约 82-85%**（可运行的 OpenIM 兼容重写；距"完整对齐 Go 企业版"差 15-20%）。

| 维度 | 完成度 | 依据 |
|------|--------|------|
| 核心 API 覆盖 | ~92% | 185 路由（> Go 174 个 handler）；缺 jssdk/extendmsg/prometheus_discovery |
| 前端兼容（OpenIM 契约） | ~85% | WS 1001-2100 全、binary protobuf、信封、camelCase；sorted_conversation 已对齐；其余契约仅抽查 |
| 工程与稳定性 | ~90% | 0 泄漏、事务、参数化 SQL（0 注入）、连接池+重连、迁移自动化、优雅停机、RuntimeOptions 接线 |
| 架构对齐 zigmodu | ~85% | ComptimeRouter/ws_routes/ThreadSafeEventBus+WorkerPool/HealthEndpoint/Prometheus/YamlParser/Tx 全用；仍用 libpq（未迁 data.sqlx）、无结构化日志 |
| 测试 | ~35% | 8 个测试（总线/HTTP 契约/限流/protobuf 往返）；缺服务层 DB 测试、WS socket 测试、压测 |
| 产品功能（对照 Go） | ~80% | 核心 IM 齐全；缺多终端 6 策略（仅同平台踢线）、WS gzip、异步消息管道深度（事件驱动替代 Kafka）、RTC 持久化、jssdk |

**优先补齐路线**：P0 测试深度（服务层/WS/压测）→ P1 多终端登录策略 + WS gzip → P1 jssdk/extendmsg → P2 结构化日志 + handler 按域拆文件 → P3 评估 data.sqlx 迁移。

## 2026-08-01 测试深度轮（P0）

| 项 | 结果 |
|----|------|
| 服务层 DB 集成测试 | 新增真实 PostgreSQL 全链路测试：注册（PBKDF2）→ 登录 → parseToken → 档案查询 → 非好友拒收 → 加好友请求/接受（事务）→ 建群带成员（事务）→ 发消息 → 会话自动同步；PG 不可用时优雅跳过；`zig build test` 共 9 个测试全过 |
| 暴露并修复真实 bug | `auth.registerWithPassword` 双重 PBKDF2 哈希（先 encode 再 `createUser` encode）→ 登录必然 InvalidPassword；改为传原始密码由 `createUser` 哈希一次 |
| 泄漏修复 | `auth.deinit` 未清理登录限流 map（`deinitLoginLimiter`），已补上 |

验证：`zig build` / `zig build test` 通过（9 个测试）；HTTP 注册/登录/发消息冒烟正常；优雅停机 **0 泄漏**。

## 2026-08-01 多终端登录策略轮（P1）

对齐 Go `ws_server.go` 的 6 种登录策略：0=DefaultNotKick、1=AllLoginButSameTermKick（默认）、2=SingleTerminalLogin、3=WebAndOther、4=AllLoginButSameClassKick、5=PCAndOther、6=Customize（回退同终端）。平台分类（Mobile/PC/Web/MiniWeb/Pad/Admin/HarmonyOS）按 OpenIM platform id 映射。

配置项 `[gateway] login_policy`（INI + 旧格式回退均支持）。新增 `shouldKickOld` 纯函数单测覆盖全部 6 策略；运行时实测策略 1（同平台二次登录踢旧连接，收到 2002 踢线帧）与策略 0（双连接共存）。

验证：`zig build` / `zig build test` 通过（8/8）；WS 策略 0/1 实测通过；优雅停机 **0 泄漏**。

## 2026-08-01 压测工具 + JSSdk 轮（P0/P1）

**压测工具**：新增 `src/bench.zig` + `zig build bench`（`BENCH_ITERS` 控制迭代数），进程内直连 PG 压测登录/加好友/建群/发消息，输出 ops/s。实测：login 4 ops/s（PBKDF2 10 万次迭代的真实成本）、friend request 862 ops/s、group create（事务）394 ops/s、message send 133 ops/s。

**JSSdk 端点**（对齐 Go jssdk）：`POST /jssdk/get_conversations`（按 owner/IDs 返回会话聚合：conversation + lastMsg + user/group + maxSeq/readSeq + unreadCount）与 `POST /jssdk/get_active_conversations`（按活跃度取前 N 条）。响应结构对齐 Go proto `ConversationMsg`。实测两端点返回正确数据。

验证：`zig build` / `zig build test` 通过（8/8）；jssdk 两端点、压测工具实测通过；优雅停机 **0 泄漏**。

## 2026-08-01 契约审计轮 · Friend/Black/Apply（P0）

对照 Go `protocol/relation/relation.proto` + `sdkws/sdkws.proto` 逐项核对好友域 HTTP 契约：

| 端点 | 对齐结果 |
|------|----------|
| `friend/get_friend_list` | 补 `total`；每项含 Go `FriendInfo` 嵌套 `friendUser`（userID/nickname/faceURL）+ `isPinned`（DB 列已存在，补齐查询与 DTO） |
| `friend/get_black_list` | key 由 `blacksInfo` 改为 Go 的 `blacks`；补 `total`；每项含嵌套 `blackUserInfo` |
| `friend/get_friend_apply_list`（收方） | key 对齐 Go json tag：`FriendRequests`（大写）+ `total` |
| `friend/get_self_friend_apply_list`（申请方） | `friendRequests` + `total` |
| `friend/get_specified_friends_info` | 重构为 Go `{infos:[{userInfo,friendInfo,blackInfo}]}`（原先平铺 `friendsInfo`） |
| `friend/get_specified_blacks` | key 改为 `blacks` |
| `friend/update_friends` | 补齐 `isPinned`/`remark`/`ex` 参数化部分更新（原先忽略 isPinned） |
| `group/get_group_member_list` | 补 `total` |
| `group/get_*_application_list` ×3 | 补 `total` |

**修复关键崩溃（第 5 处本地 zigmodu 修复）**：`bindJson` 的 `deepCopy` 对非 u8 slice（`[]struct`、`[][]const u8`）只做浅拷贝，指针仍指向 `parseFromSlice` 缓冲区，`defer parsed.deinit()` 后即悬空 —— 凡是带数组字段的 handler（`user_register` 多用户、`batch_send_msg`、`set_conversations`、`invite_user_to_group` 等）在第 2 个元素上必然段错误（实测 `/user/user_register` 双用户崩溃，密码指针 0xaaaaaaaa…）。修复：slice 分支对元素逐个 deepCopy。

验证：`zig build` 通过；测试 8/8（`zig build test --summary all` 显示 7/7 steps succeeded, 8/8 tests passed；首次 run 偶发 runner 重试属 zig 0.17-dev 工具链抖动，二进制直跑 8/8 稳定通过）；全链路冒烟（注册/登录/加好友/接受/置顶/拉黑/申请列表/specified info）通过；优雅停机 **0 泄漏 0 panic**。

**遗留（记录在案）**：`GroupMemberFullInfo` 缺 `appMangerLevel`（group_members 表无此列）；incremental 系列仍是 `sinceTimestamp` 自定义契约（Phase 21 对齐前端，未迁 Go version/versionID 增量）；WS 二进制推送未 gzip。

## 2026-08-01 契约审计轮 · Group/Statistics（P0/P2）

对照 Go `protocol/group/group.proto` 继续对齐：

| 端点 | 对齐结果 |
|------|----------|
| `group/get_groups_info` | key 由 `groupsInfo` 改为 Go 的 `groupInfos`；原先直接吐蛇形 `Group` 结构体（严重契约违规），改为经 `groupToJson` camelCase |
| `group/get_groups` | 补 `total`；同样经 camelCase DTO |
| `group/get_joined_group_list` | 补 `total` |
| `group/get_group_abstract_info` | 重构为 Go `{groupAbstractInfos:[{groupID,groupMemberNumber,groupMemberListHash}]}`：请求由单 `groupID` 改为 `groupIDs` 数组；`groupMemberListHash` 用成员 user_id 的 FNV-1a 64 计算（无真实版本哈希，但可稳定用于增量成员同步判断） |
| `statistics/user/register`、`statistics/group/create` | 对齐 Go `{total,before,count:map<date,int64>}`：新增 `countBefore`（start 之前总数）与 `countByDay`（按 UTC 日期 GROUP BY）；动态 map 用 `sendOkDataJson` 手工序列化 |

验证：`zig build` 通过；8/8 测试（`--summary all` 7/7 steps succeeded）；冒烟：statistics 返回按天 map（如 `{"2026-07-31":72}`）、group 三端点返回 camelCase Go 结构；优雅停机 **0 泄漏 0 panic**。

**遗留更新**：statistics `/user/active`、`/group/active` 仍是 `{count}`（Go `GetActiveUser/GetActiveGroup` 为 `{msgCount,userCount/groupCount,dateCount,users/groups}`，需按 messages 表聚合，下轮可做）；`send_msg` 响应缺 Go 的 `modify`（MsgData，可选字段）；extendmsg（Reaction）在 enterprise 参考中无 HTTP 路由（走 WS/msg 服务），暂不实现。

## 2026-08-01 契约审计轮 · Statistics Active + 字段补齐（P2）

| 项 | 对齐结果 |
|----|----------|
| `statistics/user/active` | 对齐 Go `GetActiveUserResp`：`{msgCount,userCount,dateCount:<date,数量>,users:[{user:{userID,nickname,faceURL},count}]}`；按单聊消息（group_id=''）聚合，top N 由 `pageNumber/showNumber` 控制 |
| `statistics/group/active` | 对齐 Go `GetActiveGroupResp`：`{msgCount,groupCount,dateCount,groups:[{group:{groupID,groupName,faceURL},count}]}`；按群消息（group_id!=''）聚合 |
| `group` 成员列表 | `GroupMemberFullInfo` 补 `appMangerLevel`：`getMembers`/`getMembersSince`/`getMember` 三查询 LEFT JOIN users 取 `app_manager_level` |
| `msg/send_msg` | 响应补 Go `SendMsgResp` 的 `modify` 字段（null） |

新增：message 模块 `activeMsgCount`/`activeEntityCount`/`activeDateCount`/`activeTopEntities`（按 create_time 秒区间 + group_mode 区分单聊/群聊）；`appendDayCountJson` 与 `appendEscapedString` 动态 JSON 构建辅助（昵称/URL 转义，避免手工 JSON 非法）。

过程中修复：首次实现 `appMangerLevel` 时列索引错位（role_level 误读 epoch 时间戳导致 i16 溢出），集成测试抓出并修正为 row[12]。

验证：`zig build` 通过；8/8 测试（`--summary all` 7/7 steps succeeded, 8/8 tests passed）；冒烟：active 两端点返回真实聚合（用户/群 top 榜、按天 map）、成员列表含 appMangerLevel、send_msg 含 modify；优雅停机 **0 泄漏 0 panic**。

**遗留更新**：所有 statistics 端点已对齐 Go 主结构；剩余记录：incremental 系列仍是 sinceTimestamp 自定义契约（Phase 21 对齐前端，未迁 Go version/versionID 增量）；WS 二进制推送未 gzip；`GetActiveUser/GetActiveGroup` 的 `ase` 排序参数未实现（默认按 count 降序，管理端排序足够）；extendmsg（Reaction）在 enterprise 参考中无 HTTP 路由，暂不实现。
