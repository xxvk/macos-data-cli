# Reminders adapter 0.4 架构草案

状态：0.4 架构基线已确认；权限、发现、受限 query/get、alarm/recurrence 映射、create、
部分 edit、complete/reopen 和受保护的单条 delete 已实现。一次性
create/get/edit/complete/reopen/delete cleanup gate 已在本机 iCloud 通过，最终同名匹配
数量为 0；complete/reopen 覆盖安全重复 no-op 和周期下一 occurrence 返回。
独立周期完成 gate 已在本机 iCloud 通过并确认零 fixture 残留。

本 adapter 只使用 Apple 公共 EventKit Framework。不得直接读写 Reminders 私有数据库，
不得使用屏幕坐标自动化操作 Reminders.app，也不得静默切换到非 iCloud 账户。

## 用户目标与 MVP 边界

0.4 的目标是让本地 Agent 通过稳定 JSON contract 管理个人 iCloud 任务：

- 查询 source 和提醒事项列表；
- 使用有界分页查询全部、未完成或已完成 reminder；
- 通过 opaque 本机 ID 读取单条 reminder；
- 创建、部分编辑、完成、重新打开和删除单条 reminder；
- 表达标题、备注、URL、优先级、开始/截止时间、alarm、重复规则、完成状态和所属列表；
- 所有修改先支持 dry-run，apply 后必须重新读取验证。

首版不写入地点 alarm，也不支持共享列表成员管理、列表创建/删除、附件、子任务、标签和
Reminders.app 智能列表语义。已有地点 alarm 返回只读摘要，避免普通编辑静默删除它。

## Apple API 边界

- 权限使用 `EKEventStore.requestFullAccessToReminders()`；EventKit 没有 Reminders
  read-only 权限等级。
- App bundle 需要 `NSRemindersFullAccessUsageDescription`；已废弃的
  `NSRemindersUsageDescription` 不作为主要 contract。
- Reminders 列表是 `calendars(for: .reminder)` 返回的 EventKit calendar。
- 查询使用全部、未完成、已完成 reminder predicate，再通过异步 fetch 获取结果。
- 写入只使用 EventKit save/remove；不同 `EKEventStore` 的对象不得混用。
- 重复 reminder 只能取得当前第一个未完成 occurrence；完成后下一项才会出现。CLI
  不得虚构 Calendar 式的全部 occurrence 编辑能力。

Apple 官方参考：

- [访问 Event Store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
- [EKEventStore](https://developer.apple.com/documentation/eventkit/ekeventstore)
- [创建 events 和 reminders](https://developer.apple.com/documentation/eventkit/creating-events-and-reminders)
- [创建重复 event 或 reminder](https://developer.apple.com/documentation/eventkit/creating-a-recurring-event)
- [NSRemindersFullAccessUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsremindersfullaccessusagedescription)

## 权限与 iCloud 选择

- `reminders permission` 返回当前权限；只有显式运行该命令才请求 full access。
- 默认 source 必须是唯一验证通过、包含 reminder lists 的个人 iCloud CalDAV source。
- source 缺失或不唯一时 fail closed；不得回退到 Local、Exchange、Google 等账户。
- 默认读取选中 source 下所有 lists；`--list` 可以缩小范围。
- 系统默认 list 只有属于选中 iCloud source 且可写时才能自动用于创建；否则如果只有一个
  可写 iCloud list 就选它；存在多个时必须显式提供 `listID` 并 fail closed。
- `macos-data resources` 应报告 Reminders 能力，但不得暴露 Apple ID 或账户地址。

## 建议命令

```text
macos-data reminders permission --format json
macos-data reminders sources --format json
macos-data reminders lists --format json
macos-data reminders query [--status incomplete|completed|all] [--due-start <value>] [--due-end <value>] [--list <id|unique-title>] [--title <text>] [--limit <1...200>] [--cursor <cursor>] --format json
macos-data reminders get --id <opaque-reminder-id> --format json
macos-data reminders create --input <file>|--stdin --dry-run|--apply [--idempotent] --format json
macos-data reminders edit --id <id> --input <file>|--stdin --dry-run|--apply --format json
macos-data reminders complete --id <id> --dry-run|--apply --format json
macos-data reminders reopen --id <id> --dry-run|--apply --format json
macos-data reminders delete --id <id> --dry-run --format json
macos-data reminders delete --id <id> --apply --confirm "DELETE REMINDER" --format json
```

只有 permission 命令可以触发授权请求。

## 建议 JSON 模型

```json
{
  "id": "reminder_<opaque>",
  "title": "Prepare weekly report",
  "notes": null,
  "url": null,
  "priority": "none",
  "completed": false,
  "completionDate": null,
  "start": null,
  "due": {
    "value": "2026-08-17",
    "timeZone": null,
    "hasTime": false,
    "floating": true
  },
  "hasAlarms": true,
  "hasRecurrenceRules": false,
  "listID": "remlist_<opaque>",
  "listTitle": "Reminders"
}
```

`start` 和 `due` 使用同一种对象结构。CLI 不得把仅日期值强制转换为 UTC 零点。带时间值
使用 ISO 8601 和 IANA 时区；仅日期值使用 `YYYY-MM-DD`、`hasTime: false` 和 null
时区。priority 使用 `none/high/medium/low`，不暴露任意 EventKit 整数。
当前只读切片同时报告兼容性 presence 字段和详细 alarm/recurrence 数组。相对、绝对和地点
alarm 均可读取；地点 alarm 仍明确为只读。

## Identifier 策略

0.4 不定义也不强制自定义 `externalID`。保留用户 URL 和 notes，不建立本机身份 sidecar；
只有显式幂等创建使用短期隐私最小化 receipt。

`reminder_<opaque>` 包含 adapter 管理的 opaque 身份：先尝试本机
`calendarItemIdentifier`，失效后再使用 calendar server 提供的 external identifier，
并按 reminder 类型和选中的 iCloud source 过滤。Apple 明确说明 full sync 可能导致本机
identifier 失效，因此必须有这个 fallback；出现多个或不匹配结果时 fail closed。Agent
不得解析该 ID，也不得把成功解析视为永久的跨系统身份保证。

## 分页与查询限制

EventKit fetch 是异步操作，并可能返回无界数组。必须先选定 lists，把未完成 reminder 的 due
范围下推到 EventKit predicate，单次最多返回 200 条，传递取消并提供结构化 timeout，禁止在
receipt 和诊断日志中保存 notes。fetch 后的 5,000 项上限无法阻止 EventKit 先生成完整数组，
因此不能宣称为严格峰值内存保证。排序固定为：未完成
在前；有 due 的未完成项按 due 升序、无 due 放后；已完成项按 completion date 降序；最后
以 list ID、标准化 title 和 opaque ID 打破并列。anchor cursor 绑定过滤条件、list 集合、
排序版本和上一页最后一项。anchor 消失或变化时返回 stale，而不是静默跳过；anchor 之前新增
项目不会推动后续页 offset。

## 写入安全与幂等

- 所有 mutation 必须且只能选择 `--dry-run` 或 `--apply`。
- delete apply 还必须提供 `--confirm "DELETE REMINDER"`。
- dry-run 不调用 EventKit save/remove。
- create dry-run 返回不带 ID 的 `ReminderDraft`，不得为未保存对象伪造 opaque ID；未知顶层
  字段必须 fail closed。
- create apply 在 save 后、read-back 前写入隐私最小化 60 秒 receipt，只含 hash、opaque ID
  和时间 metadata。save accepted/read-back pending 不是重试信号；必须返回 ID 并要求调用方
  使用 `get`，不得自动删除或重建。
- apply 后重新 fetch 并返回最终状态。
- 重复 complete/reopen 是带明确状态的安全 no-op。
- 幂等创建必须拒绝非等价重试。
- 不得声称可以读取隐藏的未来重复 occurrence。

0.4 在基础 CRUD 之后实现 recurrence 的读取、创建、编辑和清空。complete 遵循 EventKit
当前 occurrence 模型，并回读下一个可见未完成 occurrence。地点 alarm 可读；写入 payload
尝试创建或修改地点 alarm 时返回结构化 unsupported-field 错误。

## TDD 与发布 gate

实现顺序：Core contract 和日期映射；mock 权限/source/list 测试；只读 store 与分页；
CLI 错误 contract；所有写命令 dry-run；EventKit apply/read-back；显式一次性 iCloud
集成测试；最后执行 Release build、已安装 smoke、文档和版本审计。

`swift test` 和默认 gate 不得读取个人 reminder 或真实写入。手动 gate 只创建唯一标记的
一次性 reminder，验证 CRUD、complete、reopen 和清理；它不是 CI，并要求确认短语。

独立周期 gate 为：

```text
bash scripts/run_reminders_recurrence_integration.sh --confirm "REMINDERS RECURRENCE TEST"
```

它创建两次 daily recurrence，完成当前 occurrence，验证下一未完成 occurrence 的 due 日期
已经向后推进，在 `nextOccurrence` 立即可见时交叉核对，并删除全部同名 fixture。本机实测
EventKit 会复用同一个 opaque ID；EventKit 不保证每个可见 reminder occurrence 都有不同
identifier，因此不能把 ID 变化作为推进条件。

## 已确认架构决策

- 0.4 不使用自定义 external ID，保留 URL 和 notes。
- recurrence 在基础 CRUD 后进入 0.4。
- `start` 和 `due` 共用 DateComponents-aware 对象结构。
- 地点 alarm 只读，写入明确拒绝。
- 先使用有效的 iCloud 系统默认 list，其次选择唯一可写 iCloud list；否则要求显式选择。
- 分页采用上述确定性排序和绑定过滤条件的 cursor。
