# OpenIM Flutter + Volo-OpenIM 快速开始

## ✅ 当前状态

| 组件 | 状态 | 地址 |
|------|------|------|
| Volo-OpenIM 后端 | ✅ 运行中 | http://localhost:10002 |
| WebSocket 服务 | ✅ 运行中 | ws://localhost:10001 |
| PostgreSQL | ✅ Docker | localhost:5432 |
| Redis | ✅ Docker | localhost:6379 |
| Flutter 配置 | ✅ 已配置 | Android 模拟器 |

## 🚀 5分钟快速开始

### 步骤 1: 确认后端运行 (已运行)

```bash
# 检查后端健康状态
curl http://localhost:10002/health
# 应返回: {"errCode":0,"data":{"healthy":true}}
```

✅ **后端已运行** (PID: 77809)

### 步骤 2: 进入 Flutter 项目

```bash
cd /Users/n0x/ws_clawworld/volo_modulith/openim/_ref/openimsdk-open-im-flutter-enterprise
```

### 步骤 3: 安装依赖

```bash
flutter pub get
```

### 步骤 4: 配置设备类型 (已完成)

已配置为 **Android 模拟器**，如需更改：

```bash
# Android 模拟器
./setup-volo.sh android

# iOS 模拟器
./setup-volo.sh ios

# 真机调试
./setup-volo.sh device
```

### 步骤 5: 运行 Flutter 应用

```bash
# 启动 Android 模拟器 (如果尚未启动)
emulator -avd <your_avd_name>

# 运行应用
flutter run
```

## 📱 测试连接

应用启动后：

1. **点击登录页** → 进入登录界面
2. **输入测试账号**:
   - 用户名: `flutter_test_user`
   - 密码: `test123456`
3. **或注册新账号**

## 🔧 配置文件说明

当前配置文件: `openim_common/lib/src/config.dart`

```dart
// Android 模拟器配置
static String get _defaultHost => '10.0.2.2';

// API 端点
API URL:    http://10.0.2.2:10002
WebSocket:  ws://10.0.2.2:10001
```

## 🐛 常见问题

### 1. 连接超时

**现象**: 应用显示 "Connection timed out"

**解决**:
```bash
# 检查后端是否运行
curl http://localhost:10002/health

# 如果未运行，重启后端
cd /path/to/volo-openim/apps/openim-main
cargo run --release
```

### 2. 端口冲突

**现象**: "Address already in use"

**解决**:
```bash
# 查找占用端口的进程
lsof -i :10002
lsof -i :10001

# 终止进程
kill -9 <PID>
```

### 3. Flutter 构建失败

**现象**: 编译错误

**解决**:
```bash
# 清理并重新构建
flutter clean
flutter pub get
flutter run
```

## 📝 目录结构

```
openimsdk-open-im-flutter-enterprise/
├── openim_common/
│   └── lib/src/
│       ├── config.dart           ← 当前配置文件
│       ├── config_volo.dart      ← Volo 配置模板
│       └── config.dart.backup    ← 原配置备份
├── lib/                          ← Flutter 应用代码
├── setup-volo.sh                 ← 配置脚本
├── VOLO_SETUP.md                 ← 详细配置文档
└── QUICKSTART.md                 ← 本文件
```

## 🔄 切换配置

```bash
# 查看当前状态
./setup-volo.sh status

# 恢复原始配置
./setup-volo.sh restore

# 重新配置 Android
./setup-volo.sh android

# 配置 iOS
./setup-volo.sh ios

# 配置真机
./setup-volo.sh device
```

## 📊 验证清单

- [ ] Volo-OpenIM 后端运行 (curl http://localhost:10002/health)
- [ ] Flutter 依赖安装完成 (flutter pub get)
- [ ] 配置文件已更新 (config.dart)
- [ ] 设备/模拟器已连接 (flutter devices)
- [ ] 应用成功运行 (flutter run)
- [ ] 登录/注册功能正常
- [ ] WebSocket 连接正常

## 🎯 下一步

1. **测试基础功能**: 注册 → 登录 → 添加好友
2. **测试消息**: 发送文字消息 → 接收消息
3. **测试群组**: 创建群组 → 邀请成员 → 群聊
4. **查看文档**: [VOLO_SETUP.md](VOLO_SETUP.md) 了解详细配置

## 📞 获取帮助

如果遇到问题：

1. 查看后端日志: `tail -f /tmp/openim-flutter.log`
2. 查看 Flutter 日志: `flutter run --verbose`
3. 检查配置: `./setup-volo.sh status`
4. 参考详细文档: [VOLO_SETUP.md](VOLO_SETUP.md)

## 🎉 成功标志

当你看到以下信息，说明一切正常：

**后端日志**:
```
🌐 HTTP server listening on 0.0.0.0:10002
WebSocket gateway listening on 0.0.0.0:10001
```

**Flutter 日志**:
```
Connected to device
Login successful
WebSocket connected
```

**应用界面**:
- 登录成功
- 消息列表显示
- 可以收发消息

---

**当前时间**: 2026-03-14
**配置状态**: ✅ 已配置 Android 模拟器
**后端状态**: ✅ 运行中
**就绪状态**: ✅ 可以运行 Flutter 应用
