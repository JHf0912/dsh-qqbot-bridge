# dsh-qqbot-safe

基于腾讯官方 QQ 机器人开放平台，将 QQ 私聊或群聊安全地接入 [DeepSeek Harness（DSH）](https://github.com/deepseek-ai/deepseek-harness)。给机器人发送消息，就等同于向一个独立的 DSH Agent 会话发送消息。

> 当前版本：`0.1.0`。项目仍处于早期阶段，建议先使用专用测试机器人、专用工作目录和私聊白名单。

## 特性

- 只使用腾讯 QQ 机器人开放平台和腾讯官方 SDK，不使用个人 QQ 逆向协议、Hook、注入或模拟登录。
- 首次启动支持腾讯官方扫码绑定，自动保存 AppID、Secret 和扫码用户 OpenID。
- 私聊默认白名单，群聊默认关闭；空白名单不会退化成开放访问。
- QQ 消息直接驱动 DSH Agent，支持流式回复、会话持久化和模型切换。
- 支持在 QQ 内处理 DSH 的一次性权限申请：`/approve CODE` 或 `/deny CODE`。
- AppSecret、OpenID 和 API Key 仅保存在本机 `$DSH_HOME/.env`，不进入项目配置和日志。
- 内置隐私扫描、单元测试、打包检查和 GitHub Actions CI。

## 合规说明

本项目仅面向腾讯官方机器人能力。使用前请遵守腾讯 QQ 开放平台规则、机器人运营规范和所在地法律法规。平台审核、接口权限、主动消息窗口和频率限制以腾讯当前规则为准。本项目无法承诺账号绝对不会受到限制，但不会提供绕过风控或协议限制的实现。

## 快速启动

### 准备条件

- Windows 10/11、macOS 或 Linux
- Node.js `>= 22`
- pnpm `11.x`（推荐通过 Corepack 管理）
- 已安装并能正常运行的 DSH `>= 0.1.0-rc.6`
- 可用的 DeepSeek 模型凭据
- 一个腾讯官方 QQ 机器人

如果 DSH 使用 DeepSeek 官方接口，请把 API Key 写入本机 DSH 环境文件，而不是项目目录：

```dotenv
# Windows 默认位置：C:\Users\<你>\.dsh\.env
# macOS/Linux 默认位置：~/.dsh/.env
DEEPSEEK_API_KEY="你的 API Key"
```

### Windows：从源码一键启动

下载或克隆仓库后，在项目根目录执行：

```powershell
corepack enable
pnpm install --frozen-lockfile
powershell -ExecutionPolicy Bypass -File .\scripts\dev-start.ps1
```

脚本会完成：

1. 安装依赖并构建 TypeScript；
2. 创建或更新 `qqbot-safe-dev` profile；
3. 将 profile 链接到当前源码，后续重新构建即可测试最新代码；
4. 启动 DSH。

首次没有 QQ 凭据时，终端会显示官方绑定二维码。扫码成功后，插件会自动写入：

```dotenv
QQBOT_APPID="..."
QQBOT_SECRET="..."
QQBOT_C2C_ALLOW="..."
```

这些值保存在 `$DSH_HOME/.env`，不会写入仓库。扫码用户会自动成为第一个私聊白名单用户。看到以下内容后即可在 QQ 中发送“你好”：

```text
[im-qqbot] Bot ready! appId=...
```

以后启动可直接执行：

```powershell
node "$env:USERPROFILE\.dsh\profiles\node_modules\@deepseek-ai\dsh\lib\bin.js" --profile qqbot-safe-dev
```

如果设置了自定义 `DSH_HOME`，请将路径替换为对应目录。

### npm 发布后安装

```bash
dsh plugin --profile qqbot add dsh-qqbot-safe
dsh --profile qqbot
```

如果 `dsh` 没有加入 PATH，可直接调用 `$DSH_HOME/profiles/node_modules/@deepseek-ai/dsh/lib/bin.js`。

## 隐私配置教程

### 本机私密文件

所有敏感配置统一放在：

```text
$DSH_HOME/.env
```

默认位置：

- Windows：`C:\Users\<你>\.dsh\.env`
- macOS/Linux：`~/.dsh/.env`

示例：

```dotenv
QQBOT_APPID="机器人 AppID"
QQBOT_SECRET="机器人 AppSecret"
QQBOT_C2C_ALLOW="用户OpenID1,用户OpenID2"
DEEPSEEK_API_KEY="DeepSeek API Key"
```

多个用户 OpenID 使用英文逗号分隔。不要把个人 QQ 号当作 OpenID。

### Profile 配置

Profile 配置位于 `$DSH_HOME/profiles/<profile>/cordis.patch.yml`。推荐保持 OpenID 在 `.env`，YAML 只读取环境变量：

```yaml
- id: im-qqbot
  config:
    cwd: 'D:/dsh-workspaces/qqbot'
    provider: deepseek-official
    model: deepseek-v4-flash
    requireMention: true

    access:
      c2cMode: allowlist
      c2cAllow: !!js >-
        (process.env.QQBOT_C2C_ALLOW ?? '')
          .split(',')
          .map((value) => value.trim())
          .filter(Boolean)
      groupMode: disabled
      groupAllow: []

    acknowledgeOpenAccess: false
    allowUnsafeCwd: false
    logMessageContent: false
    enableApprovals: true
    approvalTimeoutMs: 120000
    debug: false
```

修改 `.env` 或 profile 后应完整重启 DSH：`Ctrl+C` 停止，再重新运行启动命令。

### 哪些内容不能上传

不要提交或粘贴到 Issue、PR、截图和日志中：

- `$DSH_HOME/.env` 或项目 `.env`
- `QQBOT_SECRET`、`DEEPSEEK_API_KEY`
- 真实用户/群 OpenID、消息 ID、TraceId
- 二维码绑定链接或尚未失效的二维码
- `$DSH_HOME/sessions`、`qqbot-workspace`、聊天记录和生成文件

提交前运行：

```bash
pnpm privacy:check
pnpm check
```

`.gitignore` 已排除常见本地敏感文件，但不能替代人工复核。

## QQ 权限审批

当工具需要访问工作区之外的位置时，DSH 会先触发审批。插件向任务发起者发送：

```text
⚠️ DSH 权限申请
工具：pwsh
原因：需要访问工作区外路径

允许本次操作：/approve A1B2C3
拒绝本次操作：/deny A1B2C3
```

审批具有以下边界：

- 仅任务发起者本人可以处理；
- 验证码一次性使用；
- 只授权当前操作，不永久开放磁盘；
- 默认 120 秒超时自动拒绝；
- Agent 取消或 DSH 退出时自动取消；
- 群聊中其他成员即使看到验证码也不能批准。

## 主要配置

| 配置 | 默认值 | 说明 |
|---|---:|---|
| `provider` | `deepseek-official` | DSH LLM provider |
| `model` | `deepseek-v4-flash` | DSH 模型；可通过 `/model` 切换 |
| `cwd` | `./qqbot-workspace` | Agent 专用工作目录 |
| `requireMention` | `true` | 群聊是否必须 @机器人 |
| `access.c2cMode` | `allowlist` | 私聊访问策略 |
| `access.c2cAllow` | 来自环境变量 | 允许的用户 OpenID |
| `access.groupMode` | `disabled` | 群聊访问策略 |
| `access.groupAllow` | `[]` | 允许的群 OpenID |
| `acknowledgeOpenAccess` | `false` | 开放访问的二次风险确认 |
| `allowUnsafeCwd` | `false` | 是否允许根目录或用户主目录 |
| `logMessageContent` | `false` | 是否记录消息正文 |
| `enableApprovals` | `true` | 是否启用 QQ 一次性审批 |
| `approvalTimeoutMs` | `120000` | 审批超时，超时自动拒绝 |
| `debug` | `false` | SDK 诊断日志开关 |

不建议使用开放模式。如果确实需要：

```yaml
access:
  c2cMode: open
acknowledgeOpenAccess: true
```

开放模式会让任何能找到机器人的用户触发 DSH Agent。

## 内置命令

- `/bot-help`：查看帮助
- `/bot-status`：查看会话、模型和用量状态
- `/bot-ping`：连接测试
- `/bot-version`：查看版本
- `/bot-reset`：清除当前会话上下文
- `/bot-new`：开始新会话
- `/bot-stop`：终止当前任务
- `/model`：查看或切换模型
- `/approve CODE`：允许当前一次权限申请
- `/deny CODE`：拒绝当前一次权限申请

## 项目结构

```text
src/
├─ approval.ts          QQ 一次性审批通道
├─ commands/            斜杠命令
├─ model/               模型发现、路由和用户偏好
├─ session/             QQ peer 与 DSH Session 映射
├─ shared/              通用工具和发送辅助
├─ transport/           入站组装、出站缓冲和分片
├─ config.ts            配置 Schema
├─ security.ts          启动前安全校验
├─ setup.ts             官方扫码与私密凭据落盘
└─ index.ts             Cordis 插件入口和生命周期编排
```

详细设计见 [架构说明](docs/ARCHITECTURE.md)。

## 开发与验证

```bash
pnpm install --frozen-lockfile
pnpm build
pnpm test
pnpm typecheck
pnpm privacy:check
pnpm check
```

`pnpm check` 会执行隐私扫描、构建、单元测试、类型检查和 npm 打包预览。

## 常见问题

- 机器人显示“未连接服务”：确认启动终端仍在运行，并检查是否出现 `Bot ready`。
- 机器人完全不回复：检查 `QQBOT_C2C_ALLOW` 是否存在且是用户 OpenID，不是机器人 AppID。
- DSH 直接 `turn/end`：显式配置 `provider` 和 `model`，并确认模型凭据可用。
- 权限申请没有出现：确认 `enableApprovals: true`、审批策略为 `ask`，且操作确实触发沙箱升级。
- 修改 `.env` 后无效：完整停止并重启 DSH。

更多排查步骤见 [故障排查](docs/TROUBLESHOOTING.md)。

## 参与贡献

提交改动前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [SECURITY.md](SECURITY.md)。安全问题请通过 GitHub Security Advisory 私下报告，不要公开提交凭据或日志。

## 作者与交流

- 作者：[wang-22-code](https://github.com/wang-22-code)
- QQ：`1722800850`

欢迎交流使用体验、问题反馈和改进建议。请勿通过公开 Issue、截图或聊天记录发送 AppSecret、API Key、OpenID 等敏感信息。

## 来源与许可

本项目派生自腾讯官方 MIT 项目 [`@tencent-connect/dsh-qqbot`](https://github.com/tencent-connect/dsh-qqbot)，由社区独立维护，并非腾讯官方产品。详见 [LICENSE](LICENSE) 和 [NOTICE](NOTICE)。
