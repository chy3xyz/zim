# zim — OpenIM Server rewritten in Zig

[![CI](https://github.com/chy3xyz/zim/actions/workflows/ci.yml/badge.svg)](https://github.com/chy3xyz/zim/actions/workflows/ci.yml)

A single-process rewrite of the [OpenIM Server](https://github.com/openimsdk/open-im-server) (Go microservices → **17-module Zig Modulith**, ~53k lines), wire-compatible with the OpenIM Flutter SDK.

[中文文档](README_CN.md)

## Highlights

- **One process, no Kafka, no MongoDB** — 10+ Go microservices collapse into one Zig binary on PostgreSQL (+JSONB, +PGMQ)
- **OpenIM wire contracts** — 188 HTTP routes + WebSocket protocol (1001–2100, protobuf) aligned with the OpenIM Flutter SDK; end-to-end Flutter integration test runs against the real server
- **zent ORM, migrated incrementally** — all 8 multi-statement atomic transactions run on zent `TxClient` (typed upserts with `GREATEST` monotonic expressions), legacy SQL runs unchanged through a thin executor adapter; dual-path fallback keeps behavior stable
- **Memory-safety track record** — systematic elimination of libpq result UAFs, allocator-mismatch frees, and data races (the full trail is in [AGENTS.md](AGENTS.md), 87 phases of AI-paired development)
- **Performance** (ReleaseFast, in-process benchmark, 200 iters/op — see [docs/benchmark.md](docs/benchmark.md)):

| Operation | Throughput |
|-----------|-----------|
| login (PBKDF2) | ~75 ops/s |
| friend request | ~2667 ops/s |
| group create | ~2740 ops/s |
| message send (transactional, conversation sync) | ~1070 ops/s |

## Modules

| Domain | Modules |
|--------|---------|
| Core IM | auth (JWT + 6 login policies), user, friend, group, message (seq + edit/recall), conversation (incremental sync) |
| Enterprise | office (work moments), organization, RTC meeting persistence |
| Transport | gateway (188 declarative routes), websocket (protobuf push), push, queue (PGMQ) |
| Support | config (hot-reload), db_postgres, event_bus, third (S3 presign/FCM/webhooks), crontask |

Encryption keys (AES-256), verification codes, message filtering (type intervals + attention IDs), and per-terminal login kick policies are all included.

## Quick start

Prerequisites: Zig 0.17.0-dev.1970, PostgreSQL 15+, libpq headers.

```bash
# 1. Database (migrations auto-apply at startup)
psql -h localhost -U postgres -c 'CREATE DATABASE zim'
# set [database] in src/../config/config.yaml if not using defaults

# 2. Build & run
cd src
zig build
./zig-out/bin/zim          # HTTP :10000, WS :10001

# 3. Tests (integration tests skip cleanly when PG is unreachable)
zig build test

# 4. Full CI gate: build → test → fmt → audit → deadcode → smoke+WS
bash ../scripts/ci.sh
```

Point the [OpenIM Flutter SDK](https://github.com/openimsdk/open-im-sdk-flutter) (or the bundled `ui/zimapp` client, whose `zim_sdk` package is a pure-Dart SDK for this backend) at `http://localhost:10000` / `ws://localhost:10001`.

## Repository layout

```
src/            Zig backend (17 modules, ComptimeRouter, zent ORM layer)
migrations/     PostgreSQL DDL (auto-applied, tracked in schema_migrations)
ui/zimapp/      Flutter client — includes zim_sdk, a pure-Dart IM SDK for zim
ui/admin/       Admin console (ant-design-pro based)
docs/           Architecture, benchmarks, migration guides (Chinese)
scripts/        ci.sh gate, ws_smoke.py real-handshake test
AGENTS.md       Full development log (87 phases, AI-paired)
```

## Dependencies

- [zmodu](https://github.com/chy3xyz/zmodu) (formerly zigmodu) — application framework
- [zent](https://github.com/chy3xyz/zent) — Zig Entity Framework
- `ui/zimapp` is based on the OpenIM Flutter demo (Apache-2.0 — see [ui/zimapp/NOTICE.md](ui/zimapp/NOTICE.md))
- `ui/admin` is based on ant-design-pro (MIT — see [ui/admin/NOTICE.md](ui/admin/NOTICE.md))

## Contributing & security

See [CONTRIBUTING.md](CONTRIBUTING.md) (ground rules: dual-path persistence, allocator discipline, parameterized SQL, tests required) and [SECURITY.md](SECURITY.md) (private vulnerability reporting).

## License

[MIT](LICENSE)
