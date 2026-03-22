# 伴伴 Companion App

Flutter 跨平台客户端（iOS / Android / Windows / Linux / macOS）

## 快速开始

### 1. 安装 Flutter

参考 [flutter.dev](https://docs.flutter.dev/get-started/install)，SDK 版本 >= 3.3.0。

### 2. 初始化平台文件

在 `companion_app/` 目录下运行：

```bash
# 生成 Android / iOS / Linux / macOS / Windows / Web 平台脚手架
flutter create . --project-name companion_app --org com.banban

# 安装依赖
flutter pub get
```

> `flutter create .` 只会填充缺失的平台文件，不会覆盖已有的 `lib/` 代码。

### 3. 运行

```bash
# Android 模拟器
flutter run -d android

# iOS 模拟器（macOS 需要 Xcode）
flutter run -d ios

# 桌面（当前平台）
flutter run -d linux    # 或 macos / windows
```

### 4. 配置

启动后在登录界面填写：

- **服务器地址**：后端地址，例如 `http://192.168.1.100:8080`
- **用户名 / 密码**：Memoh 账号

---

## 项目结构

```
lib/
├── main.dart                    # 入口
├── app.dart                     # GoRouter 路由 + Material 主题
├── core/
│   ├── api/
│   │   ├── api_client.dart      # Dio（Bearer JWT 自动注入）
│   │   └── websocket_client.dart # WS 连接 + 指数退避重连
│   └── auth/
│       ├── auth_repository.dart  # 登录 / 登出 / Token 管理
│       └── secure_storage.dart   # flutter_secure_storage 封装
└── features/
    ├── onboarding/
    │   └── screens/
    │       ├── login_screen.dart      # 登录界面
    │       └── bot_picker_screen.dart # 选择伴伴
    └── companion/
        ├── models/chat_message.dart   # 消息模型
        ├── bloc/                      # BLoC 状态管理
        │   ├── companion_bloc.dart
        │   ├── companion_event.dart
        │   └── companion_state.dart
        ├── screens/companion_screen.dart # 主对话界面
        └── widgets/
            ├── message_bubble.dart    # 消息气泡（用户/助手）
            └── streaming_text.dart   # Delta 流式渐入动画
```

## WebSocket 协议

连接地址：`ws://<host>/bots/<bot_id>/companion/ws?token=<JWT>`

| 方向 | 帧 | 说明 |
|------|-----|------|
| 上行 | `{"type":"input_text","text":"..."}` | 发送文字 |
| 上行 | `{"type":"ping"}` | 心跳（每25s） |
| 下行 | `{"type":"status","status":"thinking"}` | 正在思考 |
| 下行 | `{"type":"delta","text":"..."}` | 流式增量 |
| 下行 | `{"type":"final","text":"...","duration_ms":N}` | 完整回复 |
| 下行 | `{"type":"error","message":"..."}` | 错误 |
| 下行 | `{"type":"pong"}` | 心跳响应 |

## Phase 2 计划

- 语音输入（FunASR STT）
- 语音合成（Kokoro-ONNX TTS）
- VAD 自动检测静音
- 记忆浏览界面
