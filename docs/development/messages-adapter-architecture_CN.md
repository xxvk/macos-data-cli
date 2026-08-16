# Messages 适配器架构决策（0.9.1）

## 决策

0.9.1 交付一个**只读**的 `messages` 适配器，数据源为本机 Messages 的 SQLite 库
`~/Library/Messages/chat.db`，沿用 Mail 0.2 已验证的 fail-closed 快速路径模式。
读取消息历史没有公开框架可用；适配器只读一个「运行时校验过 schema 指纹、immutable
连接」的 SQLite 视图，返回 metadata + 有界、脱敏后的正文投影。

## 为什么是 0.9.1 的方向

- **没有公开读取 API。** `Messages.app` 的脚本字典只暴露 `send` / `login` /
  `logout` 和 `account` / `chat` / `participant` / `file transfer` 类，**没有
  `message` 类**，所以 Apple Events 只能发消息、读不了历史。
- **`chat.db` 是唯一读取路径。** 它是众所周知、结构清晰的 SQLite 库（`message` /
  `chat` / `handle` / `attachment` 及关联表），schema 可按 macOS 版本做指纹，
  且有大量开源工具和取证资料可参考。
- **复用 Mail 的架构。** Mail 0.2 已经建立了 roadmap 要求的门禁：Full Disk
  Access、运行时 schema 指纹、immutable 只读连接、有界查询、deadline、fail-closed。
  Messages 直接继承这套模式，不必另起炉灶。

## 基线与本机观测到的 schema（macOS 27）

已在 macOS 27.0（`26A5406e`）上以只读方式打开 `chat.db` 确认：

- `message` — `text`（纯文本正文）、`attributedBody`（BLOB 富文本）、`date`
  （Apple epoch 秒）、`is_from_me`、`handle_id`、`service`、`account`、
  `is_read`、`is_delivered` 及大量标记列。
- `chat` — `chat_identifier`、`display_name`、`room_name`、`service_name`、
  `account_login`、`is_archived` 等分组元数据。
- `handle` — 参与者标识（电话/邮箱），经 `chat_handle_join` 和
  `message.handle_id` 关联。
- `attachment` / `message_attachment_join` — 附件记录（0.9.1 不涉及，最多只给
  计数，绝不返回路径或字节）。

读取器绝不能假设该 schema 永远不变；必须像 Mail 的 `V10` 门禁一样，在运行时探测
并校验一个有界的 schema 指纹，不匹配即 fail-closed。

## 命令面（0.9.1）

- `mpia OPTIONS "/messages/permission"` — 状态只读探测：报告 Full Disk Access 与 `chat.db`
  可读性，不弹窗。
- `mpia GET "/messages/recent" --params '{"limit":20,"cursor":"<opaque-cursor>","service":"imessage"}'`
  — 只读「近期消息」，最新在前，游标分页。每条返回：不透明本地 ID、`service`、
  `isFromMe`、时间、会话 ID、以及有界脱敏后的正文投影。
- 仅只读：不做发消息/回复、已读回执、反应、附件导出、会话删除或任何写入。

## 契约（metadata-first，有界正文投影）

```json
{
  "ok": true,
  "contractVersion": "0.1",
  "data": {
    "items": [
      {
        "id": "msg_8f2c4e",
        "service": "iMessage",
        "isFromMe": false,
        "sentAt": "2026-08-14T09:12:00Z",
        "conversationId": "chat_5d8e2a",
        "text": "投影后的正文，默认截断到 500 字符"
      }
    ],
    "nextCursor": "cursor_8f2c4e",
    "complete": true,
    "truncated": false,
    "limitations": ["body projected and truncated to 500 chars"]
  }
}
```

投影与脱敏规则（不可妥协）：

- 正文是**投影**，默认只读纯文本 `text` 列；更丰富的 `attributedBody` BLOB 只在
  未来明确增加投影开关时才解析，0.9.1 不暴露它。
- 正文截断到硬上限（默认 500 字符），命中即标记 `truncated`。
- 参与者 handle、原始本地库 ID、账号标识、附件路径**默认一律不返回**；跨契约只
  暴露不透明 item ID 和不透明会话 ID。
- live smoke 输出只含聚合（计数、截断、完整性），绝不打印消息正文、handle 或标识。

## TCC 与授权

- 读 `chat.db` 要求 responsible process 具备 Full Disk Access。开发期用签名 app
  bundle（`.build/debug/mpia.app`），发布期用发布 bundle，均需授权 Full Disk
  Access。
- `OPTIONS /messages/permission` 是状态查询，不弹窗，也不接受主动请求授权的参数。

## 组件设计

- `MessagesStoreLocator` — 解析 `~/Library/Messages/chat.db`，拒绝符号链接和
  超大/不安全文件，报告发现状态。
- `MessagesPermissionProbe` — 不弹窗地检查 Full Disk Access 与库可读性。
- `ChatDbReader` — 打开 immutable 只读 SQLite 连接，校验 schema 指纹，执行带
  deadline 的有界 `recent` 查询。
- `MessagesMapper` — 把行映射到契约，应用不透明 ID、正文投影/截断与脱敏。
- `MessagesPagination` — 基于 (`date`, 不透明 ID) 的游标；游标绑定精确的
  `chat.db` 指纹，库变化即失效（stale）。

## 稳定数据与隐私规则

- 把消息 ID、会话 ID、handle ID、游标当作不透明适配器值。
- 绝不暴露原始 `ROWID`、`guid`、`chat_identifier`、电话号码或邮箱。
- 诊断日志绝不打印正文、handle 或标识。
- 游标过期或 schema 未知即 fail-closed，绝不自动重试。

## 测试与兼容门禁

- 单元测试只用合成 SQLite fixture（手工构造的 `chat.db` schema），绝不读真实
  Messages 数据。
- 隐私最小化的 live smoke（`scripts/run_messages_read_smoke.sh`）只打印聚合计数
  与截断状态；Full Disk Access 不可用时必须停止、不发起查询。
- 每个新的 macOS 版本都要重新探测 schema 指纹；不匹配即禁用快速路径，绝不猜测。

## 交付顺序

1. 架构决策（本文）+ 中文摘要。
2. `MessagesStoreLocator` + `MessagesPermissionProbe`。
3. `ChatDbReader`（schema 指纹 + 有界 `recent` 查询）。
4. `MessagesMapper` + 分页 + 注册表接线。
5. 合成 fixture 单元测试。
6. live smoke（仅聚合）+ `messages permission` 验证。
7. README / usage / OpenAPI 重新生成。

## 0.9.1 明确不做

- 发消息、回复、反应、已读回执、附件导出、以及任何写入。
- 跨正文全文搜索；群会话参与者解析；iCloud 同步；跨设备保证。
- `attributedBody` 富文本投影（只在未来单独加明确门禁的开关后再评估）。
