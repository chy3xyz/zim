# 自研 libpq 封装 → zigmodu sqlx 迁移评估

> 状态：评估（未实施）。日期：2026-08-05。基于 zigmodu v0.15.9。

## 现状

`src/modules/db_postgres/` 是 zim 自研的 PostgreSQL 访问层：

- `PostgresClient`：libpq（PQexecParams）封装，8 连接池（`database.max_conns` 驱动）、`PQreset` 自动重连、`ensureHealthy`、busy 标志互斥
- `Tx`：begin/commit/rollback，锁定池连接；已用于建群/加好友/删好友/解散群/注销用户/消息发送（Phase 36-37 + 本轮 B6）
- `model.QueryParam` 参数化（string/int/bigint/smallint/bool/string_array/null），libpq 原生 `$N` 占位符
- 17 个模块的 persistence 全部基于它（约 150+ 条 SQL，Phase 39 已全参数化）

## zigmodu sqlx/Repository 可提供的替代能力（v0.15.9）

| 能力 | 自研 libpq | zigmodu sqlx |
|---|---|---|
| 参数化查询 | ✓（QueryParam + `$N`） | ✓（sqlx 占位符转换，含 `?N` bug 已修） |
| 连接池 | ✓（手写 8 连接） | ✓（SqlxBackend 池） |
| 事务 | ✓（Tx） | ✓（Transaction） |
| 行扫描 | 手写 `row[i]` 解析（parseMessageRow 等） | `queryRowBorrowed`（v0.15.8 RAII，自动释放） |
| 批量写 | ✗（循环单行） | `Repository.insertMany/upsertMany`、`findByIds`（v0.15.7 bulk） |
| 多租户 | ✗（单租户，不适用） | `findPageForTenant` 等（zim 不需要） |
| CRUD 模板 | ✗（手写 SQL） | `Repository`/`CrudApi`/`data.CrudService` |

## 迁移收益

1. **消除手写行解析**：17 个 persistence 的 `rowToXxx`（约 400+ 行样板）换成 `queryRowBorrowed`，释放逻辑自动
2. **批量写**：群成员批量插入、消息批量拉取可走 `insertMany`/`findByIds`，减少 round-trip
3. **类型安全**：comptime 列名校验（列名拼错编译期报错）
4. **维护对齐**：zigmodu 官方 API 演进（如 v0.15.8 queryRow 契约）自动受益

## 迁移风险（高）

1. **地基替换**：17 个模块 150+ 条 SQL 全部依赖当前封装 —— 迁移需全量回归（现有 15 个测试覆盖有限路径，需补测）
2. **行为差异**：libpq `PQexecParams` 与 sqlx 的占位符转换/结果解析存在边界差异（NULL 处理、数组类型、时间戳精度）—— 已踩过 libpq 非 NUL 结尾、`?N` 占位等坑，sqlx 侧同样需要验证
3. **Tx 语义**：现有 Tx 在消息发送（B6）等事务中用 `exec: anytype` 抽象 —— 迁移需保持该抽象或改用 sqlx Transaction
4. **运行时依赖**：zigmodu sqlx 的驱动层（sqlite/mysql/pg）与 libpq C 绑定并存时构建复杂度增加

## 结论与建议

**不建议近期迁移**。理由：
- 自研封装已成熟（参数化、事务、池、重连、熔断统计齐全，audit/deadcode 全绿）
- 迁移是"重写持久层"级别的工程（估 2-3 倍于 B5 拆分工作量），收益主要是样板代码减少，无功能收益
- 现有 15 个测试不足以支撑全量回归，需先扩测试覆盖

**建议的渐进路径**（如未来需要）：
1. 先补足 message/group/user 的批量场景单测（覆盖现有行为）
2. 新功能（如消息批量拉取优化）优先用 sqlx Repository 做**增量接入**（并存期，不改存量）
3. 存量迁移按模块逐个做，每模块一 PR + 契约测试护航
