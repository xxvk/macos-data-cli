# mpia-cli 0.9.4：公网 Demo API 与后台 Mac Runner

状态：`planned`

本文只记录未来实施计划，不代表 0.9.4 已实现、已验证或已授权部署。
当前 `VERSION` 不因本计划变更；实施、部署、提交与发布需要分别授权。

## 目标

在家庭 Mac mini 上保留一个已登录的专用 macOS 后台用户，由该用户运行
`mpia`。世界任何位置的调用方可以直接通过公网 HTTPS 和 `curl` 调用
Demo API；公网 Gateway 通过 Tailscale 私网连接家庭 Mac，不需要开放家庭
路由器端口。

```text
全球 curl
  -> 公网 HTTPS Gateway
  -> Tailscale 私网
  -> Mac mini loopback bridge
  -> mpia-runner 后台用户
  -> mpia adapters
```

0.9.4 依赖 0.9.3 的本地 REST-style CLI、route manifest、JSON Schema 和
OpenAPI 契约。0.9.3 的 `mpia METHOD /path` 仍是本地 CLI 接口，不应被误称为
已经存在的网络 HTTP server。

## 已确定的架构决策

- 公网 Gateway 采用供应商中立设计，可部署于 GCP、AWS 或普通廉价 Linux VPS。
- Gateway 终止公网 TLS，并作为 Tailnet 节点访问家庭 Mac。
- 家庭 Mac 不做端口转发，不在公网或家庭 LAN 直接暴露 Runner。
- Mac 端 Runner 只监听 loopback，再通过 Tailscale 私网发布给指定 Gateway 节点。
- Tailnet ACL 只允许 Gateway 身份访问 Runner 端口。
- 首版采用同步短请求；Gateway 等待 Runner 返回，不引入异步任务队列。
- Runner 不在线、后台用户未登录或请求超时时，返回明确的结构化错误，不自动重试写操作。

## macOS 后台用户

- 创建标准用户 `mpia-runner`，不得授予管理员权限。
- 使用一个独立的 Demo Apple Account 登录 iCloud；其中只能保存可丢弃演示数据，
  不得混入真实联系人、日历、提醒事项、邮件、消息、通话、照片或笔记。
- 由同一稳定签名与 bundle identity 的 `mpia.app` 承载 TCC 权限。
- Runner 作为 per-user LaunchAgent 启动，必须运行在该登录用户的 GUI bootstrap
  session 中；不能用 root LaunchDaemon 替代需要 TCC/Apple Events 的用户进程。
- 用户完成一次登录后，可以通过 Fast User Switching 切换到其他账户；后台资格必须
  对每个 adapter 分别实测，不能从进程仍存在推断所有 GUI/TCC 能力可用。
- 保留 FileVault。Mac 重启后需要人工首次登录；登录前 Gateway 返回
  `RUNNER_OFFLINE`，不得启用不安全的自动登录作为默认恢复方式。

## 公网 Demo 边界

公网入口按已确认决策保持匿名，不要求 API Token。该模式只适用于专用 Demo
Apple Account，不属于生产远程控制方案。

- Gateway 和 Runner 必须显式配置 `demoMode=true`；缺少该配置时拒绝启动匿名服务。
- OpenAPI、Manifest 和响应必须醒目标记 `demoOnly: true` 与匿名共享数据边界。
- 如果未来接入个人或生产数据，必须先增加鉴权和授权模型，不能复用匿名配置直接上线。
- Gateway 不记录请求或响应正文，只记录 route、状态码、耗时、字节数、脱敏 request ID
  和熔断原因。
- 日志不得包含 token、确认短语、`Idempotency-Key`、任何请求字段或正文、联系人、邮件、
  消息、电话、路径或其他用户数据。

## 完整 Manifest 与远程执行资格

完整 Manifest/OpenAPI 可以公开发现，但“可发现”不等于“可远程执行”。每条 route
需要由单一事实源生成：

```text
remoteEligible: boolean
remoteBlockedReason: string | null
remoteMethod: string | null
```

默认阻止以下类别，并返回稳定的 `REMOTE_ROUTE_BLOCKED`：

- 接受任意本机输入、输出或目录路径的 route；
- 文件导出、attachment/media export 和任意本机文件读取；
- 会激活 GUI 的 Mail reveal、Shortcut import/edit/run 等操作；
- 会主动弹出 TCC、Apple Account、管理员权限或其他授权提示的 request route；
- 依赖前台窗口、Accessibility 操作或结果无法在 30 秒内安全判定的 route；
- 无法证明只作用于 Demo 数据或无法精确恢复的操作。

Gateway 不得维护一份容易漂移的手写 allowlist。远程资格应成为 route manifest 的正式
字段，并由 OpenAPI、CLI help、Gateway 和测试共同消费。

## 写入契约

业务参数继续放在 HTTP query/body；dry-run、apply、confirmation 和幂等性属于执行控制，
通过固定 HTTP Header 传递。Gateway 不得把安全意图混入业务 JSON，也不得暴露任意 CLI
参数数组。

| 本地 CLI 安全参数 | HTTP Header | HTTP 取值 |
| --- | --- | --- |
| `--dry-run` | `Mpia-Execution-Mode` | `dry-run` |
| `--apply` | `Mpia-Execution-Mode` | `apply` |
| `--confirm "DELETE NOTE"` | `Mpia-Confirmation` | `DELETE NOTE` |
| 幂等写入 | `Idempotency-Key` | 客户端生成的唯一非敏感值 |

不使用 `Mpia-Dry-Run: true` 与 `Mpia-Apply: false` 两个布尔 Header；单一枚举避免两个
Header 同时为 true、同时为 false、重复或缺失时产生歧义。Header 名称按 HTTP 规则不区分
大小写，Header 值按 manifest 契约精确匹配。

Notes 删除预览示例：

```bash
curl -X DELETE "https://demo.mpia.dev/notes/delete?id=note_opaque_id" \
  -H "Content-Type: application/json" \
  -H "Mpia-Execution-Mode: dry-run" \
  --data '{"expectedModificationDate":"2026-08-15T09:00:00Z"}'
```

正式执行示例：

```bash
curl -X DELETE "https://demo.mpia.dev/notes/delete?id=note_opaque_id" \
  -H "Content-Type: application/json" \
  -H "Mpia-Execution-Mode: apply" \
  -H "Mpia-Confirmation: DELETE NOTE" \
  -H "Idempotency-Key: 019d-example-unique-request" \
  --data '{"expectedModificationDate":"2026-08-15T09:00:00Z"}'
```

远程写入仍必须保留本地 CLI 的全部安全条件：

- 所有 mutation route 必须显式提供一个 `Mpia-Execution-Mode`，不设置默认模式；
- `dry-run` 禁止携带 `Mpia-Confirmation` 或 `Idempotency-Key`；
- `apply` 必须携带 `Idempotency-Key`；
- manifest 声明 confirmation 的 route 在 apply 时必须精确提供 `Mpia-Confirmation`；
- 不需要 confirmation 的 route 收到 `Mpia-Confirmation` 时 fail closed；
- Header、query 和 body 中的重复字段或相互矛盾的安全意图一律拒绝；
- Gateway 与 Runner 必须绑定 method、path、规范化 query/body、执行模式、确认状态和
  idempotency key；
- 相同 key 与相同请求返回原结果；相同 key 与不同请求拒绝；
- timeout、断线或未知结果不得自动重试；
- apply 后必须执行 adapter 既有的回读验证，并原样保留
  `readback_confirmed`、`pending`、`unknown` 等状态。

Gateway 必须把经过 manifest 验证的 Header 转换为结构化 Runner 请求或独立的进程参数；
禁止拼接 shell command。确认短语与 idempotency key 不得出现在 Gateway、Runner、反向代理、
Tracing 或错误日志中。

确认短语是防误操作机制，不是身份认证。匿名 Demo 用户仍可按公开文档操作共享数据，
因此必须依赖配额、容量熔断和定期恢复控制影响范围。

## 真实 HTTP 语义门禁

0.9.3 的 METHOD/path 是本机 CLI 的语义映射；0.9.4 在提供真实 HTTP server 前必须解决
以下传输层差异，不能直接假定 CLI 语义等于标准 HTTP 行为。

### OPTIONS 与 CORS preflight

- 带 `Origin` 和 `Access-Control-Request-Method` 的 OPTIONS 请求按 CORS preflight 处理，
  不进入 mpia 业务 dispatcher；
- 不带 preflight 标识的 `OPTIONS /resources`、permission 和 discovery route 才按 mpia
  业务请求处理；
- CORS allow headers 必须明确包含 `Content-Type`、`Mpia-Execution-Mode`、
  `Mpia-Confirmation` 和 `Idempotency-Key`，并以 allowlist 限定允许的 origin；
- 浏览器 API 测试工具与普通 `curl` 都必须覆盖这两个分支。

### HEAD 标量响应

真实 HTTP HEAD 响应不得包含 JSON body。公网 HTTP projection 将本地 CLI 的 HEAD 标量
route 映射为 GET，并在 manifest/OpenAPI 中显式记录 `remoteMethod: GET`；本地 0.9.3 CLI
仍保留 HEAD，不因远程传输层改写。禁止通过带正文的 HEAD 冒充标准 HTTP。

### DELETE request body

0.9.4 首版暂时保留 DELETE 的严格 JSON body，用于 Notes 等 route 的并发 token；但必须
通过实际 Gateway、反向代理、`curl` 和浏览器 API 测试工具验证 body 未被丢弃或改写。
任一部署组件无法可靠保留 DELETE body 时，该 route 必须返回稳定的
`REMOTE_ROUTE_BLOCKED`，不得降级为缺少并发保护的删除。未来可单独评估将适合的并发 token
映射为 `If-Match`，但 0.9.4 不静默改变现有 adapter contract。

## 请求限制与熔断

首版采用已确认的宽松演示配额：

- 每个公网 IP 最多 120 请求/分钟；
- 每个公网 IP 最多 5 个并发请求；
- 单次同步请求总 deadline 为 30 秒；
- params 最大 32 KiB；
- body 最大 384 KiB；
- response 最大 4 MiB；
- 达到对象数量、磁盘、错误率或并发全局阈值时停止新的写入，只保留健康检查和恢复接口。

Gateway 必须返回结构化的 `RATE_LIMITED`、`RUNNER_OFFLINE`、`RUNNER_TIMEOUT`、
`REMOTE_ROUTE_BLOCKED` 和 `DEMO_CAPACITY_EXCEEDED`，不能用通用 500 隐藏状态。

## 共享数据与恢复

- 匿名调用方共享同一套演示数据，不提供会话级隔离。
- 建立可重复生成的 golden fixture，记录预期对象数量和非敏感内容 hash。
- 每日执行一次精确恢复；达到容量阈值时提前停止写入并触发恢复。
- 恢复只能处理带 Demo manifest 标识的对象，禁止清空整个 Contacts、Calendar、
  Reminders、Notes、Safari 或其他系统数据域。
- 恢复流程必须是 `inventory -> plan -> exact apply -> read-back`，并证明无额外残留。
- 恢复失败时保持写入熔断，等待人工检查，不能循环删除或重新创建。

## 健康与可观测性

至少区分以下状态：

- Gateway 公网进程是否健康；
- Tailnet 是否连接；
- Mac Runner 是否可达；
- `mpia-runner` 是否处于已登录用户 session；
- mpia 版本、manifest hash 和 Gateway 预期是否一致；
- 各 adapter 是否为 `available`、`permission_missing`、`background_unsupported`、
  `schema_unsupported` 或 `temporarily_unavailable`；
- Demo fixture 是否健康、漂移或达到容量阈值。

健康接口只能返回状态、版本和 hash，不得返回个人数据、路径、Apple Account 或设备标识。

## TDD 与验收

- Manifest/OpenAPI 必须完整展示全部 route，并准确标注远程执行资格。
- 从不在 Tailnet 内的设备执行 `curl`，可以访问公网健康检查、Manifest 和至少一个
  远程安全读取 route。
- 云端 Gateway 只能通过 Tailnet 访问 Runner；公网和家庭 LAN 不能直接连接 Runner。
- Fast User Switching 后逐项验证后台安全 adapter，失败能力必须降级而不是误报成功。
- 重启后、首次人工登录前返回 `RUNNER_OFFLINE`；登录后 LaunchAgent 自动恢复并回读健康。
- 所有本机路径、GUI 激活和权限请求 route 都必须稳定返回 `REMOTE_ROUTE_BLOCKED`。
- 验证 120 请求/分钟、5 并发、30 秒 deadline、请求/响应大小和全局容量熔断。
- 验证写入 dry-run、apply、确认短语、idempotency 冲突、断线未知结果和回读状态。
- 验证所有 mutation route 的安全 Header 组合矩阵，包括缺失、重复、冲突、错误确认短语、
  dry-run 携带幂等 key，以及 apply 缺少幂等 key。
- 验证 CORS preflight 不进入业务 OPTIONS dispatcher，普通业务 OPTIONS 仍可执行。
- 验证远程 HEAD projection 使用 GET 返回 JSON，真实 HEAD 不返回正文。
- 验证 DELETE body 经过公网 Gateway、反向代理和 Runner 后保持字节与语义一致。
- 验证每日 golden fixture 恢复只清理 manifest-bound Demo 对象，且恢复后计数/hash 一致。
- 检查 Gateway、Runner 和云平台日志，证明请求/响应正文与演示内容没有被持久化。
- 中英文 Roadmap、架构文档、Manifest、OpenAPI 与运行时行为保持一致。

## 非目标

- 0.9.4 不使用 macOS Container 代替真实 macOS 执行环境；Apple Containerization
  运行的是 Linux guest，不能提供 mpia 所需的 macOS Framework/TCC 数据面。
- 首版不提供多租户、OAuth/OIDC、个人生产数据、异步离线队列或可用性 SLA。
- 首版不关闭 FileVault、不默认自动登录、不开放家庭路由器端口。
- 首版不允许云端传入任意 shell、CLI 参数数组或本机文件路径。
- 本计划不授权实施、部署、创建云资源、修改 Tailnet、写入系统数据、提交或发布。
