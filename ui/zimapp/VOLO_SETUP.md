# OpenIM Flutter + Volo-OpenIM 配置指南

本文档介绍如何将 OpenIM Flutter 客户端连接到 Volo-OpenIM Rust 后端。

## 🏗️ 架构说明

### 原版 OpenIM 架构
```
Flutter Client
    │
    ├──→ Chat API (port 10009)
    ├──→ Auth API (port 10008)
    ├──→ IM API (port 10002)
    └──→ WebSocket (port 10001)
```

### Volo-OpenIM 架构
```
Flutter Client
    │
    ├──→ Unified API (port 10002) ← 所有 HTTP API
    └──→ WebSocket (port 10001)   ← 实时消息
```

**区别**: Volo-OpenIM 使用统一的端口 10002 处理所有 API 请求（包括认证、消息、用户管理等），简化了架构。

## 🚀 快速开始

### 1. 启动 Volo-OpenIM 后端

```bash
cd /path/to/volo-openim/apps/openim-main

# 确保依赖服务运行
docker-compose -f docker-compose.dev.yml up -d

# 启动 OpenIM 服务
export DATABASE_URL="postgres://openim:openim_password@localhost:5432/openim"
export REDIS_URL="redis://localhost:6379"
export OPENIM_SECRET="flutter_test_secret_key"
export STORAGE_TYPE="local"

cargo run --release
```

验证后端运行:
```bash
curl http://localhost:10002/health
# 应返回: {"errCode":0,"data":{"healthy":true}}
```

### 2. 配置 Flutter 客户端

```bash
cd /path/to/openimsdk-open-im-flutter-enterprise

# 使脚本可执行
chmod +x setup-volo.sh

# 根据你的设备类型选择配置
./setup-volo.sh android    # Android 模拟器
./setup-volo.sh ios        # iOS 模拟器
./setup-volo.sh device     # 真机调试
```

### 3. 运行 Flutter 应用

```bash
# 安装依赖
flutter pub get

# 运行应用
./setup-volo.sh run
# 或直接使用
flutter run
```

## 📱 设备特定配置

### Android 模拟器

```bash
./setup-volo.sh android
```

配置:
- API Base URL: `http://10.0.2.2:10002`
- WebSocket URL: `ws://10.0.2.2:10001`

> **注意**: 10.0.2.2 是 Android 模拟器访问主机的特殊 IP

### iOS 模拟器

```bash
./setup-volo.sh ios
```

配置:
- API Base URL: `http://localhost:10002`
- WebSocket URL: `ws://localhost:10001`

### 真机调试

```bash
./setup-volo.sh device
```

脚本会自动检测你的电脑 IP，例如:
- API Base URL: `http://192.168.1.100:10002`
- WebSocket URL: `ws://192.168.1.100:10001`

**要求**: 手机和电脑必须在同一 WiFi 网络下。

## ⚙️ 应用内服务器配置

Flutter 应用启动后，你可以在应用内动态修改服务器配置：

1. 进入 **我的** → **设置** → **服务器设置**
2. 填写以下信息：

| 字段 | Android 模拟器 | iOS 模拟器 | 真机 |
|------|---------------|-----------|------|
| 服务器地址 | 10.0.2.2 | localhost | 192.168.x.x |
| App地址 | http://10.0.2.2:10002 | http://localhost:10002 | http://192.168.x.x:10002 |
| SDK API地址 | http://10.0.2.2:10002 | http://localhost:10002 | http://192.168.x.x:10002 |
| SDK WS地址 | ws://10.0.2.2:10001 | ws://localhost:10001 | ws://192.168.x.x:10001 |

3. 点击保存，应用会自动重启并使用新配置

## 🔧 网络配置

### Android 网络权限

`android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

<application
    android:usesCleartextTraffic="true"
    ...>
</application>
```

### iOS 网络配置

`ios/Runner/Info.plist`:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

## 🐛 故障排除

### 连接被拒绝

```
Error: Connection refused
```

**解决**:
1. 确认 volo-openim 后端已启动: `curl http://localhost:10002/health`
2. 检查 IP 地址是否正确
3. 对于真机，确认手机和电脑在同一 WiFi

### 超时错误

```
Error: Connection timed out
```

**解决**:
1. 检查防火墙设置，确保端口 10001 和 10002 开放
2. 对于 macOS，检查系统偏好设置 → 安全性与隐私 → 防火墙

### 认证失败

```
Error: Invalid token / 401 Unauthorized
```

**解决**:
1. 重新登录获取新 token
2. 检查服务器配置是否正确
3. 确认 OPENIM_SECRET 环境变量一致

### WebSocket 连接失败

**解决**:
1. 确认 WebSocket 端口 10001 可访问
2. 检查是否有代理/VPN 干扰
3. 尝试使用 HTTP 而不是 WS 进行测试

## 📊 验证连接

### 1. 测试 API

```bash
# 注册测试
curl -X POST http://localhost:10002/account/register \
  -H "Content-Type: application/json" \
  -d '{"user_id":"test","nickname":"Test","password":"123456","platform_id":1}'

# 登录测试
curl -X POST http://localhost:10002/account/login \
  -H "Content-Type: application/json" \
  -d '{"user_id":"test","secret":"123456"}'
```

### 2. 查看日志

Volo-OpenIM 后端日志:
```bash
tail -f /tmp/openim-flutter.log
```

Flutter 日志:
```bash
flutter run --verbose
```

## 🔄 切换回原配置

如果你想切换回原版 OpenIM 后端：

```bash
./setup-volo.sh restore
```

## 📝 配置参考

### Config 文件结构

```dart
class Config {
  // 服务器 IP (根据平台自动选择)
  static String get _defaultHost {
    if (Platform.isAndroid) return '10.0.2.2';
    if (Platform.isIOS) return 'localhost';
    return 'localhost';
  }
  
  // API URL (Volo-OpenIM 统一使用 10002 端口)
  static String get imApiUrl => 'http://$serverIp:10002';
  
  // WebSocket URL
  static String get imWsUrl => 'ws://$serverIp:10001';
  
  // 认证 URL (Volo 中与 API 相同)
  static String get appAuthUrl => 'http://$serverIp:10002';
}
```

## 🎯 功能对比

| 功能 | 原版 OpenIM | Volo-OpenIM |
|------|-------------|-------------|
| 用户注册/登录 | ✅ | ✅ |
| 好友管理 | ✅ | ✅ |
| 群组管理 | ✅ | ✅ |
| 消息收发 | ✅ | ✅ |
| WebSocket 实时消息 | ✅ | ✅ |
| 文件上传 | ✅ (MinIO) | ✅ (Local/Garage) |
| 组织架构 | ✅ | ✅ |
| 工作流 | ✅ | ✅ |

## 📚 相关文档

- [Volo-OpenIM 部署指南](../../volo-openim/docs/DEPLOYMENT.md)
- [Flutter 集成指南](../../volo-openim/docs/FLUTTER_INTEGRATION.md)
- [API 测试文档](../../volo-openim/docs/TESTING.md)

## 💡 提示

1. **开发模式**: 使用 `cargo run` 启动后端，代码修改后自动重载
2. **日志级别**: 设置 `RUST_LOG=debug` 查看详细日志
3. **热重载**: Flutter 支持热重载，保存代码后自动更新 UI
4. **网络调试**: 使用 Chrome DevTools 调试 Flutter Web 网络请求

## 🎉 成功标志

当你看到以下日志，说明连接成功：

**Volo-OpenIM 后端**:
```
User authenticated: flutter_user_xxx
WebSocket connection established
```

**Flutter 应用**:
```
Login successful
WebSocket connected
Message received: {...}
```

现在你可以开始使用 OpenIM Flutter 客户端与 Volo-OpenIM 后端进行开发测试了！
