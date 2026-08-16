# 使用说明

从 0.9.3 开始，`mpia` 只接受 REST 风格 CLI。旧 adapter/subcommand 语法已删除。

```bash
mpia METHOD "/path" \
  --params '{"selector":"value"}' \
  --body '{"field":"value"}' \
  --dry-run|--apply \
  --confirm "EXACT PHRASE"
```

只有 `mpia --help`、`mpia --version` 和 `mpia -v` 不使用 METHOD/PATH。METHOD
不区分大小写；公开文档统一显示大写。结果始终是 JSON，不再接受 `--format`、
`--input` 或 `--stdin`。

## 输入规则

- `--params` 可省略，默认 `{}`；严格内联 JSON object，最多 32 KiB。
- `--body` 仅用于声明了 input schema 的 route；严格内联 JSON object，最多 384 KiB。
- 未知字段、重复字段、类型错误和缺少必填字段均 fail closed。
- `--dry-run`、`--apply`、`--confirm` 是独立 flag，不能放进 JSON 自我授权。
- 文件仍以路径放入 params；不得把图片、附件或 Shortcut 文件编码进 body。
- 内联 JSON 可能进入 shell history 或进程参数，不得承载密码、API key 或其他秘密。

## Agent 与资源发现

```bash
mpia GET "/agent/help"
mpia GET "/agent/manifest"
mpia HEAD "/agent/version"
mpia OPTIONS "/resources"
```

`GET /agent/manifest` 是 method、path、params、body schema、安全约束、输出 schema
和退出码的运行时唯一公开真相源。完整 route 与 model 见
[在线文档](https://mpia-cli-doc.vercel.app/)。

## 通讯录

```bash
mpia OPTIONS "/contacts/permission"
mpia OPTIONS "/contacts/containers"
mpia HEAD "/contacts/container"
mpia HEAD "/contacts/count"
mpia GET "/contacts/query" --params '{"name":"Ada","limit":20}'
mpia GET "/contacts/get" --params '{"external-id":"person-001"}'
mpia POST "/contacts/create" --body '{"kind":"person","externalID":"person-001","givenName":"Ada"}' --dry-run
mpia PATCH "/contacts/edit" --params '{"external-id":"person-001"}' --body '{"jobTitle":"Engineer"}' --dry-run
mpia PATCH "/contacts/avatar/edit" --params '{"external-id":"person-001","image":"/tmp/avatar.png"}' --dry-run
mpia DELETE "/contacts/delete" --params '{"external-id":"person-001"}' --apply --confirm "DELETE CONTACT"
```

Contacts 默认选择唯一验证的 iCloud 容器，也可用 `container` param 显式指定。
创建必须包含 external ID；普通编辑不能修改它。

## Calendar 与 Reminders

```bash
mpia OPTIONS "/calendar/sources"
mpia GET "/calendar/query" --params '{"start":"2026-08-16T00:00:00Z","end":"2026-08-17T00:00:00Z"}'
mpia POST "/calendar/create" --body '{"title":"Review","startDate":"2026-08-16T09:00:00+09:00","endDate":"2026-08-16T10:00:00+09:00"}' --dry-run
mpia OPTIONS "/reminders/sources"
mpia GET "/reminders/query" --params '{"status":"incomplete","limit":20}'
mpia POST "/reminders/create" --body '{"title":"Follow up"}' --dry-run
mpia PATCH "/reminders/edit" --params '{"id":"reminder_opaque"}' --body '{"title":"Follow up today"}' --dry-run
```

两者默认只使用唯一验证的 iCloud CalDAV source；可通过 `source` param 显式选择。

## Notes

```bash
mpia OPTIONS "/notes/permission"
mpia GET "/notes/accounts"
mpia GET "/notes/query" --params '{"limit":20}'
mpia POST "/notes/create" --body '{"folderID":"notesfolder_opaque","title":"Title","bodyFormat":"plaintext","body":"Body"}' --dry-run
mpia PUT "/notes/edit-body" --params '{"id":"note_opaque"}' --body '{"bodyFormat":"plaintext","body":"Replacement","expectedModificationDate":"2026-08-14T00:00:00Z","expectedBodySHA256":"<sha256>"}' --dry-run
```

Notes 写入仍受 iCloud write-account 绑定、非共享/非锁定对象、乐观并发 token 与回读验证保护。

## Mail、Messages 与 Phone Calls

```bash
mpia OPTIONS "/mail/doctor"
mpia GET "/mail/query" --params '{"unread":true,"limit":20}'
mpia GET "/mail/get" --params '{"id":"msg_opaque","content":"text"}'
mpia OPTIONS "/messages/permission"
mpia GET "/messages/recent" --params '{"limit":20,"service":"imessage"}'
mpia OPTIONS "/phone-calls/permission"
mpia GET "/phone-calls/recent" --params '{"limit":20}'
```

三个通信 adapter 都是只读。Messages 与 Phone Calls 需要 Full Disk Access。

## Photos、Safari 与 Shortcuts

```bash
mpia GET "/photos/query" --params '{"start":"2026-08-01T00:00:00Z","end":"2026-08-16T00:00:00Z","limit":20}'
mpia POST "/photos/export" --params '{"id":"photo_opaque","output":"/tmp/photo.jpeg"}'
mpia GET "/safari/bookmarks/list" --params '{"limit":50}'
mpia POST "/safari/reading-list/add" --body '{"url":"https://example.com","title":"Example"}' --dry-run
mpia GET "/shortcuts/list" --params '{"limit":50}'
mpia POST "/shortcuts/run" --params '{"id":"shortcut_opaque","input-path":["/tmp/input.txt"]}' --apply --confirm "RUN SHORTCUT"
mpia POST "/shortcuts/author/validate" --params '{"source":"./managed.cherri"}'
```

Photos 与 Shortcut bytes 仅通过文件路径传递。Safari 直接 bookmark/folder 写入只保证
`local_only`，不能宣称触发 iCloud 同步。

## 错误与迁移

旧语法返回 `LEGACY_SYNTAX_REMOVED`、退出码 64 和对应 REST route 的 `nextAction`，
不会继续执行。方法不匹配返回 `METHOD_NOT_ALLOWED` 并列出允许方法；未知 path 返回
`ROUTE_NOT_FOUND`。调用方应先判断进程退出码，再读取 JSON `error.code`。
