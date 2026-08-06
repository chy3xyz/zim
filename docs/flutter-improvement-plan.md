# zimapp Flutter 前端质量提升方案（目标 9+）

> 前置说明：本方案面向 **Flutter 环境**执行（当前沙箱无法运行 flutter/dart 工具链，
> 以下改动已评估、部分已实现，需在本地 Flutter 环境 `flutter analyze` + `flutter test` 验证后合入）。

## 现状（评估基线 5.5/10）
- 架构分层 7（本地包体系优秀）、状态管理 7（get 全局一致）
- **测试 3**（zimapp 业务逻辑 0 测试）、**质量 5**（chat_logic 3191 行）、**安全 4**（密钥硬编码）、可观测 6

## 已实现（本仓库已合入，低风险）

### 1. 密钥配置化（安全 4→6）
- `openim_common/lib/src/config.dart`：`webKey`/`webServerKey` 改为 **getter**，优先读 `DataSp`（`webKeyKey`/`webServerKeyKey`），回退默认值。
- `openim_common/lib/src/utils/data_sp.dart`：新增两个持久化 key 常量。
- **待做（Flutter 环境）**：`server_config` 页面加两个输入框（webKey/webServerKey），保存时
  `DataSp.putString(DataSp.webKeyKey, ...)` —— view 表单改动（无验证环境暂缓）。

### 2. 协议契约测试（测试 3→5）
- `zim_sdk/test/message_model_test.dart`（新增）：`Message.fromJson`/`UserInfo.fromJson` 契约测试，
  锁定 camelCase 字段名（防后端契约回归 + SDK 改名）。
- 运行：`flutter test zim_sdk/test/message_model_test.dart`。

## 待做（需 Flutter 环境，按序执行）

### P0-1. chat_logic.dart（3191 行）拆分 — 质量 5→7
按职责拆为 mixin/controller，**行为零变化**（只搬代码）：

| 新文件 | 职责 | 预估行数 |
|---|---|---|
| `chat_logic.dart` | 保留：生命周期/页面状态/入口 | ~600 |
| `chat_send_logic.dart` | 消息发送/重发/草稿（含 is_edit/is_revoke 分支） | ~700 |
| `chat_receipt_logic.dart` | 已读回执（markMessageRead / read_receipt 2200）/已读列表 | ~300 |
| `chat_mention_logic.dart` | @成员/@所有人（AtAllTag 检测、group_at_type） | ~400 |
| `chat_history_logic.dart` | 分页拉取/PullMsgBySeqList/增量同步 | ~600 |
| `chat_msg_display_logic.dart` | 消息项构建/引用回复/自定义内容 | ~600 |

**拆分方法**（机械搬移，每步验证）：
1. 每块抽出后 `flutter analyze` + 跑通单聊/群聊冒烟
2. 用 `part` 或 mixin（`with ChatSendLogic`）注入 controller
3. **禁止**跨块直接改行为；先搬后改

### P0-2. 核心逻辑单测（测试 5→8）
- `zim_sdk`（纯协议层）：消息编解码、会话列表排序、未读数计算 —— 契约测试 + 单元测试
- `openim_common`：utils.dart（2045 行）中**纯函数**（时间格式化/头像名/URL 处理）抽单测
- chat_logic 拆分后：发送状态机（sending/success/failed）、@解析、回执推进逻辑抽纯函数单测
- 目标：核心逻辑覆盖率 ≥ 40%（当前 ~0）

### P0-3. flutter analyze 纳入 CI（质量 5→8）
- 本地：`flutter analyze --fatal-infos`（当前有大量 warnings 需清零）
- CI（GitHub Actions）：`subosito/flutter-action` + `flutter analyze` + `flutter test` 两步
- **当前沙箱无法验证** —— 需在可写 Flutter 环境先清 warnings

### P1-4. 错误上报接入（可观测 6→8）
- 现有 bugly 依赖接入 `FlutterError.onError` + `PlatformDispatcher.instance.onError`
- 上报带 `webKey` 与用户 ID（脱敏）

### P2-5. 国际化统一（体验）
- strings.dart（1234 行）迁移到 `flutter_localizations` + ARB 标准 l10n
- 现有页面 intl 调用统一走 AppLocalizations

## 验收标准（9 分）
- [ ] chat_logic 拆分完成且 `flutter analyze` 0 error
- [ ] `flutter test` 全绿（含新增契约/单元测试 ≥ 30 个）
- [ ] 密钥无硬编码默认值用于生产（配置页可覆盖）
- [ ] CI 增加 analyze + test 门禁
