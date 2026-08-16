# mpia-cli 0.9.6：Messages 功能扩充

状态：`planned`

本文只记录未来实施计划，不代表 0.9.6 已实现、已验证或已授权发布。
当前 `VERSION` 不因本计划变更；实施、版本提升、提交、tag、push 与发布需要分别授权。

0.9.6 依赖稳定完成的 0.9.5 原生授权宿主和 GUI。Phone Calls 的后续扩充见
[Phone Calls 0.9.7 计划](phone-calls-expansion-0.9.7_CN.md)。

## 目标

将 Messages 从只有 `permission + recent` 的最小只读 adapter，扩展为可查询会话、
搜索消息、检查未读和附件 metadata、解析联系人，并可通过官方 Messages Apple Events
受控发送纯文本的完整本机数据面。

交付范围同时覆盖：

- REST-style CLI
- Manifest 和 JSON Schema
- OpenAPI 与三语文档
- 0.9.5 SwiftUI GUI 的生成式 route 页面
- Messages 领域化会话与发送界面

## 共享身份与隐私契约

0.9.6 建立可由 0.9.7 复用的 `CommunicationIdentityProjection`：

```text
counterpartyId
contactId?
displayName?
maskedHandle
handleKind
matchStatus: matched | ambiguous | unavailable
```

- 联系人解析使用公开 `CNContactStore`；缺少 Contacts 权限时自动降级为遮罩身份。
- 原始电话号码和邮箱只在进程内短暂使用，不进入 JSON、日志、历史或 state。
- `counterpartyId` 使用机器本地 `0600` 密钥和 HMAC 生成，不保证跨机一致。
- 邮箱严格小写、去首尾空白后匹配。
- 电话号码只做保守标准化；不使用末尾 7 位等模糊猜测。
- 多个联系人匹配同一 handle 时返回 `ambiguous`，不得猜测姓名。
- Contacts limited access 只能解析用户授权给 mpia 的联系人。
- 所有 cursor 绑定 schema fingerprint、筛选条件和排序；漂移后 fail-closed。

## Public Routes

保留并增强：

```text
OPTIONS /messages/permission
GET     /messages/recent
```

新增：

```text
GET  /messages/conversations
GET  /messages/conversation
GET  /messages/conversation/messages
GET  /messages/message
GET  /messages/search
GET  /messages/unread
GET  /messages/attachments
GET  /messages/recipient-options
POST /messages/send
GET  /messages/send-status
```

`OPTIONS /messages/permission` 除 Full Disk Access 和 schema 状态外，还需报告：

- Contacts authorization
- Messages Automation authorization
- basic read capability
- conversation capability
- attachment metadata capability
- reaction/reply capability
- text send capability

高级字段采用按功能分级的 capability gate；单个高级字段缺失不得连带禁用基础读取。

## Read Contracts

### Conversations

`GET /messages/conversations` 返回：

- opaque conversation ID
- 联系人或群组显示标题
- service
- participant count
- unread count
- last message timestamp
- 有界 last-message preview
- attachment presence
- archived / filtered 状态

`GET /messages/conversation` 返回会话 metadata 和参与者身份投影，不返回 raw handle、
账号或数据库 ID。

### Messages

`GET /messages/conversation/messages` 提供按会话分页的时间线；
`GET /messages/message` 提供单条消息详情。消息投影包括：

- opaque message/conversation ID
- service、方向与发送时间
- subject 与最多 500 字符正文
- sent / delivered / read / failed 状态
- edited / retracted 时间
- reply-to opaque message ID
- Tapback/reaction 汇总
- attachment count
- audio/system message 标记

`attributedBody` 只允许：

- 严格的 Foundation class allowlist
- 有界 BLOB 大小
- 安全 unarchive
- 失败时正文保持空值并报告 limitation

不得用通用、不受限反序列化处理数据库 BLOB。

### Search and unread

`GET /messages/search` 支持：

- query
- conversationId / contactId
- from / to
- service
- incoming / outgoing
- unread
- hasAttachments
- limit / cursor

默认搜索最近 90 天；全历史必须显式 `scope=all`。query 至少为 2 个 Unicode scalar，
单页最多 200 条。SQLite progress handler 必须真正限制扫描 deadline；超时返回稳定错误，
不得输出不一致的部分分页。

`GET /messages/unread` 按会话聚合未读数量、最新时间和有界预览。

### Attachment metadata

`GET /messages/attachments` 只返回：

- opaque attachment ID
- 文件名
- MIME type / UTI
- total bytes
- incoming / outgoing
- transfer state
- sticker 状态
- local availability

不返回原始路径、不导出文件、不读取附件内容、不触发 iCloud 下载。路径仍需在 adapter
内部完成规范化、根目录和 symlink 检查，诊断日志不得输出文件名或路径。

## Text Sending Contract

发送目标只能是：

```text
opaque conversationId
或
Contacts opaque contactId + recipientEndpointId
```

`GET /messages/recipient-options` 根据 contact ID 返回短期 endpoint：

```text
endpointId
label
kind
maskedValue
iMessageAvailable
expiresAt
```

不允许在 CLI 请求中直接传电话号码或邮箱。

发送 body：

```json
{
  "conversationId": "chat_...",
  "text": "message",
  "deliveryPolicy": "imessage_only",
  "idempotencyKey": "..."
}
```

也可用 `recipientEndpointId` 替代 `conversationId`，二者必须且只能提供一个。

执行流程：

```text
dry-run
-> 遮罩目标、渠道、字符数和费用警告
-> 精确确认
-> Apple Event send
-> chat.db 有界回读
-> operation status
```

安全要求：

- 默认 `imessage_only`，禁止静默降级成 SMS。
- SMS 必须显式 `allow_sms`，并再次确认 `SEND SMS` 和可能产生的运营商费用。
- iMessage 确认短语为 `SEND MESSAGE`。
- apply 必须提供 `idempotencyKey`；相同 key 和相同请求不得重复发送。
- Apple Event 使用结构化 descriptor，绝不把消息正文插入脚本源码。
- idempotency ledger 只保存请求 HMAC、operation ID 和状态，不保存正文或目标。
- 回读状态区分 `accepted`、`observed`、`sent`、`delivered`、`read`、`failed`、
  `unknown`。
- timeout 或 unknown 不得自动重发。

`GET /messages/send-status` 只接受 opaque operation ID，不回显正文或 raw target。

## SwiftUI GUI

Messages 领域页提供：

- 会话侧栏和未读 badge
- 消息时间线
- 搜索与日期、服务筛选
- 回复、编辑、撤回和 reaction 的只读展示
- attachment metadata chip
- 文本 Compose sheet
- dry-run、确认、发送和状态回读

全部新增 route 必须同时具有 Manifest 生成的基础表单；领域化界面不能成为第二份
命令或安全契约。

## 明确不做

- 不发送附件。
- 不删除、编辑或撤回消息。
- 不直接写 `chat.db`。
- 不自动回复、不创建群聊、不发送 scheduled message。
- 不标记已读、不执行 Tapback。
- 不允许输入或输出 raw 电话号码和邮箱。
- 0.9.6 route 不自动加入 0.9.4 公网 Demo allowlist。

## TDD 与验收

- 合成 `chat.db` 覆盖一对一、群聊、SMS、iMessage、未读、附件、回复、编辑、撤回和
  reactions。
- 覆盖 unsafe attributed archive、超大 BLOB、损坏 attachment 和 dataless 文件。
- 覆盖搜索时间范围、分页、deadline、中文/日文查询和 cursor 漂移。
- 覆盖 Contacts denied、limited、ambiguous 和 store change。
- fake Apple Event backend 覆盖发送、SMS 禁止、确认短语、idempotency 和 unknown。
- Live send 只能使用 Private 配置中的专用测试联系人，并需当前任务明确授权。
- SMS 实测需要独立确认费用；未完成 live acceptance 前不得宣称 SMS 已验证。
- live smoke 只输出聚合结果，不输出正文、联系人、文件名或 handle。
- 新 route 全部进入 Manifest、OpenAPI、CLI help、三语文档和 SwiftUI GUI。
- 完整 Swift tests、CLI contracts、GUI tests、schema generation、Release build 和
  `git diff --check` 必须通过。

## 版本完成条件

- 0.9.5 已稳定完成，SwiftUI App 是权限和执行宿主。
- 现有 `recent` contract 保持兼容；新增字段只能是兼容性 optional 字段。
- Messages 领域页和全部新增 GUI route 已完成真实本机验收。
- `VERSION` 只在所有门禁通过后提升为 0.9.6。
- commit、tag、push、Release 与 Homebrew 更新分别授权。

