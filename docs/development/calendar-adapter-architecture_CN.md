# Calendar adapter 0.3 架构

Calendar adapter 使用 Apple 公共 EventKit，不读取 Calendar 私有数据库，也不依赖
Calendar.app GUI 或 AppleScript。本文描述 0.3 开发分支 contract；它尚未代表已发布版本。

## 权限和 source 选择

- 读取事件必须具有 EventKit `fullAccess`。`writeOnly` 不得被解释为可读。
- `calendar permission` 调用 `requestFullAccessToEvents()`。
- 默认 source 必须是唯一可验证的 `iCloud` CalDAV source。
- 可以显式使用 `--source iCloud` 或 source identifier，但非 iCloud source 会被拒绝。
- 找不到或匹配到多个 iCloud source 时 fail closed，不回退到 Local、Exchange、Google
  或其他账户。
- query 默认读取所选 iCloud source 下的全部事件日历；`--calendar` 可以指定 identifier
  或唯一标题。
- create 优先使用同一 iCloud source 内的系统默认可写日历；没有可验证默认值且存在多个
  可写日历时，要求 JSON 中显式提供 `calendarID`。

## 命令

```text
macos-data calendar permission
macos-data calendar sources --format json
macos-data calendar calendars --format json
macos-data calendar query --start <iso8601> --end <iso8601> [--calendar <id|title>] [--title <text>] [--limit <1...200>] [--cursor <cursor>] --format json
macos-data calendar conflicts --start <iso8601> --end <iso8601> [--calendar <id|title>] --format json
macos-data calendar get --id <opaque-event-id> --format json
macos-data calendar create --input <file>|--stdin --dry-run|--apply [--idempotent] --format json
macos-data calendar edit --id <id> --input <file>|--stdin --dry-run|--apply [--span this|future] --format json
macos-data calendar delete --id <id> --dry-run [--span this|future] --format json
macos-data calendar delete --id <id> --apply --confirm "DELETE EVENT" [--span this|future] --format json
```

所有日期输入和 Calendar JSON 输出使用 ISO 8601。`timeZone` 使用 IANA identifier，
例如 `Asia/Tokyo`。

最小 create JSON：

```json
{
  "title": "Planning",
  "startDate": "2026-08-16T09:00:00+09:00",
  "endDate": "2026-08-16T10:00:00+09:00",
  "timeZone": "Asia/Tokyo"
}
```

`allDay` 默认 `false`；`attendees` 和 `recurrenceRules` 默认空数组。参与者可从 EventKit
读取，但 0.3 不提供参与者写入，输入非空 attendees 会明确报错。

全天事件的 start/end 必须是 `YYYY-MM-DD`，end 是 exclusive。普通事件仍要求带时间和
时区偏移的 ISO 8601 timestamp。Alarm 每项只允许 `relativeMinutes` 或 `absoluteDate`；
`[]` 清空提醒。创建时必须先删除 EventKit 继承的目标日历默认 alarm。

幂等创建不能假设两个独立 EventKit 进程立即一致。`--idempotent` 因此使用 60 秒、mode 700
目录/mode 600 文件的本机 receipt；receipt 不保存事件正文，只保存请求 SHA-256、opaque ID
和时间戳。冲突检测硬上限为 200 个事件，并只返回冲突事件 ID 与重叠区间。

## 周期事件

recurrence rule 显式表示：

- `frequency`: `daily`、`weekly`、`monthly`、`yearly`
- `interval`
- `daysOfWeek`
- `weekdayOrdinals`，例如每月第二个星期一
- `daysOfMonth`、`monthsOfYear`、`weeksOfYear`、`daysOfYear`、`setPositions`
- `end.endDate` 或 `end.occurrenceCount`，两者不能同时出现

周期事件 edit/delete 必须显式提供 `--span this` 或 `--span future`。CLI 不提供隐式
“整个系列”操作，也不会猜测调用方意图。

## opaque event ID

EventKit 普通 event identifier 不能安全地区分周期系列的每个 occurrence。公开 ID 因此使用
`calevent_` opaque token，内部绑定 `calendarItemIdentifier + occurrenceStart`。Agent 必须
原样传回，不得解析或持久假设内部编码。修改开始时间后，返回的新 ID可能变化；旧 ID应视为
stale。该设计确保后续 occurrence 的 edit/delete 不会误落到系列第一个事件。

source ID、calendar ID 和 cursor 同样是本机 EventKit/adapter opaque 值，不是跨设备 ID。

## 写入安全

- create/edit/delete 都要求 `--dry-run` 或 `--apply`。
- delete apply 额外要求 `--confirm "DELETE EVENT"`。
- dry-run 可以读取并生成 before/after，但不会调用 EventKit save/remove。
- EventKit save/remove 只对当前 CLI 进程所使用的同一个 `EKEventStore` 对象执行。
- 真实写入测试必须创建一次性测试事件，完成 create → read-back → edit → read-back →
  delete → absence verification；不得使用用户现有事件作为 apply fixture。

## 验证

```bash
swift test
bash scripts/run_calendar_contract_tests.sh
bash scripts/build_debug_app.sh
bash scripts/run_calendar_read_smoke.sh
bash scripts/run_calendar_dry_run_smoke.sh
bash scripts/run_local_calendar_integration.sh
bash scripts/run_calendar_recurrence_integration.sh --confirm "CALENDAR RECURRENCE TEST"
```

只读 smoke 只输出 source、calendar 和分页事件数量。dry-run smoke 的临时 JSON 存放在
权限为 700 的临时目录，退出时自动删除，不打印事件标题、参与者、地点或备注。

真实 EventKit apply 集成测试已在明确授权后通过：一次性事件完成 create、回读、edit、
再次回读、delete 和不存在验证。复测命令仍为：

```bash
bash scripts/run_local_calendar_integration.sh --with-writes --confirm "CALENDAR CRUD TEST"
```

真实重复事件 gate 也已通过：6 次系列、Alarm 回读、紧邻幂等重试、`this`/`future` 编辑、
`this`/`future` 删除和最终 URL fixture 数量为零。
