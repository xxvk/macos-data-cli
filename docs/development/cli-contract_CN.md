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
| 用法或查询参数错误 | `error.code = INVALID_QUERY` | 64 |

错误写入 stderr，成功的 JSON 写入 stdout。调用方应先根据退出码分支，
再在请求 JSON 错误 envelope 时读取 `error.code` 和 `error.message`。
