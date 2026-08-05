# zigmodu StructuredLogger 待修补丁（{any} → {s}）

`~/w4_proj/zig_ws/zigmodu/src/log/StructuredLogger.zig` 第 101 行附近，把：

```zig
                const value_str = try std.fmt.allocPrint(self.allocator, "{any}", .{value});
```

替换为：

```zig
                // String values must use {s} — {any} prints byte slices as arrays.
                const T = @TypeOf(value);
                const is_string = comptime @typeInfo(T) == .pointer and @typeInfo(T).pointer.child == u8;
                const value_str = if (is_string)
                    try std.fmt.allocPrint(self.allocator, "{s}", .{value})
                else
                    try std.fmt.allocPrint(self.allocator, "{any}", .{value});
```

应用后：`{"path":"/health","method":"GET"}`（可读）替代 `{"path":"{ 47, 104, 101, 97, 108, 116, 104 }","method":"{ 71, 69, 84 }"}`。

## 已修复（v0.15.9 之后 commit 2b265bd）

- **key 未 dupe**（comptime 字段名字面量直接入 map，defer 释放时 free 只读内存崩溃）→ 已修 + 回归测试。zim 已重新接入 StructuredLogger（core.getLogger + 启动事件 + HTTP 访问日志），实测 0 崩溃。

## 验证

```bash
# zigmodu 侧（补丁后）—— 本仓库沙箱限制 workspace 外写入，需手动应用
cd ~/w4_proj/zig_ws/zigmodu && zig build test --cache-dir /tmp/zmodu-cache 2>&1 | grep StructuredLogger

# zim 侧（已接入，补丁后访问日志字段可读）
cd /Users/n0x/w4_proj/zigmodu_ws/zim/src && zig build && ./zig-out/bin/zim
curl -s http://localhost:10000/health
# stderr 应出现 {"message":"http_request","path":"/health","method":"GET",...}
```
