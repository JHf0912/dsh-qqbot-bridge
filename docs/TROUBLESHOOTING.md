# 故障排查

## 启动检查顺序

1. 确认 Node.js `>= 22`。
2. 确认 DSH 进程保持运行。
3. 确认终端出现 `Bot ready!`。
4. 确认 `$DSH_HOME/.env` 中四个键存在且非空：`QQBOT_APPID`、`QQBOT_SECRET`、`QQBOT_C2C_ALLOW`、模型 API Key。
5. 确认 profile 的 `provider/model` 可用。

不要把这些值粘贴到 Issue。可以只报告键是否存在、值长度和错误码。

## 私聊没有回复

- `c2cAllow` 必须包含用户 OpenID，不是个人 QQ 号，也不是机器人 AppID。
- `${c2cAllow}` 是普通字符串，不会自动插值。使用 README 中的 `!!js process.env...`。
- 修改 `.env` 后完整重启 DSH。
- 临时设置 `debug: true`，发送一条新消息并观察 `C2C_MESSAGE_CREATE`。排查完恢复 `false`。

## 显示“机器人未连接服务”

说明腾讯没有检测到在线 WebSocket：

- 检查终端是否出现 `invalid appid or secret`；如有，重新进行官方扫码绑定或在开放平台重置 Secret。
- 检查代理、防火墙是否允许访问 `bots.qq.com`、`api.sgroup.qq.com` 和 WebSocket。
- 不要同时运行多个使用相同 AppID 的测试实例。

## 收到消息但立即结束

如果 Session 中出现 `has no provider/model`，在 profile 显式配置：

```yaml
provider: deepseek-official
model: deepseek-v4-flash
```

如果模型接口报鉴权错误，检查模型 API Key，但不要公开输出它。

## 权限审批不可用

- profile 需要 `enableApprovals: true`。
- DSH approval policy 必须为 `ask`，`never` 会直接拒绝。
- 审批命令必须带当前验证码，例如 `/approve A1B2C3`。
- 只有任务发起者可以批准；验证码过期后必须重新触发操作。

## 安全地提供日志

可以提供：

- 事件类型、HTTP 状态码和错误码；
- Node/DSH/插件版本；
- 已打码的 AppID；
- 是否出现 `READY`、`C2C_MESSAGE_CREATE`、`assistant/message`。

必须删除：Secret、API Key、OpenID、msg_id、二维码 URL、聊天正文、文件签名 URL。
