# CLI Contract

## JSON envelope

机器可读响应使用独立于 CLI 发布版本的 `contractVersion: "0.1"`。

| 结果 | 结构 | 退出码 |
| --- | --- | ---: |
| 成功 | `{"ok":true,"contractVersion":"0.1","data":...}` | 0 |
| 未预期的 CLI 错误 | `error.code = CLI_ERROR` | 1 |
| Contacts / 权限 / 输入错误 | `error.code = CONTACTS_ERROR` | 2 |
| 联系人定位错误 | `error.code = CONTACT_QUERY_ERROR` | 3 |
| 用法或查询参数错误 | `error.code = INVALID_QUERY` | 64 |

错误写入 stderr，成功的 JSON 写入 stdout。调用方应先根据退出码分支，
再在请求 JSON 错误 envelope 时读取 `error.code` 和 `error.message`。
