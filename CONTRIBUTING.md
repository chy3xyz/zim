# Contributing to zim

Thanks for your interest in contributing! zim is a single-process rewrite of the OpenIM Server in Zig — 17 modules on PostgreSQL, wire-compatible with the OpenIM Flutter SDK.

## Development setup

Prerequisites: **Zig 0.17.0-dev.1970**, **PostgreSQL 15+** with libpq headers, and locally built `zmodu`/`zent` dependencies (see [README.md](README.md) for the dependency layout: `../../../zig_ws/zmodu` and `../../../zig_ws/zent` relative to `src/`).

```bash
cd src
zig build            # build the server
zig build test       # 40 tests — integration tests skip cleanly when PG is down
bash ../scripts/ci.sh  # full gate: build → test → fmt → audit → deadcode → smoke+WS
```

## Ground rules

1. **Dual-path persistence**: migrated methods prefer zent (`zent_db.getClient()`/`getDriver()`) and keep the legacy `db_postgres` branch as fallback — never remove a fallback in the same change that adds a zent path. See [docs/zent-migration.md](docs/zent-migration.md) for the selection rules (SQL-computed columns → `drv.exec`; typed builders for single-table CRUD; `sql_scan` for DTO reads).
2. **Allocator discipline**: request-scoped results go to `core.getAllocator()` (request arena); persistent state to `core.getGlobalAllocator()`. TxClient's allocator must match the entity-free allocator (`zent_db.getAllocator()`) — see Phase 86's notes in [AGENTS.md](AGENTS.md).
3. **Parameterized SQL only** — every value binds through `$N`; no string interpolation into SQL (Phase 39 audited the full surface).
4. **Every emit frees its payload** (`defer core.getAllocator().free(payload)`).
5. **New routes** are written natively against `http.Context` (`ctx.bindJson`/`sendOk`/`sendFail`) and declared in the domain `*_routes` list; responses are camelCase to match the OpenIM SDK.
6. **New migrations** go to `migrations/NNN_name.sql` and auto-apply at startup (tracked in `schema_migrations`; failures abort startup).
7. **Every behavior change ships with a test** — integration tests exercise the real PostgreSQL path, contract tests use the in-process Testkit.

## Pull requests

- Keep one logical change per PR; CI runs the same gate as `scripts/ci.sh`.
- If your change touches a persistence method, run the suite twice — the first run may mask ordering-dependent leaks.
- Update [AGENTS.md](AGENTS.md)'s phase log when a change lands a new capability or fixes a real defect; that file is the project's engineering journal.

## Reporting issues

Include: zig/zmodu/zent versions, PostgreSQL version, minimal reproduction, and the JSON log lines around the failure (stderr or the configured `[log] file`).
