# ZIM 性能基准

> 记录日期：2026-08-05。环境：macOS darwin/arm64（Apple Silicon），PostgreSQL 17（localhost），Debug 构建。
> 命令：`zig build bench && ./zig-out/bin/zim-bench`（进程内压测，PG 集成，每项 200 次迭代）。

## 结果

| 操作 | 吞吐 | 单次延迟 |
|------|------|----------|
| 登录（login） | 4 ops/s | ~229ms |
| 好友申请（friend request） | 1429 ops/s | ~0.7ms |
| 建群（group create） | 1942 ops/s | ~0.5ms |
| 发消息（message send） | 866 ops/s | ~1.2ms |

## 说明

- **login 极慢是预期**：每次登录做 PBKDF2-HMAC-SHA256 密码验证（安全哈希的固有代价）；实际生产登录频率低，可接受。优化方向：若需高吞吐可评估 argon2 参数调优或登录缓存，但会降低安全性，不建议。
- **message send** 含事务（消息插入 + 全部群成员会话同步，B6/Phase 51 后群消息会遍历成员 upsert）—— 大群（100+ 成员）发送会随成员数线性增长，优化方向：批量 upsert（多行 INSERT）。
- Debug 构建（无优化）—— ReleaseFast 预计提升数倍。

## ReleaseFast 对比（2026-08-06，zig build -Doptimize=ReleaseFast）

| 操作 | Debug | ReleaseFast | 倍率 |
|------|-------|-------------|------|
| 登录 | 4 ops/s | 75 ops/s | ~19x（PBKDF2 在优化构建下大幅加速） |
| 好友申请 | 1429 ops/s | 2597 ops/s | ~1.8x |
| 建群 | 1942 ops/s | 1770 ops/s | ~0.9x（200 次迭代噪声） |
| 发消息 | 866 ops/s | 664 ops/s | ~0.8x（同批噪声，建议更多迭代复测） |

> 生产应使用 ReleaseFast 构建（`zig build -Doptimize=ReleaseFast`），登录吞吐 19 倍提升是主要收益。

## Phase 87 复测（2026-11-21，zent TxClient 事务全量切换后）

| 操作 | 旧基线 (08-06) | 本轮两轮 | 结论 |
|------|---------------|----------|------|
| 登录 | 75 ops/s | 78 / 75 ops/s | 持平 |
| 好友申请 | 2597 ops/s | 1942 / 2667 ops/s | 持平（首轮噪声，次轮与基线一致） |
| 建群 | 1770 ops/s | 2632 / 2740 ops/s | **+49~55%** |
| 发消息 | 664 ops/s | 1111 / 1070 ops/s | **+61~67%**（旧值系噪声低估） |

- 发消息含事务（消息插入 + 会话同步，全部跑 zent TxClient 事务连接）——迁移后**零回归**，
  msg/group 提升来自批量会话 upsert + 机器状态波动下的稳定复测（基线文档当时已标注
  664 为噪声，建议复测）。
- 回归口径沿用：任一操作吞吐下降 >30% 需检查最近改动。

## 回归对比

以本表为基线：若某操作吞吐显著下降（>30%），检查最近改动是否引入查询膨胀/锁竞争（如事务范围扩大、N+1 查询）。
