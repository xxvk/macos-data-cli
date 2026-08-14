# CLI Contract

## JSON envelope

机器可读响应使用独立于 CLI 发布版本的 `contractVersion: "0.1"`。

| 结果 | 结构 | 退出码 |
| --- | --- | ---: |
| 成功 | `{"ok":true,"contractVersion":"0.1","data":...}` | 0 |
| 未预期的 CLI 错误 | `error.code = CLI_ERROR` | 1 |
| Contacts / 权限 / 输入错误 | `error.code = CONTACTS_ERROR` | 2 |
| 联系人定位错误 | `error.code = CONTACT_QUERY_ERROR` | 3 |
| Mail adapter 通用错误 | `error.code = MAIL_ERROR` | 4 |
| Mail 需要 Full Disk Access | `MAIL_FULL_DISK_ACCESS_REQUIRED` | 4 |
| Mail schema 不支持 | `MAIL_SCHEMA_UNSUPPORTED` | 4 |
| Mail Automation 被拒绝 | `MAIL_AUTOMATION_DENIED` | 4 |
| Mail.app 未运行 | `MAIL_APP_NOT_RUNNING` | 4 |
| Mail.app event 超时 | `MAIL_APP_TIMEOUT` | 4 |
| Mail.app 消息未找到 | `MAIL_APP_MESSAGE_NOT_FOUND` | 4 |
| Mail.app 超时熔断已打开 | `MAIL_APP_CIRCUIT_OPEN` | 4 |
| Calendar adapter 错误 | `CALENDAR_ERROR` 或 `CALENDAR_*` | 5 |
| Calendar 未授权 full access | `CALENDAR_PERMISSION_REQUIRED` / `CALENDAR_FULL_ACCESS_REQUIRED` | 5 |
| Calendar iCloud source 缺失或歧义 | `CALENDAR_ICLOUD_SOURCE_NOT_FOUND` / `CALENDAR_SOURCE_AMBIGUOUS` | 5 |
| Calendar/event 未找到 | `CALENDAR_NOT_FOUND` / `CALENDAR_EVENT_NOT_FOUND` | 5 |
| Calendar JSON、日期范围或周期 scope 无效 | `CALENDAR_INVALID_INPUT` / `CALENDAR_INVALID_DATE_RANGE` / `CALENDAR_RECURRING_SPAN_REQUIRED` | 5 |
| Calendar 幂等创建内容不一致 | `CALENDAR_IDEMPOTENCY_CONFLICT` | 5 |
| Calendar 冲突扫描范围过大 | `CALENDAR_CONFLICT_SCAN_LIMIT_EXCEEDED` | 5 |
| Safari adapter、权限、schema 或 mutation 错误 | `SAFARI_*` | 10 |
| 用法或查询参数错误 | `error.code = INVALID_QUERY` | 64 |

错误写入 stderr，成功的 JSON 写入 stdout。调用方应先根据退出码分支，
再在请求 JSON 错误 envelope 时读取 `error.code` 和 `error.message`。

Mail 调用方还必须按 `data.backend` 分支。SQLite message/mailbox ID 与 Mail.app
fallback 的 `appmsg_`/`ambx_` ID 是 backend-specific opaque 值。fallback query
始终返回 `incomplete: true`、`nextCursor: null` 和有限候选范围的 limitations；无匹配
响应不能解释为完整 mailbox 搜索。

Calendar 成功响应沿用 contract `0.1` envelope。普通事件 Date 使用 ISO 8601；全天事件
start/end 使用 `YYYY-MM-DD`。
Calendar query 返回统一 `items`、`limit`、`nextCursor`、`truncated`、`complete`。
`calevent_`、source、calendar 和 cursor 都是本机 opaque 值；调用方不得解析。
移动事件后返回的新 `calevent_` ID取代旧 ID。周期事件 edit/delete 必须显式提供
`--span this` 或 `--span future`。

Safari bookmark 与 Reading List ID 都是本机 opaque 值。query cursor 绑定完整
`Bookmarks.plist` fingerprint；snapshot 发生任何变化后必须返回 stale cursor 错误。
Reading List add 不回显 URL、title 或 preview。pending/unknown 结果必须包含
`nextAction`，Agent 不得自动重试。
