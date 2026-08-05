# zigmodu v0.15.9 sqlx 编译修复（zig 0.17-dev 兼容）

`~/w4_proj/zig_ws/zigmodu/src/sqlx/sqlx.zig` 与当前 Zig 0.17.0-dev.1422 不兼容（2 处编译错误）。
用户 commit `2b265bd`（StructuredLogger 修复）使 zigmodu 源码变化 → zig 缓存失效 → 惰性编译的 sqlx 暴露错误。

## 补丁 1 — 冗余 comptime（908 行）

```zig
        pub const has_strings = comptime typeHasStrings(T);
```
改为：
```zig
        pub const has_strings = typeHasStrings(T);
```

## 补丁 2 — 局部常量遮蔽 Row（5959/5962/5965 行，测试函数内）

```zig
    const Row = struct { id: i64, price: i64 };
    const val = try client.queryScalar(Row, "SELECT id, price FROM items WHERE id = ?1", &.{.{ .int = 1 }});
    ...
    try std.testing.expect((try client.queryScalar(Row, "SELECT id, price FROM items WHERE id = ?1", &.{.{ .int = 999 }})) == null);
```
改为（`Row` → `RowTest`，3 处）：
```zig
    const RowTest = struct { id: i64, price: i64 };
    const val = try client.queryScalar(RowTest, "SELECT id, price FROM items WHERE id = ?1", &.{.{ .int = 1 }});
    ...
    try std.testing.expect((try client.queryScalar(RowTest, "SELECT id, price FROM items WHERE id = ?1", &.{.{ .int = 999 }})) == null);
```

## 应用后验证

```bash
cd /Users/n0x/w4_proj/zigmodu_ws/zim && ./scripts/ci.sh   # 应全绿
```
