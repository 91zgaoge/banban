# 贡献指南

感谢您对**伴伴 (Banban)** 项目的关注！我们欢迎任何形式的贡献，包括但不限于：

- 提交 Bug 报告
- 提交功能请求
- 提交代码修复或新功能
- 改进文档
- 分享使用经验

## 如何贡献

### 报告 Bug

如果您发现了 Bug，请通过 [GitHub Issues](https://github.com/91zgaoge/banban/issues) 报告。报告时请包含以下信息：

1. **问题描述**：清晰简洁地描述 Bug
2. **复现步骤**：列出复现 Bug 的具体步骤
3. **预期行为**：描述您期望发生什么
4. **实际行为**：描述实际发生了什么
5. **环境信息**：操作系统、Docker 版本、浏览器等
6. **截图或日志**：如有相关截图或错误日志，请一并提供

### 请求新功能

如果您有新功能的想法，欢迎通过 [GitHub Issues](https://github.com/91zgaoge/banban/issues) 提交。请包含：

1. **功能描述**：清晰描述您想要的功能
2. **使用场景**：描述这个功能在什么情况下有用
3. **可能的实现方案**：如果您有实现思路，欢迎分享

### 提交代码

1. **Fork 仓库**：点击右上角的 Fork 按钮创建您的 Fork
2. **克隆仓库**：
   ```bash
   git clone https://github.com/YOUR_USERNAME/banban.git
   cd banban
   ```
3. **创建分支**：
   ```bash
   git checkout -b feature/your-feature-name
   ```
4. **进行开发**：编写您的代码
5. **提交更改**：
   ```bash
   git add .
   git commit -m "feat: 添加新功能描述"
   git push origin feature/your-feature-name
   ```
6. **创建 Pull Request**：在 GitHub 上创建 PR 到主仓库

## 代码规范

### Go 代码规范

- 使用 `gofmt` 格式化代码
- 遵循 [Effective Go](https://golang.org/doc/effective_go.html) 指南
- 函数和变量使用有意义的命名
- 导出函数和类型需要添加文档注释
- 错误处理要完整，不要忽略错误返回值

### Flutter 代码规范

- 使用 `dart format` 格式化代码
- 遵循 [Effective Dart](https://dart.dev/guides/language/effective-dart) 指南
- 状态管理使用 BLoC 模式
- Widget 命名使用 PascalCase

### 提交信息规范

我们使用 [Conventional Commits](https://www.conventionalcommits.org/) 规范：

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Type 类型：**

- `feat`: 新功能
- `fix`: 修复 Bug
- `docs`: 文档更新
- `style`: 代码格式修改（不影响功能的空格、分号等）
- `refactor`: 代码重构
- `perf`: 性能优化
- `test`: 测试相关
- `chore`: 构建过程或辅助工具的变动

**示例：**

```
feat(companion): 添加语音输入支持

接入 FunASR 实现实时中文语音识别，端口 10095，
支持 Opus/PCM/WAV 格式，句子级流式传输。

Closes #42
```

## 开发环境设置

### 前置要求

- Docker 20.10+ 和 Docker Compose 2.0+
- Go 1.25+（后端开发）
- Flutter 3.x+（客户端开发）
- 4GB+ 可用内存
- 10GB+ 磁盘空间（含模型文件）

### 启动开发环境

```bash
# 克隆仓库
git clone https://github.com/91zgaoge/banban.git
cd banban

# 启动所有服务（含 FunASR 和 Kokoro TTS）
docker compose up -d

# 仅启动基础设施（本地开发后端时）
docker compose up -d postgres qdrant funasr kokoro-tts

# 运行后端
cd cmd/agent
go run main.go

# 运行 Flutter 客户端
cd companion_app
flutter run
```

访问 http://localhost:8082，默认账号：`admin` / `admin123`

## 测试

在提交 PR 之前，请确保：

1. Go 代码可以正常编译
2. 相关测试用例通过
3. 没有引入新的 lint 错误

```bash
# Go 测试
cd /path/to/banban
go test ./...

# Flutter 测试
cd companion_app
flutter test
```

## 代码审查

所有 Pull Request 都需要经过至少一名维护者的审查。请保持耐心，积极响应审查意见。

## 许可证

通过向本项目提交代码，您同意您的贡献将按照 [AGPL-3.0](LICENSE) 许可证发布。

## 获取帮助

- [GitHub Discussions](https://github.com/91zgaoge/banban/discussions)
- 在 Issue 中 @ 相关维护者

---

再次感谢您的贡献！Made with 💝 by the Banban Team
