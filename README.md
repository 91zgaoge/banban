<div align="center">

<h1>💝 伴伴 (Banban)</h1>

**你的专属 AI 伴侣 —— 有温度、有记忆、有声音**

<p>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-AGPL--v3-blue.svg" alt="License" /></a>
  <a href="https://go.dev"><img src="https://img.shields.io/badge/Go-1.25-00ADD8?logo=go&logoColor=white" alt="Go" /></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3-02569B?logo=flutter&logoColor=white" alt="Flutter" /></a>
  <a href="https://docs.docker.com/compose/"><img src="https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white" alt="Docker" /></a>
</p>

<p>
  <a href="#-快速开始">快速开始</a> ·
  <a href="#-功能特性">功能特性</a> ·
  <a href="#-技术架构">技术架构</a> ·
  <a href="#-客户端下载">客户端</a> ·
  <a href="#-开源协议">协议</a>
</p>

<br/>

基于 [Memoh-X](https://github.com/91zgaoge/memoh-X) 基础设施构建的 AI 伴侣平台，<br/>
让每个用户都能拥有专属的、真正懂你的智能伙伴。

</div>

---

## 🌟 项目介绍

伴伴是一个**开源的 AI 伴侣平台**，不是简单的聊天机器人，而是：

- 🧠 **深度记忆** —— 记住你的喜好、习惯、故事，越聊越懂你
- 🎙️ **语音交互** —— 像打电话一样自然对话，支持语音输入和回复
- 👤 **人格定制** —— 温柔/活泼/知性，选择或创造你理想的伴侣人格
- 🔒 **隐私优先** —— 本地部署，数据完全自主掌控
- 📱 **全平台** —— iOS、Android、Windows、macOS、Linux 全覆盖

## 🚀 快速开始

### 环境要求

- Docker 20.10+
- Docker Compose 2.0+
- 4GB+ 可用内存
- 10GB+ 磁盘空间

### 一键安装

```bash
# 克隆仓库
git clone https://github.com/yourusername/banban.git
cd banban

# 启动所有服务
docker compose up -d

# 查看服务状态
docker compose ps
```

### 访问服务

| 服务 | 地址 | 说明 |
|------|------|------|
| Web 后台 | http://localhost:8082 | 管理界面 (admin/admin123) |
| FunASR STT | ws://localhost:10095 | 语音识别服务 |
| Kokoro TTS | http://localhost:8880 | 语音合成服务 |

### 配置步骤

1. **登录 Web 后台** → 设置 → Provider → 添加 AI 服务商 (OpenAI/Claude/本地模型)
2. **创建 Bot** → 选择"伴伴"类型 → 选择人格模板（杏儿/可儿/雪儿）
3. **下载客户端** → 连接 Bot → 开始对话

## ✨ 功能特性

### 🎙️ 语音对话

| 功能 | 技术 | 说明 |
|------|------|------|
| **语音输入** | FunASR (阿里达摩院) | 中文语音识别，准确率 >95% |
| **语音回复** | Kokoro-FastAPI | 67种预设音色，句子级流式合成 |
| **音频格式** | Opus/PCM/WAV | 自适应压缩，低延迟传输 |

**端到端延迟**: < 1.5 秒（首字响应）

### 🧠 深度记忆

```
用户: "我最近工作压力好大"
伴伴: "抱抱你 💙 上次你说过项目 deadline 是月底，现在进展怎么样了？"
```

**记忆层次**:
- **事实记忆** —— 个人喜好、生活习惯、重要日期
- **情感记忆** —— 情绪状态、支持记录、成长轨迹
- **解决方案** —— 过去有效的建议，下次类似问题优先推荐

**记忆机制**:
- 每次对话后自动提炼关键信息
- 24小时短期记忆 + 长期语义召回
- 时间衰减算法，新记忆权重更高

### 👤 人格系统

**预置人格模板**:

| 名称 | 类型 | 特点 |
|------|------|------|
| **杏儿** | 温柔型 | 细腻倾听、善于共情、记得每一个细节 |
| **可儿** | 活泼型 | 轻松幽默、化解尴尬、带动积极氛围 |
| **雪儿** | 知性型 | 理性分析、提供视角、陪伴成长 |

**自定义人格**:
```markdown
IDENTITY: 她是你的高中同学，现在是一名心理咨询师...
SOUL: 永远先共情再给建议，允许沉默...
TASK: 成为你情绪的避风港，陪你度过低谷...
```

### 🔒 隐私保护

- ✅ 本地部署，数据不出服务器
- ✅ 端到端 WebSocket 加密
- ✅ 用户数据隔离，多租户安全
- ✅ 开源可审计，无后门

## 🏗️ 技术架构

```
┌─────────────────────────────────────────────────────────────────┐
│                         客户端层                                 │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐               │
│  │   iOS App   │ │ Android App │ │  Desktop    │  Flutter      │
│  └─────────────┘ └─────────────┘ └─────────────┘               │
└────────────────────────────┬────────────────────────────────────┘
                             │ WebSocket
┌────────────────────────────▼────────────────────────────────────┐
│                         服务层                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Go 后端 (Echo)                        │   │
│  │  • /bots/:id/companion/ws  - WebSocket 连接             │   │
│  │  • internal/stt/           - FunASR 语音识别            │   │
│  │  • internal/tts/           - Kokoro 语音合成            │   │
│  │  • internal/memory/        - Qdrant 记忆存储            │   │
│  └─────────────────────────────────────────────────────────┘   │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                         基础设施层                               │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐               │
│  │  PostgreSQL │ │   Qdrant    │ │  containerd │               │
│  │  (业务数据)  │ │ (向量记忆)   │ │ (Bot 隔离)  │               │
│  └─────────────┘ └─────────────┘ └─────────────┘               │
└─────────────────────────────────────────────────────────────────┘
```

### 核心组件

| 组件 | 技术 | 用途 |
|------|------|------|
| **STT 服务** | FunASR v1.0 | 中文语音识别，端口 10095 |
| **TTS 服务** | Kokoro-FastAPI | 语音合成，端口 8880，67种音色 |
| **记忆存储** | Qdrant | 向量数据库，语义搜索 |
| **业务数据库** | PostgreSQL 18 | 用户、Bot、对话记录 |
| **容器运行时** | containerd | Bot 隔离运行环境 |

## 📱 客户端下载

| 平台 | 下载 | 状态 |
|------|------|------|
| iOS | App Store (审核中) | 🚧 |
| Android | [APK 下载](releases) | ✅ |
| Windows | [EXE 下载](releases) | ✅ |
| macOS | [DMG 下载](releases) | ✅ |
| Linux | [AppImage](releases) | ✅ |

**Web 测试版**: http://localhost:8082 (需先启动服务)

## 🔧 开发指南

### 项目结构

```
banban/
├── cmd/agent/              # Go 后端主程序
├── companion_app/          # Flutter 客户端
├── internal/
│   ├── stt/                # 语音识别 (FunASR)
│   ├── tts/                # 语音合成 (Kokoro)
│   ├── channel/adapters/companion/  # WebSocket 适配器
│   └── memory/             # 记忆系统
├── db/migrations/          # 数据库迁移
├── docker-compose.yml      # 服务编排
└── docs/                   # 文档
```

### 本地开发

```bash
# 启动基础设施
docker compose up -d postgres qdrant funasr kokoro-tts

# 运行后端
cd cmd/agent
go run main.go

# 运行前端 (Flutter)
cd companion_app
flutter run
```

## 🤝 参与贡献

我们欢迎各种形式的贡献：

- 🐛 提交 Bug 报告
- 💡 提出功能建议
- 🔧 提交代码 PR
- 📖 完善文档
- 🌍 翻译多语言

请阅读 [贡献指南](./CONTRIBUTING.md) 了解详情。

## 📄 开源协议

本项目采用 [AGPL-3.0](./LICENSE) 开源许可证。

> ⚠️ **注意**: AGPL 要求如果您修改并在服务器上运行本软件，必须向用户提供源代码。

## 🙏 致谢

- [Memoh-X](https://github.com/91zgaoge/memoh-X) - 基础设施底座
- [FunASR](https://github.com/alibaba-damo-academy/FunASR) - 阿里达摩院语音识别
- [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI) - 高质量 TTS
- [Qdrant](https://github.com/qdrant/qdrant) - 向量数据库

---

<div align="center">

**[⬆ 回到顶部](#-伴伴-banban)**

Made with 💝 by the Banban Team

</div>
