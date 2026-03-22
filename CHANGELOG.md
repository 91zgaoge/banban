# 更新日志 (Changelog)

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] — 2026-03-22

### 🎉 首次发布 — 伴伴 AI 伴侣平台

伴伴是基于 [Memoh-X](https://github.com/91zgaoge/memoh-X) 基础设施构建的开源 AI 伴侣平台。本次发布包含完整的语音对话、深度记忆和人格定制功能。

---

### ✨ 新功能

#### 🎙️ 语音对话系统

- **STT 语音输入** — 集成 FunASR（阿里达摩院），支持实时中文语音识别
  - WebSocket 音频帧协议（Opus/PCM/WAV 格式）
  - 服务端口：10095
  - 准确率 >95%（标准普通话）

- **TTS 语音输出** — 集成 Kokoro-FastAPI，高质量语音合成
  - 67 种预设语音，支持中英文
  - 句子级流式合成，首字延迟 <400ms
  - WebSocket `tts_chunk` 帧实时推送
  - 服务端口：8880

- **端到端延迟** <1.5 秒（首字响应，网络正常条件下）

#### 🧠 深度记忆系统

- **三层记忆架构**：
  - Qdrant 向量语义搜索
  - BM25 关键词精确索引
  - LLM 智能提炼（对话后自动提取关键信息）
- **记忆类型**：事实记忆 / 情感记忆 / 解决方案记忆
- **时间衰减**：新记忆权重更高（半衰期 30 天）
- **companion 命名空间**：与通用记忆隔离，专属伴侣场景

#### 👤 人格定制系统

- **三种预置人格模板**：
  - 杏儿（温柔型）— 细腻倾听、善于共情
  - 可儿（活泼型）— 轻松幽默、化解尴尬
  - 雪儿（知性型）— 理性分析、提供视角
- **自定义人格**：通过 IDENTITY / SOUL / TASK 三段式定义
- 数据库表：`companion_persona_templates` / `companion_user_settings`

#### 📱 Flutter 全平台客户端

- 支持平台：iOS / Android / Windows / macOS / Linux
- 流式文字展示（delta 帧逐字渐现）
- 断线自动重连（指数退避，最大 30s）
- JWT 认证，`flutter_secure_storage` 安全存储

#### 🔌 WebSocket 实时通信协议

**上行帧（客户端 → 服务端）**：
```json
{"type":"input_text","text":"今天好累"}
{"type":"input_audio","codec":"opus","data":"<base64>","seq":1,"is_final":true}
{"type":"ping"}
```

**下行帧（服务端 → 客户端）**：
```json
{"type":"status","status":"thinking"}
{"type":"delta","text":"抱抱你"}
{"type":"final","text":"抱抱你，说说发生什么了？","duration_ms":1230}
{"type":"tts_chunk","audio":"<base64 Opus>","seq":1}
{"type":"pong"}
```

#### 🏗️ 后端架构

- **Companion Channel Adapter** — WebSocket 适配器，SessionHub 管理并发连接
- **companion_indexer** — 对话结束后异步提炼记忆写入 Qdrant
- **记忆检索注入** — 每次对话前检索 companion 命名空间，注入 Agent 上下文
- **容器化部署** — Docker Compose 一键启动所有服务

---

### 📦 依赖组件版本

| 组件 | 版本 |
|------|------|
| FunASR Runtime SDK | `funasr-runtime-sdk-online-cpu-0.1.12` |
| Kokoro-FastAPI | `latest` (CPU) |
| Qdrant | `latest` |
| PostgreSQL | `18-alpine` |
| Go | `1.25` |
| Flutter | `3.x` |

---

### 🚀 快速开始

```bash
git clone https://github.com/91zgaoge/banban.git
cd banban
docker compose up -d
```

访问 http://localhost:8082，默认账号：`admin` / `admin123`

---

[1.0.0]: https://github.com/91zgaoge/banban/releases/tag/v1.0.0
