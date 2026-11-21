# zim — 用 Zig 重写的 OpenIM Server

[OpenIM Server](https://github.com/openimsdk/open-im-server) 的单进程重写：Go 微服务（10+）→ **17 模块 Zig Modulith**（约 5.3 万行），与 OpenIM Flutter SDK 线协议兼容。

[English](README.md)

## 特性

- **单进程，无 Kafka、无 MongoDB** — 10+ Go 微服务收敛为一个 Zig 二进制，只依赖 PostgreSQL（+JSONB、+PGMQ）
- **OpenIM 线协议契约** — 188 条 HTTP 路由 + WebSocket 协议（1001–2100，protobuf）对齐 OpenIM Flutter SDK；Flutter 端到端集成测试直连真实后端
- **zent ORM 渐进迁移** — 全部 8 处多语句原子事务跑 zent `TxClient`（typed upsert + `GREATEST` 单调表达式），legacy SQL 经薄适配器原语句执行；双路径回退保证行为稳定
- **内存安全实践** — libpq 结果 UAF、跨分配器释放、数据竞争的系统性根治记录见 [AGENTS.md](AGENTS.md)（87 个 Phase 的 AI 结对开发全记录）
- **性能**（ReleaseFast，进程内基准，每项 200 次迭代 — 见 [docs/benchmark.md](docs/benchmark.md)）：

| 操作 | 吞吐 |
|------|------|
| 登录（PBKDF2） | ~75 ops/s |
| 好友申请 | ~2667 ops/s |
| 建群 | ~2740 ops/s |
| 发消息（事务 + 会话同步） | ~1070 ops/s |

## 模块

| 域 | 模块 |
|----|------|
| 核心 IM | auth（JWT + 6 种登录策略）、user、friend、group、message（seq + 编辑/召回）、conversation（增量同步） |
| 企业 | office（工作圈）、organization、RTC 会议持久化 |
| 通道 | gateway（188 条声明式路由）、websocket（protobuf 推送）、push、queue（PGMQ） |
| 支撑 | config（热加载）、db_postgres、event_bus、third（S3 预签名/FCM/webhook）、crontask |

内置端到端加密密钥、验证码、消息过滤（类型区间 + attentionIds）、多终端踢线策略。

## 快速开始

前置：Zig 0.17.0-dev.1970、PostgreSQL 15+、libpq 头文件。

```bash
# 1. 数据库（迁移在启动时自动应用）
psql -h localhost -U postgres -c 'CREATE DATABASE zim'
# 非默认配置请改 config/config.yaml 的 [database] 段

# 2. 构建运行
cd src
zig build
./zig-out/bin/zim          # HTTP :10000，WS :10001

# 3. 测试（PG 不可达时集成测试优雅跳过）
zig build test

# 4. 完整 CI 门禁：build → test → fmt → audit → deadcode → smoke+WS
bash ../scripts/ci.sh
```

将 [OpenIM Flutter SDK](https://github.com/openimsdk/open-im-sdk-flutter)（或仓库内 `ui/zimapp` 客户端——其 `zim_sdk` 包是专为 zim 后端写的纯 Dart SDK）指向 `http://localhost:10000` / `ws://localhost:10001`。

## 仓库结构

```
src/            Zig 后端（17 模块、ComptimeRouter、zent ORM 层）
migrations/     PostgreSQL DDL（启动自动应用，schema_migrations 跟踪）
ui/zimapp/      Flutter 客户端 — 含 zim_sdk 纯 Dart IM SDK
ui/admin/       管理后台（基于 ant-design-pro）
docs/           架构/基准/迁移文档（中文）
scripts/        ci.sh 门禁、ws_smoke.py 真实握手测试
AGENTS.md       开发全记录（87 个 Phase）
```

## 依赖

- [zmodu](https://github.com/chy3xyz/zmodu)（原名 zigmodu）— 应用框架
- [zent](https://github.com/chy3xyz/zent) — Zig Entity Framework
- `ui/zimapp` 基于 OpenIM Flutter demo（Apache-2.0 — 见 [ui/zimapp/NOTICE.md](ui/zimapp/NOTICE.md)）
- `ui/admin` 基于 ant-design-pro（MIT — 见 [ui/admin/NOTICE.md](ui/admin/NOTICE.md)）

## 参与贡献与安全

见 [CONTRIBUTING.md](CONTRIBUTING.md)（贡献守则：双路径持久化、分配器纪律、参数化 SQL、变更须带测试）与 [SECURITY.md](SECURITY.md)（漏洞私下报告渠道）。

## 许可证

[MIT](LICENSE)
