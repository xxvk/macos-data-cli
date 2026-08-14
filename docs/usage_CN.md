# 使用说明

`macos-data` 是一个本地 Terminal CLI。它使用 Apple 公共 Framework 和明确公开的 App
Automation 接口访问 macOS 数据，Agent 不需要专用集成即可调用。

## 统一资源查询

使用一个机器可读响应查看当前可发现的 Contacts、Mail、Calendar、Reminders、Photos 和 Notes 资源作用域：

```text
macos-data resources --format json
```

每个资源返回 adapter 管理的 opaque `id`、`kind`、`provider`、`displayName`，以及
`readable`、`writable`、`selected`、`permission` 能力状态。Contacts 的 selected 状态
反映已经验证的 iCloud 容器。Mail 不会因为“存在一个账号”就擅自标记为 selected；
偏好的 `aim-tech.jp` 工作邮箱仍需要隐私安全的显式验证。Calendar 在获得 full access 后
返回 EventKit source；selected 只会标记唯一验证通过的 iCloud CalDAV source。Reminders
采用相同的 fail-closed iCloud source 策略，并使用独立的 `remindersSource` kind。
Photos 始终报告一个 `photosLibrary` scope；未授权时不可读，limited 时 permission 为
`limited`，可读但不代表完整照片库。
Notes 始终报告一个只读 `notesLibrary` scope；permission 表示负责执行进程对 Notes.app 的
Automation 状态，不代表可以访问 Notes 私有数据库。

## Notes（0.6 只读开发切片）

不触发弹窗地检查 Notes.app Automation 状态：

```text
macos-data notes permission --format json
```

只有显式命令可以请求 macOS 授权：

```text
macos-data notes permission --request --format json
```

响应包含 `access`、`readable`、`complete` 和 `requested`。access 可能为 `available`、
`denied`、`requiresConsent`、`targetNotRunning`、`targetUnavailable` 或 `unknown`。

只读发现有界 account 与嵌套 folder 结构，不读取 note 标题或正文：

```text
macos-data notes accounts --format json
macos-data notes folders [--account-id <opaque-id>] [--parent-id <opaque-id>] \
  [--limit <1...200>] [--cursor <opaque-cursor>] --format json
```

account/folder ID 由 SHA-256 生成并由 adapter 管理，不返回 Notes 原始 scripting ID。folder
cursor 与 account/parent filter 绑定，跨 filter 或 stale cursor 会 fail closed。

只读查询有界 note metadata，不读取正文：

```text
macos-data notes query [--account-id <opaque-id>] [--folder-id <opaque-id>] \
  [--title <substring>] [--modified-after <iso8601>] \
  [--limit <1...200>] [--cursor <opaque-cursor>] --format json
```

结果只包含 adapter-owned note/account/folder ID、标题、创建/修改时间以及
password-protected/shared 标志；不包含 plaintext、HTML、attachment 或 Notes 原始 scripting ID。
query cursor 与全部 filter 绑定，换 filter 复用时会 fail closed。枚举上限为 32 个 account、
200 个 folder、200 条 note、16 层以及 5 秒 Apple Events deadline；CLI 启动总耗时可能更长。
`complete: false` 表示有界快照无法证明已检查全部匹配 note。adapter 通过 Apple Events 使用
Notes.app scripting dictionary，绝不读取 Notes 私有 store 或 CloudKit container。参阅
[Notes 0.6 可行性决策](development/notes-adapter-feasibility_CN.md)。

读取一条已选择的 note；默认只返回 metadata，不获取正文：

```text
macos-data notes get --id <opaque-note-id> --format json
macos-data notes get --id <opaque-note-id> --body plaintext --format json
macos-data notes get --id <opaque-note-id> --body html --format json
macos-data notes get --id <opaque-note-id> --include-attachments --format json
```

`plaintext` 和 `html` 是对敏感正文的显式 opt-in。返回的 UTF-8 正文上限为 256 KiB；超过上限
或 password-protected note 均 fail closed。单条 Apple Event 有 deadline，但 Notes 会先提供完整
property，CLI 随后才能执行 UTF-8 输出上限，因此这是输出边界，不是 Apple Events 峰值内存的
严格保证。诊断日志绝不记录正文内容。

attachment metadata 同样需要显式 opt-in。每条 note 最多返回 100 个 adapter-owned opaque
attachment ID，以及名称、创建/修改时间、content identifier、URL 和 shared 状态；绝不读取
attachment `contents`，也不执行 save 或 binary export。`attachmentsComplete: false` 表示达到
单 note 上限。binary export 继续延后，必须另行定义目标文件、byte 上限、禁止覆盖和清理 gate。

## Photos（0.5 开发切片）

不触发弹窗地读取当前权限：

```text
macos-data photos permission --format json
```

显式请求 Photos read/write 权限：

```text
macos-data photos permission --request --format json
```

响应包含 `access`、`readable`、`complete` 和 `requested`。`limited` 表示
`readable: true`、`complete: false`。授权后可以枚举 album metadata：

```text
macos-data photos albums --kind all --limit 50 --format json
macos-data photos albums --kind user --limit 50 --cursor <opaque-cursor> --format json
```

结果保留用户 folder 层级、区分 user/smart album，并允许 title 重名；后续选择必须使用 opaque
album ID。按 creation date 查询有界 asset metadata；默认排除 hidden asset 和精确位置：

```text
macos-data photos query --start 2026-08-01T00:00:00Z --end 2026-08-15T00:00:00Z \
  [--album-id <opaque-album-id>] [--media image|video|audio|unknown] \
  [--favorite true|false] [--include-hidden] [--include-location] \
  [--limit <1...200>] [--cursor <opaque-cursor>] --format json
macos-data photos get --id <opaque-asset-id> [--include-location] --format json
```

时间范围必须有序且不超过 366 天。query/get 只返回 metadata 和 opaque reference，
不调用媒体 manager，也不会触发 iCloud 媒体下载；本阶段 `contentAvailability` 固定为
`unknown`。

将一个显式资源导出到新的本地文件：

```text
macos-data photos export --id <opaque-asset-id> --output <file> \
  [--variant original|current|paired-video|adjustment-data] \
  [--allow-network] --format json
```

默认 variant 为 `original`，禁止网络且禁止覆盖。资源仅在 iCloud 时，默认返回
`PHOTOS_CONTENT_NOT_LOCAL`，不留下残片；`--allow-network` 才代表显式下载同意。同一优先级
存在多个资源时拒绝猜测。成功输出先在目标目录旁建立私有临时文件，再原子移动，并设置为
`0600`。JSON 只返回 opaque asset ID、variant、resource kind、content type、byte count 和
networkAllowed，不包含媒体 byte，也不回显输出路径。照片库修改尚未实现。参阅
[Photos 0.5 架构](development/photos-adapter-architecture_CN.md)。

本机 Debug、Xcode 工具链和 Contacts 授权流程请先阅读[本机 Debug 与 Contacts 授权](development/local-debug-and-tcc_CN.md)。

## Calendar（0.3）

请求读取和写入所需的 EventKit full access：

```text
macos-data calendar permission --format json
```

`writeOnly` 不能读取日历，因此不会被 CLI 当作成功。列出 source 和选中 iCloud source
内的日历：

```text
macos-data calendar sources --format json
macos-data calendar calendars --format json
```

默认必须找到唯一的 iCloud CalDAV source。可以添加 `--source iCloud` 或准确 identifier，
但不能用它切换到 Local、Exchange、Google 或其他账户。

按明确时间窗查询事件：

```text
macos-data calendar query \
  --start 2026-08-01T00:00:00+09:00 \
  --end 2026-09-01T00:00:00+09:00 \
  --limit 50 --format json
macos-data calendar query --start <iso8601> --end <iso8601> \
  --calendar <id|unique-title> --title <text> --format json
macos-data calendar conflicts --start <iso8601> --end <iso8601> \
  [--calendar <id|unique-title>] --format json
```

查询范围必须满足 start < end，最长 366 天；默认 limit 50、最大 200，并使用统一的
opaque cursor 分页。结果包含标题、开始/结束、all-day、IANA `timeZone`、地点、备注、
URL、参与者状态、availability、event status 和周期规则。

使用 query 返回的 `calevent_` opaque ID读取事件：

```text
macos-data calendar get --id <calevent-id> --format json
```

该 ID 同时定位周期系列和 occurrence start；不得解析。移动事件后应使用返回的新 ID。

创建前先 dry-run：

```json
{
  "title": "Planning",
  "startDate": "2026-08-16T09:00:00+09:00",
  "endDate": "2026-08-16T10:00:00+09:00",
  "timeZone": "Asia/Tokyo"
}
```

```text
macos-data calendar create --input event.json --dry-run --format json
macos-data calendar create --input event.json --apply --format json
macos-data calendar create --input event.json --apply --idempotent --format json
macos-data calendar edit --id <id> --input patch.json --dry-run --format json
macos-data calendar edit --id <id> --input patch.json --apply --format json
```

存在多个可写 iCloud 日历且系统默认日历不属于所选 source 时，在 create JSON 中明确
提供 `calendarID`。参与者只读；输入非空 `attendees` 会报错，不会假装已发送邀请。

Alarm 使用 `alarms` 数组。每项必须且只能提供 `relativeMinutes` 或 `absoluteDate`；负数表示
事件开始前，例如 `-10`。编辑时传 `"alarms": []` 会清空全部提醒。创建逻辑会先移除
EventKit 从目标日历继承的默认 alarm，再严格应用 JSON。

全天事件必须使用 date-only 和 exclusive end date：

```json
{"title":"Holiday","allDay":true,"startDate":"2026-11-01","endDate":"2026-11-02"}
```

`--idempotent` 使用请求指纹和 60 秒的本机 receipt 避免 Agent 紧邻重试产生重复事件。
receipt 只保存指纹、opaque event/calendar ID 和时间戳，不保存事件标题、备注或地点；正常
edit/delete 会使相关 receipt 失效。`calendar conflicts` 检测严格时间重叠，最多扫描 200 个
事件；事件首尾相接不算冲突，超过上限会要求缩小范围或指定日历。

周期规则支持 daily/weekly/monthly/yearly、interval、weekday、ordinal weekday、月/年
位置，以及 endDate 或 occurrenceCount。周期事件 edit/delete 必须添加：

```text
--span this
--span future
```

删除先预览，再使用独立确认短语：

```text
macos-data calendar delete --id <id> --dry-run --span this --format json
macos-data calendar delete --id <id> --apply --confirm "DELETE EVENT" --span this --format json
```

详细边界参阅 [Calendar adapter 架构](development/calendar-adapter-architecture_CN.md)。

## Reminders（0.4 开发切片）

当前源码实现权限、iCloud reminder list 发现，以及只读 query/get：

```text
macos-data reminders permission --format json
macos-data reminders sources --format json
macos-data reminders lists --format json
macos-data reminders query [--status incomplete|completed|all] \
  [--due-start <iso8601>] [--due-end <iso8601>] \
  [--list <id|unique-title>] [--title <text>] \
  [--limit <1...200>] [--cursor <cursor>] --format json
macos-data reminders get --id <opaque-reminder-id> --format json
macos-data reminders create --input <file>|--stdin --dry-run|--apply [--idempotent] --format json
macos-data reminders edit --id <opaque-reminder-id> --input <file>|--stdin --dry-run|--apply --format json
macos-data reminders complete --id <opaque-reminder-id> --dry-run|--apply --format json
macos-data reminders reopen --id <opaque-reminder-id> --dry-run|--apply --format json
macos-data reminders delete --id <opaque-reminder-id> --dry-run --format json
macos-data reminders delete --id <opaque-reminder-id> --apply --confirm "DELETE REMINDER" --format json
```

需要显式选择时可以添加 `--source iCloud` 或准确 source identifier。只有唯一验证通过、
包含 reminder lists 的 iCloud CalDAV source 才能被选择，否则 fail closed。query 默认只查
未完成 reminder；due 边界必须是带明确 offset 的 ISO 8601 timestamp。结果采用按实际时刻的
确定性排序；anchor cursor 绑定经过隐私哈希的查询条件和已选 list 集合。修改查询/list，或
anchor 已被删除、修改后继续分页会被拒绝。未完成 reminder 的 due 范围会在 fetch 前下推到
EventKit。fetch 超时为 10 秒并传递调用方取消；结果超过 5,000 条会失败并提示缩小范围。
但 EventKit 会先生成结果数组，所以该上限是响应安全边界，不是严格的峰值内存上限。

start/due 通过 `value`、`hasTime`、`floating` 和 `timeZone` 区分仅日期、floating timed
和 IANA-zone timed。只读 contract 同时返回兼容性字段 `hasAlarms`、
`hasRecurrenceRules` 以及详细 `alarms`、`recurrenceRules` 数组；相对、绝对和地点 alarm
均可读取，但地点 alarm 写入仍不支持。create、partial edit、complete/reopen 和单条 delete
均已实现。

`create --dry-run` 会验证并标准化未保存 draft，不调用 `EKEventStore.save`。目标可写 list
依次通过 JSON `listID`、所选 iCloud source 内的可写系统默认 list、唯一可写 iCloud list
确定；存在歧义时 fail closed。preview 故意不返回 `id`。顶层未知 JSON 字段也会被拒绝，
避免 Agent 拼写错误被静默忽略。

`create --apply` 通过 EventKit 保存一次，并立即使用返回的 opaque ID 回读。
`verification: "readback_confirmed"` 是强成功状态；`save_accepted_readback_pending` 表示
EventKit 已接受保存但立即回读尚不可见，调用方必须保留 ID 且不得自动重试。
`--idempotent` 使用私有 60 秒本地 receipt，只保存 SHA-256 输入指纹、opaque
Reminder/list ID 和创建时间，不保存 title、notes、URL、alarm 或 recurrence。

edit JSON 使用 partial patch：省略字段保持不变；`notes`、`url`、`start`、`due`、
`alarms`、`recurrenceRules` 传 `null` 会清空；传值会替换。`title`、`priority`、`listID`
不能为 null。完成状态由独立 complete/reopen 命令处理，edit 会拒绝该字段。若原 reminder
包含只读地点 alarm，修改 alarms 会失败，避免静默丢失数据。apply 只 save 一次，并沿用
create 的 no-auto-retry 回读状态。真实 edit apply 已在一次性 gate 中通过，最终残留为 0。

`complete` 设置完成状态和明确 completion timestamp；`reopen` 同时清除两者。重复目标状态
返回 `already_completed` 或 `already_incomplete`，不再次 save。周期 reminder 完成后若下一
未完成 occurrence 可见，会单独通过 `nextOccurrence` 返回。真实 complete/reopen apply
和重复 no-op 验证已通过。
独立周期完成 gate 也已在本机 iCloud 通过并确认零残留。EventKit 在 due 日期向后推进时
复用了同一个 opaque reminder ID，因此调用方不能用 ID 是否变化判断 occurrence 是否推进：

```text
bash scripts/run_reminders_recurrence_integration.sh --confirm "REMINDERS RECURRENCE TEST"
```

删除必须先 dry-run，或为 apply 提供准确确认短语。`absence_confirmed` 表示 opaque ID 已无法
解析；`remove_accepted_readback_pending` 表示 EventKit 已接受删除但立即 absence verification
仍不确定，调用方不得自动重试，应使用相同 ID 调用 `get`。

一次性真实 iCloud create/get/edit/complete/reopen/delete gate 已在本机通过，并确认最终
同名匹配数量为 0。
unit、release、read 和 dry-run gate 均不写入 reminder。再次运行仍须获得明确授权：

```text
bash scripts/run_local_reminders_integration.sh --with-writes --confirm "REMINDERS CRUD TEST"
```

```json
{
  "title": "Prepare weekly report",
  "listID": null,
  "notes": null,
  "url": null,
  "priority": "high",
  "start": null,
  "due": {"value":"2026-08-17","timeZone":null,"hasTime":false,"floating":true},
  "alarms": [{"relativeMinutes":-10}],
  "recurrenceRules": []
}
```

参阅 [Reminders 0.4 架构草案](development/reminders-adapter-architecture_CN.md)。

## Mail（0.2）

Mail 0.2 是只读 adapter：不发送、起草、回复、转发、移动、归档、删除或标记邮件，
也不修改 mailbox、账户或 Mail 偏好设置。未支持的写入类命令会在访问 Mail 数据前
返回 usage error。

运行只读 capability 检查：

```text
macos-data mail doctor --format json
```

`doctor` 动态发现最高数字的 `~/Library/Mail/V*`，只读打开 `Envelope Index`，检查
WAL、数据库一致性、必需 schema、Full Disk Access 和当前 Automation 状态。它不启动
Mail.app、不触发授权弹窗，也不读取主题、邮箱地址、mailbox 名称或正文。

`fastPathAvailable: true` 表示当前主机满足 V10 SQLite metadata 快路径；这不是对未来
macOS/Mail schema 的保证，每次运行仍会重新 probe。Automation 的
`target_not_running` 或 `requires_consent` 不影响 SQLite 快路径，但表示 text fallback
或 `mail reveal` 当前不可用。

发现隐私安全的账号作用域和 mailbox：

```text
macos-data mail accounts --format json
macos-data mail mailboxes --format json
macos-data mail mailboxes --account-id <opaque-account-id> --format json
```

account ID 是 adapter 派生的 opaque local scope；响应不会返回原始账号 authority 或
完整 mailbox URL。mailbox 和 message ID 同样是 opaque 值，调用方不应解析其内部格式。

读取本地 Mail schema 报告的会话分组：

```text
macos-data mail threads --limit 50 --format json
```

只有明确的正数 `conversation_id` 才会被分组。响应只返回 opaque thread ID、消息数量和
最新接收时间，不会根据主题或参与者猜测关系。Mail.app fallback 不提供此命令。

只搜索本地已缓存的邮件正文，不启动 Mail.app：

```text
macos-data mail search --text "project alpha" --limit 20 --format json
```

该命令只读取本地 EMLX 缓存，最多扫描 200 个 metadata 候选，时间预算为 1 秒。缺失、partial、
损坏或截断的缓存会写入 `limitations`；返回无匹配不代表远程或未缓存邮件中不存在该词。该命令
绝不会 fallback 到 Mail.app 或远程内容。

V10 schema/FDA 快路径不可用时，仅当 Mail.app 已运行且 Automation 已授权，CLI 才会
使用 metadata fallback。其 Apple Event 超时为 5 秒，硬上限为 32 个账号、200 个
顶层 mailbox 和 25 个 message 候选；query 始终返回 `incomplete`、不提供 cursor，
并报告 `backend: "mail_app"` 和 fallback reason。fallback 的 `ambx_`/`appmsg_` ID
不能与 SQLite ID 混用。raw export 和 attachment verify 仍只允许 fast path。

查询有限 message metadata：

```text
macos-data mail query --unread --limit 50 --format json
macos-data mail query --mailbox-id <id> --subject <text> --format json
macos-data mail query --from <text> --received-after 2026-07-01 --format json
macos-data mail query --cursor <cursor> --limit 50 --format json
```

filter 使用 AND 语义，支持 `--account-id`、`--mailbox-id`、`--from`、`--to`、
`--subject`、`--received-after`、`--received-before`、`--unread`、`--flagged`
和 `--has-attachment`；日期使用 ISO 8601。默认 limit 为 50，最大为 200；结果被截断
时返回 `nextCursor`。查询使用参数绑定和 250 ms SQLite deadline，只读取 envelope
metadata，不读取正文。

Mail.app metadata fallback 只在有限候选中应用 filter，不枚举嵌套 mailbox，并拒绝
`--cursor`。调用方必须保留 `limitations`，不能把无匹配结果解释成完整 mailbox 搜索。

Mail 响应返回 `backend`；query 还返回 `cacheState`、`truncated`、`nextCursor`、
`elapsedMs`、`fallbackReason`、`incomplete` 和 `limitations`。metadata 保持
`backend: "sqlite"`；显式 text 读取会根据实际来源返回 `sqlite_emlx` 或 `mail_app`。

使用 `mail query` 返回的 opaque ID 读取唯一一封邮件：

```text
macos-data mail get --id <id> --format json
macos-data mail get --id <id> --content text --format json
macos-data mail get --id <id> --content raw --output message.eml --format json
macos-data mail get --id <id> --content raw --output -
```

默认 projection 是 `metadata`，不会读取 EMLX payload。`--content text` 才会显式
读取本地缓存，解码常见 MIME transfer encoding 和 charset，优先非附件的
`text/plain`；没有 plain part 时，把 HTML 清洗为纯文本。实现不调用 WebKit，也不会
加载远程资源。

`--content raw` 输出准确 RFC 822 bytes，必须指定 `--output`。raw 不嵌入 JSON；
`--output -` 不能与 `--format json` 同用；命名文件已存在时拒绝覆盖。单封原文上限
64 MiB，本地文件读取预算 100 ms，抽取文本上限 2 MiB，MIME 最深八层。

`cacheState: "partial"` 绝不会被报告为 complete。缓存 text 缺失时，显式 text 读取
可通过串行 Mail.app Apple Events fallback，单次超时 3 秒，超时后熔断 30 秒。普通
fallback 不自动启动 Mail；Automation 拒绝、Mail 未运行和定位失败都会保留在结构化
结果中。raw 不做 fallback，因为 Mail.app 的 text `source` 不能保证 byte-exact。
Mail reindex 或移动邮件后，opaque local ID 可能变 stale。

在 Mail.app 中可视化定位一条结果：

```text
macos-data mail reveal --id <id> --format json
```

`reveal` 可以启动并激活 Mail.app；它使用同一个 opaque local ID，不会主动修改 read、
flag、mailbox 或 message 数据。

不导出附件，只交叉校验 attachment metadata：

```text
macos-data mail attachments verify --id <id> --format json
```

verifier 只返回 SQLite/MIME count、cache state，以及 complete EMLX 是否一致；不返回
附件名、路径或 payload。partial 或缺失 EMLX 始终为 `incomplete` 且不标记 `matched`，
即使当前可见 count 恰好相等也一样。

显式导出本地缓存附件：

```text
macos-data mail attachments export --id <id> --output ./attachments --format json
```

导出要求 SQLite/EMLX fast path；必要时创建输出目录，拒绝路径穿越和不安全文件名，
不会覆盖已有文件，单个附件上限为 20 MiB。不会使用 Mail.app fallback 或远程附件。

## Contacts

列出当前 Contacts 容器：

```text
macos-data contacts containers --format json
```

默认使用已经验证的 iCloud 容器。也可以显式指定 `iCloud` 或列表返回的
精确的 iCloud container identifier：

```text
macos-data contacts list --container iCloud --format json
macos-data contacts get --external-id <id> --container <icloud-container-id> --format json
```

不存在或非 iCloud 的 container 会直接报错，不会静默回退到本地或
Exchange 账户。

当前版本只使用 iCloud Contacts 容器：

```text
macos-data contacts container
```

如果找不到 iCloud 容器，所有写入操作都会拒绝，不会回退到本地或其他账户。

导出 JSON 快照：

```text
macos-data contacts export --format json
macos-data contacts export --format json --output contacts-snapshot.json
```

`list` 用于实时读取；`export` 用于生成可保存、审计或交给 Agent 批量处理的快照。

带有 `--format json` 的失败响应也使用结构化格式：

```json
{"ok":false,"error":{"code":"CONTACT_QUERY_ERROR","message":"..."}}
```

写入命令使用 `--format json` 时，会在 `data.contact` 返回保存后的联系人
状态，并同时返回操作名称。delete 返回删除前最后读取到的联系人状态：

```json
{"ok":true,"data":{"operation":"updated","contact":{}}}
```

External ID migration 会在 `data.contact` 返回迁移后的联系人，并同时返回
`from` 和 `to` 标识。

检查权限和联系人数量：

```text
macos-data contacts permission
macos-data contacts count
macos-data contacts count --format json
```

JSON 响应使用独立于 CLI 发布版本的 contract `0.1`。成功 envelope 包含
`ok`、`contractVersion` 和 `data`；错误 envelope 包含 `ok`、
`contractVersion` 和 `error`。

以 JSON 读取联系人：

```text
macos-data contacts list --format json
macos-data contacts get --external-id <id> --format json
```

Contacts 有上限分页，使用统一分页 contract：

```text
macos-data contacts list --limit 50 --format json
macos-data contacts list --limit 50 --cursor <opaque-cursor> --format json
macos-data contacts query --kind organization --limit 50 --format json
```

分页响应包含 `items`、`limit`、`nextCursor`、`truncated`、`complete`。Contacts cursor
由 adapter 管理且保持 opaque；Agent 必须原样传回，不应从中推导 offset。

Mail query 响应现在也提供统一的 `items` 字段；已有的 `messages` 字段作为 0.2 客户端
兼容别名保留。Mail.app fallback 始终明确标记为 incomplete，不会伪造 cursor；其
`limitations` 会说明该 backend 为什么不能恢复分页。

查询支持多个条件，条件之间使用 AND 语义；单次最多三个不同字段：

```text
macos-data contacts query --name "张三"
macos-data contacts query --kind organization
macos-data contacts query --phone "+81"
macos-data contacts query --email "person@example.com"
macos-data contacts query --url "example.com"
macos-data contacts query --organization "Example"
macos-data contacts query --postal-code "10001"
```

从 JSON 创建联系人。写入前应先查看 dry-run：

通过 CLI 创建的每个联系人都必须在 JSON 中包含 `externalID`。外部创建且
没有 external ID 的联系人可以被读取，但 CLI 不会创建或管理没有 ID 的新记录。

```text
macos-data contacts create --input contact.json --dry-run
macos-data contacts create --input contact.json --apply
cat contact.json | macos-data contacts create --stdin --dry-run
cat contact.json | macos-data contacts create --stdin --apply --idempotent
macos-data contacts edit --external-id <id> --input contact.json --dry-run
macos-data contacts edit --external-id <id> --input contact.json --apply
cat patch.json | macos-data contacts edit --external-id <id> --stdin --dry-run
```

第一版通过 `kind` 区分 `person` 和 `organization`。`external_id` 只能存储在 label 为 `macos-data-cli` 的 URL 中，value 格式为 `x-macos-data://external-id/<id>`。其他 URL label 都按普通网址处理。CLI 默认选择已经验证的 iCloud 容器，也可以显式指定 `--container iCloud` 或准确的容器 identifier。

默认情况下重试仍保持严格行为。只有在确认相同 external ID 的持久化字段
等价时，才应给 create 添加 `--idempotent`。JSON-only metadata 和头像可用性
不参与比较；持久化字段不同会返回冲突。删除命令可以添加
`--ignore-not-found`，让已经删除的联系人在重试时返回成功。

读取结果包含 `imageAvailable` 字段。它表示 Contacts.framework 当前报告的
头像数据可用性，不能当作 Contacts.app 是否显示 iCloud 头像的绝对事实。
头像 apply 结果还会包含 `avatar.status`：`readback_confirmed` 表示强回读确认；
`verification_unknown` 表示保存已接受，但 Framework 无法安全读回头像。此时应遵循
`avatar.nextAction`，不能自动重试、删除或重建联系人。

普通编辑不会修改 `external_id`。如果输入 JSON 包含 `externalID`，它必须与 `--external-id` 完全一致；修改 external ID 应单独设计迁移功能。

如果写入返回 CoreData 错误 `134092`，说明 macOS Contacts 记录可能已经损坏或无法保存。应先保留 JSON 表示，再明确确认删除并重新创建联系人，然后重试。`macos-data` 不会自动执行这个破坏性恢复操作。

头像使用独立参数写入，不进入普通联系人 JSON：

```text
macos-data contacts edit --external-id <id> --image ./avatar.png --dry-run
macos-data contacts edit --external-id <id> --image ./avatar.png --apply
```

只读验证已有头像，不会写入联系人：

```text
macos-data contacts avatar verify --external-id <id> --format json
```

结果可能是 `readback_confirmed`、`not_available` 或
`verification_unknown`。轻量预检为 false 时会返回
`verification_unknown`，不会强行读取可能触发 fault 的 `imageData`。

如果已有 iCloud 联系人无法安全原地编辑头像，可以使用独立的替换流程。
该流程会保留 JSON 联系人字段，但会创建新的 Contacts 记录，因此必须明确确认：

```text
macos-data contacts avatar replace --external-id <id> --image ./avatar.png --dry-run
macos-data contacts avatar replace --external-id <id> --image ./avatar.png --apply --confirm "RECREATE CONTACT"
```

头像输入上限为 10 MB，处理后最长边不超过 1024 px，最终文件不超过 200 KB。超过输入上限、无法解码或无法压缩到目标大小时，CLI 会报错且不会修改联系人。

普通编辑是 partial update：未出现的字段保持原值；显式写入 `null` 会清空该字段。

### metadata 规则（0.1）

`metadata` 是 JSON contract 字段。0.1 版本会在 JSON 读取、编辑预览和 export 中保留它，但不会写入 Apple Contacts。这样不会把项目私有结构误写入 Notes 或其他联系人字段。

删除单条联系人必须使用 `external_id`。先预览：

```text
macos-data contacts delete --external-id <id> --dry-run
```

确认删除：

```text
macos-data contacts delete --external-id <id> --apply --confirm "DELETE CONTACT"
```

迁移 external ID 必须使用独立命令。先预览：

```text
macos-data contacts external-id migrate --from <old-id> --to <new-id> --dry-run
```

确认无误后写入：

```text
macos-data contacts external-id migrate --from <old-id> --to <new-id> --apply --confirm "CHANGE EXTERNAL ID"
```

完整的数据格式、错误行为和安全规则请参阅[开发规则](development/rules_CN.md)，本机验证记录请参阅[本机 Contacts 测试数据](development/local-contacts-fixture.md)。
