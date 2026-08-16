# 架构说明

## 设计目标

`dsh-qqbot-safe` 是一个 Cordis 插件，将腾讯 QQ Bot WebSocket 事件转换为 DSH Agent 消息，并把 DSH Session 事件转换回 QQ 回复。设计优先级依次为：协议合规、默认拒绝、会话隔离、可诊断性和可扩展性。

## 数据流

```text
QQ Open Platform
  │ C2C / Group event
  ▼
Tencent official Node.js SDK
  │ middleware pipeline
  ├─ duplicate/self filter
  ├─ access allowlist
  ├─ approval command interception
  ├─ mention/history/sanitizer
  ├─ rate/concurrency guard
  └─ envelope formatter
  ▼
Inbound transport
  │ createUserMessage
  ▼
SessionManager ── ModelResolver
  │ followup
  ▼
DSH Agent / Session
  │ assistant/chunk, assistant/message, turn/end
  ▼
Outbound buffer and chunker
  │ official sendMarkdown API
  ▼
QQ user or group
```

## 模块职责

### 插件入口

`src/index.ts` 只负责依赖注入、SDK 中间件排序、事件注册和生命周期释放。业务逻辑应放在独立模块，避免入口继续膨胀。

### 配置与安全

- `src/config.ts`：Cordis 配置 Schema 和默认值。
- `src/security.ts`：在打开网络连接前验证工作目录、开放访问确认和白名单状态。
- `src/setup.ts`：调用腾讯官方扫码连接器，并以原子替换方式写入 `$DSH_HOME/.env`。

### 会话

`src/session/` 将 `appId + scope + peerId` 映射为确定性 SessionId。同一 QQ 用户或群会恢复到同一 DSH 会话；模型切换通过 fork 保留历史。

### 模型

`src/model/` 负责默认路由、用户覆盖、模型枚举和偏好持久化。显式 profile 配置优先于宿主默认值。

### 消息传输

- `src/transport/inbound.ts`：将正文、引用、群历史和附件描述组装成 DSH UserMessage。
- `src/transport/outbound.ts`：订阅 DSH Session 事件。
- `src/transport/outbound-buffer.ts`：合并流式文本，防止每个 token 都调用 QQ API。
- `src/transport/chunker.ts`：按 QQ 长度限制切分 Markdown。

### 权限审批

`src/approval.ts` 是 DSH `approval/request` waterfall 的 QQ answerer：

1. 只接管本插件所拥有的 Agent；
2. 生成一次性随机验证码；
3. 将工具和原因发送给原任务发起者；
4. 只接受相同 peer、相同 sender 的明确命令；
5. 返回 `allowed-once` 或非授权结果；
6. 超时、取消或卸载时失败关闭。

它不改变全局沙箱模式，也不提供永久授权。

## 信任边界

- QQ OpenID 是访问标识，不是身份认证的替代品；只信任腾讯事件中提供的 senderId。
- `.env` 与 Session 数据属于本机私密层，不属于插件源码。
- QQ 回复只能代表用户对单次审批的决定，不能提升插件自身权限。
- DSH 沙箱和审批服务是最终执行边界；插件不绕过它们。

## 扩展原则

- 新平台适配器应复用 Session/Transport 抽象，不把平台字段泄漏到 Agent 层。
- 新命令放入 `src/commands/` 并通过工厂注入依赖。
- 新的安全敏感配置必须默认拒绝，并提供显式风险确认。
- 任何日志默认不得包含正文、Secret、完整 OpenID 或附件签名 URL。
