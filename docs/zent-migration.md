# zent ORM 迁移评估与计划

> 状态：Phase-0 试点（Phase 76）+ 迁移切片 1（Phase 77：collects 全 CRUD、统计聚合行解析）
> + 迁移切片 2（Phase 78：auth_tokens / auth_verification_codes / fcm_tokens / webhook_events / app_logs）
> + 迁移切片 3（Phase 79：office 工作圈全量 + tags + clientConfig，低冲突层收尾）
> + 迁移切片 4（Phase 80：conversation 全量 —— 核心域第一片， BEST_PRACTICES
> 对齐的类型化升级：SaveOrUpdateOnWith 业务键 upsert + GREATEST 单调表达式）；
> 本文档记录可行性结论与逐表迁移路线。

## 背景

[zent](https://github.com/chy3xyz/zent)（v0.34.0，本地 `~/w4_proj/zig_ws/zent`）是 Zig 版
Entity Framework（对标 Go ent）：Schema as Code、comptime 类型安全查询/变更 builder、
libpq 直连 PostgreSQL、连接池、事务（TxClient）、拦截器、软删除、raw DTO 扫描
（`sql_scan.queryAll`）等。

zim 现状：全部持久化走自研 `db_postgres.zig`（libpq + 参数化 SQL + 8 连接池 + `Tx`），
17 个模块约 50+ 表手工 SQL。

## 结论：可行，且与 zmodu 无冲突

- zent 是 **数据层**，zmodu 是 **应用框架**（模块/HTTP/事件总线）——正交组合，
  `zmshop_zent` / `zmcanyin_zent` 已在生产规模验证 zmodu + zent 同进程共存。
- zmodu v0.15.31+ 官方适配 zent（见 zmodu CHANGELOG `chore(zent): 适配 zent v0.32.x`）。
- 本机 libpq 经 `pg_config` 发现（homebrew postgresql@17）；链接复用 zmodu sqlx 已有的
  `-lpq`（同一可执行文件链接一次即可），zent 自身 build 负责头文件 discovery。
- 真实 PG 双向互通已验证（`tests.zig` "zent: ORM client interops with zim persistence"）：
  zent Create/Update/Delete ↔ `user.getUser` 交叉读写同一 `users` 表，测试后 0 残留。

## 已落地（Phase 76 试点）

| 件 | 说明 |
|----|------|
| `src/build.zig.zon` | `zent` path 依赖（fingerprint 0xc7cc6523fbab2ba2） |
| `src/build.zig` | exe + tests 模块 `addImport("zent", ...)` |
| `src/zent_schemas.zig` | `users` 表 Schema-as-Code 映射（SELECT 按列名生成，未声明的列如 TIMESTAMPTZ 不会被触碰） |
| `src/zent_db.zig` | `ConnPool(PostgresDriver)`（min 1 / max 4，`health_check_on_borrow=false`）+ client 持有 + `init/deinit`；配置串 dupe（防 config 热加载悬空） |
| `src/main.zig` | `app.start()` 后初始化（**非致命**：失败仅告警，db_postgres 仍是权威路径）；停机时先于 app/core 关闭连接池 |
| `src/tests.zig` | 双向互通集成测试（PG 不可用优雅跳过） |

关键经验（源自 zmshop_zent 踩坑，zim 直接继承）：
- client 必须坐在连接池上——单个共享 `PostgresDriver` 在并发下会撕裂 wire protocol。
- `health_check_on_borrow=false`：ping-under-mutex 会死锁；健康由 max_idle/max_lifetime 淘汰兜底。
- zent 的 `entity_info` 是类型级声明，取法：`@TypeOf(client.user).entity_info`（不能经实例访问）。
- 行内存契约：查询/创建返回 owned Entity，字符串由 client allocator 持有，
  用 `zent_db.deinitRow(user_info, &row)` 释放；`All()` 结果用自带 `.deinit()`。

## 迁移路线（建议按风险从低到高逐表推进）

1. ~~**只读域先行**~~（✅ Phase 77 已完成）：`user.countByDay`、`group.countByDay`、
   `message.activeDateCount`、`message.activeTopEntities` 四处手工行解析
   （dupe + parseInt + freeResult 循环）已替换为 `sql_scan.queryAll(DTO, ...)` ——
   SQL 保持不变（计算列加 `AS day/count/...` 别名对齐 DTO 字段名），按列名扫描，
   字符串由 scanner 负责分配，历史 UAF 高发区（Phase 60）不再手工管理。
2. ~~**低冲突 CRUD 表**~~（✅ Phase 77 首表 + Phase 78 批量完成）：
   - `collects` 全 CRUD（Phase 77）：`addCollect`/`getCollects` 走 `sql_scan.queryOne/queryAll`
     （INSERT..RETURNING 按列名直接扫进 `model.Collect`，动态 IN 子句拼 `$N` 参数）、
     `removeCollect` 走 `crud_helpers.delete`（Collect schema 实体删除，id+user_id 双谓词
     保持归属校验）。
   - `auth_tokens`（Phase 78）：`storeToken`/`deleteByUser` → `drv.exec`（expire_time 为
     SQL 计算列）；`parseToken` → `sql_scan.queryOne(TokenInfo)`。
   - `auth_verification_codes`（Phase 78）：60s 限流检查 → `queryOne(bool DTO)`；
     upsert（ON CONFLICT）与一次性消费 DELETE → `drv.exec`；
     `checkVerificationCode` 读取 → `queryOne` + `freeDto`（一次性字符串显式释放）。
   - `fcm_tokens` / `app_logs` / `webhook_events`（Phase 78）：写入（upsert/INSERT/UPDATE
     含 NOW() 计算列）→ `drv.exec`；读取（`getFCMToken`/`getPendingWebhookEvents`）→
     `sql_scan.queryOne/queryAll`。
   - office 全量（Phase 79，低冲突层收尾）：工作圈 12 列读（get/getRecvList/getSendList/
     findRelevant）→ `sql_scan.queryAll(model.WorkMoment)`（别名对齐后按列名直扫，JOIN 列
     face_url/nickname 在列）；create → `queryOneLenient`（RETURNING 无 JOIN 列，缺席字段
     保持 ""，与 legacy 一致）；点赞/评论/已读清除（JSONB 追加/过滤更新 + upsert）→ `drv.exec`；
     unread/count → `queryOne({count:i64} DTO)`；tags CRUD（TagRow DTO 中转 + tag_members
     子查询填充 user_id_list，字符串所有权转移给返回值）；clientConfig → `queryOne`。
   - 剩余候选：`searchLogs` 动态 WHERE 查询（third 模块唯一 legacy 读写路径）。
3. **核心域**（`users`/`friends`/`groups`/`messages`；`conversations` ✅ Phase 80）：
   - schema 全量映射（含 TIMESTAMPTZ 用 `field.Time`）；
   - 写路径事务用 `zent_db.beginTx()`（TxClient，嵌套降级 savepoint）对齐现有 `Tx` 语义；
   - 会话同步批量 upsert（`upsertWithLatestBatch` 500 行分块）对位 zent
     `BulkInsert` + `SaveOrUpdateOnWith` 自定义更新表达式（v0.34.0，`GREATEST` 单调可用
     `{t:col}`/`{x:col}` 模板表达）。
4. **每迁移一域**：旧 SQL 删除 + deadcode 门禁确认为 0 + 契约测试保持绿。

### 迁移模式（Phase 77 确立）

- **双路径回退**：迁移方法先查 `zent_db.getClient()/getDriver()`，层不可用时走
  legacy `db_postgres` 分支 —— zent 初始化失败（非致命设计）时零行为变化；
  全部表迁移完毕后一次性删除 legacy 分支。
- **测试覆盖**：`IntegrationCtx.init` 在 PG 可用时同步初始化 zent 层 —— 所有
  集成测试自动走 zent 路径（不会静默回退），deinit 幂等安全。
- **DTO 即模型**：`sql_scan` 按列名扫描，SQL 计算列加别名后可直接扫进现有
  `model.*` 结构，无需中间 DTO 层。
- **UUID 主键**：表默认 `uuid_generate_v4()` 的列走 INSERT..RETURNING 读回
  （zent 实体 Create 不回写非自增主键）；实体 schema 仅用于 delete/update 谓词。
- **写语句选型**（Phase 78 确立）：含 SQL 计算列（`NOW()`、`INTERVAL`、`EXTRACT`）的
  INSERT/UPDATE/DELETE 走 `drv.exec(原 SQL, args)` —— 语义零变化、无需实体 schema；
  纯谓词删除/更新才引入 schema 走 `crud_helpers`。
- **一次性 DTO 显式释放**：`queryOne` 结果若超出请求生命周期使用（如同函数内多次
  查询），用 `sql_scan.freeDto(T, allocator, &row)` 释放；随请求 arena 回收的无需。

### BEST_PRACTICES 对齐（Phase 80 起，读 docs/BEST_PRACTICES.md 再动手）

- **API 选型决策表**（§1）：单表 CRUD → `crud_helpers`/typed builder；聚合 →
  `q.Count()`；JOIN/GROUP BY/动态 SET/表达式投影 → raw driver（这不算偷懒，
  是文档钦定的边界）。`update`/`updateSeq` 触碰非 schema 列（update_time
  TIMESTAMPTZ 未入实体）→ `drv.exec` raw 是正确姿势，typed `setExprArgs`
  会因 UnknownField 编译失败。
- **业务键 upsert**（§5a）：`SaveOrUpdateOnWith(&.{冲突列}, &.{UpsertSetExpr})`
  —— GREATEST 单调列用 `{t:col}/{x:col}` 模板（`GREATEST({t:max_seq},
  {x:max_seq})`），`NOW()` 类表达式直接写 expr；未提供 expr 的已设字段默认
  `col = EXCLUDED.col`。注意与裸 SQL 的语义差：默认分支会把**全部已设字段**
  写进 DO UPDATE SET（本例 conversation_type/user_id/group_id 由
  conversation_id 决定，值恒等价）。
- **zeroInit 与无 0 值 enum**（踩坑）：`sql_scan` 对 DTO 做 comptime
  零值初始化，无 0 tag 的 enum（ConversationType 从 1 起）直接编译失败 ——
  用 i16 中转 DTO + `@enumFromInt` 物化（见 conversation/persistence.zig
  的 ConvRow）。扫描器支持 enum 按 tag value 扫（不是 index）。
- **setFieldValue 类型精确匹配**：schema `field.Int` → i64，小整数入参
  （i16/i32）须显式 `@as(i64, v)`。
- **惰性编译掩盖既有 bug**：service 层从未被测试调用的函数（如
  conversation delete 的 bool 签名 + try 函数体）直到首次实例化才编译 ——
  迁移补测试时可能翻出潜伏错误（Phase 80 修复 delete → `!bool`）。
- **事务边界的 comptime 守卫**：`exec: anytype` 双态参数（client/Tx）里，
  zent 分支必须以 `@TypeOf(exec) == *db_mod.PostgresClient` 守卫 —— 事务内
  调用（*Tx）必须留在 legacy 分支，混用 zent 池会拿到另一个连接、破坏原子性
  （conversation upsert 的生产调用全部 Tx-bound，zent 分支待 TxClient 迁移激活）。
- **jsonb_build_object 参数必须显式转型**（Phase 79 踩坑）：zent 驱动不带类型 OID
  发送参数，`jsonb_build_object('k', $N)` 的 `any` 形参令 PG 无法推断类型
  （`could not determine data type of parameter $N`）—— zent 分支的裸参数要写
  `$N::text`/`$N::bigint`（legacy libpq 显式发 text OID 故无此问题）。
- **字符串所有权转移**：`queryAll` 结果直接改写进返回模型时（如 getTags 的
  TagRow → model.Tag），只释放列表缓冲（`rows.deinit()`，Managed 0 参），
  字符串交给调用方生命周期 —— 与 legacy dupe 进 caller allocator 的契约一致。

## 明确不做 / 注意

- **不替换** `migrations/*.sql`：zent schema 只做查询映射，DDL 仍以迁移文件为准
  （`sql_schema.migrateSchema` 仅用于纯 zent 新表）。
- `seq` 分配（`SELECT ... FOR UPDATE` + 原子 `UPDATE ... RETURNING`）迁移时用
  `Selector.forUpdateWith(LockOpts{ .skip_locked = ... })`（v0.34.0 行锁变体）。
- webhook / push 等 EventBus 异步消费路径迁移时保持"结果落 arena / 全局"的内存契约不变。
- libpq 是硬依赖：无 libpq 头文件的机器上 zent 的 `pg_c` 不会被接线，`zent_db.zig`
  将无法编译（与 zim 本身需要 libpq 的前提一致）。
