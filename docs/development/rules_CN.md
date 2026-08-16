# 开发规则

## 测试驱动流程

每个新功能都遵循以下流程：

1. 先定义 CLI 行为和 JSON contract。
2. 先增加一个失败的单元测试或集成测试。
3. 用最小改动让测试通过。
4. 运行完整测试套件。
5. 如果涉及 macOS Framework，则构建 release、安装本地版本，并用真实 CLI 验证。
6. 更新使用说明和路线图状态。

测试不能在每次运行时重复创建真实联系人。映射和匹配使用确定性的纯测试；端到端验证使用文档中记录的本机测试联系人。

真实 Contacts CLI 集成测试与 `swift test`、CI 分离，默认只执行读取和
dry-run：

```bash
bash scripts/run_local_contacts_integration.sh
```

验证进程级 JSON contract 和错误路径时，运行：

```bash
bash scripts/run_cli_contract_tests.sh
```

该测试仅在本机运行，不会写入或删除 Contacts 记录。

Calendar 0.3 使用独立的进程 contract、只读和 dry-run gate：

```bash
bash scripts/run_calendar_contract_tests.sh
bash scripts/run_calendar_read_smoke.sh
bash scripts/run_calendar_dry_run_smoke.sh
bash scripts/run_local_calendar_integration.sh
```

这些流程不保存 Calendar 修改。真实 Calendar CRUD 必须另行明确授权，并且只允许
create → read-back → edit → read-back → delete → absence verification 的一次性事件流程。
真实 gate 还必须提供 `--with-writes --confirm "CALENDAR CRUD TEST"`；命令行确认短语
不能取代当前任务中用户对真实写入的明确授权。

只有在明确验证真实写入时，才执行一次性联系人流程：

```bash
bash scripts/run_local_contacts_integration.sh --with-writes
```

写入流程只创建并清理临时集成联系人，不能对固定的 person、organization
或 create smoke-test 联系人执行删除。

## Contacts contract

- `kind` 只有 `person` 和 `organization`，来源是原生 Contacts 记录类型。
- 读取模型中的 `external_id` 可以为空，但创建联系人时必须提供。
- CLI 永远不得创建没有 `external_id` 的联系人；这是 Contacts 的固定规则，不是未来待办功能。
- `external_id` 使用 `mpia://ext-id/<id>` 写入 URL 字段。
- 保留 URL 的 label 必须严格为 `mpia-cli`；读取端不得把 `Homepage` 或其他 label 识别为 `external_id`。
- 保留 URL 的 value 格式为 `mpia://ext-id/<id>`。
- `imageAvailable` 只表示 Contacts.framework 报告的头像数据可用性，不能据此断言 Contacts.app 是否显示 iCloud 头像。
- 头像 apply 结果包含 `avatar.status`：`readback_confirmed` 表示保存后成功读回非空头像数据；`verification_unknown` 表示保存已接受，但 Contacts.framework 无法安全读回头像。Agent 应遵循 `avatar.nextAction`，不能自动删除、自动重建或自动重试头像写入。
- `contacts avatar verify` 会先进行轻量头像可用性预检；预检为 false 时跳过 `imageData` 读取，以降低 iCloud fault 风险。
- `contacts avatar replace` 是无法原地编辑头像时的明确恢复流程。它要求确认短语 `RECREATE CONTACT`，会创建新的 Contacts 记录，绝不能自动调用。
- 如果写入时出现 CoreData 错误 `134092`，CLI 必须认为该记录可能已损坏，保留诊断信息，并提醒 Agent 先保存 JSON 字段、在明确确认后删除并重新创建联系人，再重试操作。CLI 不得自动删除或自动重建联系人。
- Apple 联系人 identifier 只是本地实现细节，不能作为跨系统 ID。
- 查询按字段类型做规范化；组合查询使用 AND 语义，最多三个不同字段。
- 多条匹配必须返回歧义错误，不能静默选择联系人进行写入。

## 安全与隐私

- 读写前都必须检查 Contacts 权限。
- 写入必须显式选择 `--dry-run` 或 `--apply`。
- 不直接访问 Contacts 私有数据库，也不上传联系人数据。
- 0.1 只允许 iCloud 容器；找不到时必须拒绝写入，不得回退到本地或其他账户。
- 诊断日志只保留 `external_id` 作为关联键。邮箱、国际电话号码、绝对路径
  和底层异常文本在写入 `~/Library/Logs/mpia-cli/diagnostics.log`
  前必须脱敏。
- 诊断日志不得包含姓名、组织、邮政地址、头像二进制数据或完整联系人 JSON。

## Calendar contract（0.3）

- 只使用 Apple 公共 EventKit，不读取 Calendar 私有数据库。
- 读取必须具有 `fullAccess`；`notDetermined`、`denied`、`restricted` 和 `writeOnly`
  使用不同的稳定错误。
- 默认和显式 source 都必须解析为唯一 iCloud CalDAV source；禁止静默回退到其他账户。
- query 必须提供 start/end，start < end，范围最多 366 天，limit 为 1...200。
- source、calendar、`calevent_` 和 cursor ID 都是本机 opaque 值。
- `calevent_` ID 绑定 calendar item 与 occurrence start，确保周期事件不会误定位到第一个 occurrence。
- create/edit/delete 必须显式选择 `--dry-run` 或 `--apply`；delete apply 额外要求
  `--confirm "DELETE EVENT"`。
- 周期事件 edit/delete 必须在 params 中显式选择 `"span":"this"` 或 `"span":"future"`。
- 参与者字段只读。0.3 不发送邀请，也不接受非空 attendees 写入。
- 普通事件日期使用 ISO 8601；全天事件使用 date-only `YYYY-MM-DD`，且 endDate 不包含在
  事件内。timeZone 使用有效 IANA identifier。
- 每个 alarm 只能有一个相对或绝对触发条件；`alarms: []` 清空提醒，create 必须先移除
  目标日历继承的默认 alarm，再应用 JSON。
- Calendar `POST /calendar/create` 的 `"idempotent":true` 参数使用 60 秒、opaque、隐私最小化的 receipt 处理紧邻进程
  重试；receipt 不得保存事件文本。
- 冲突扫描最多处理 200 个事件；仅边界相接不算冲突。
- dry-run 临时数据必须位于权限 700 的自动删除目录，不在日志或测试输出中打印事件标题、
  参与者、地点、URL 或备注。
- 真实 apply 测试不得修改现有用户事件，只能使用完成后删除的一次性 fixture。
- 真实周期 gate 必须验证 `this` 和 `future` 范围，并在中途断言失败时也清理全部 occurrence。

## Safari contract（0.8）

- Safari 0.8.1 从有界、非 symlink 的 `Bookmarks.plist` snapshot 读取 bookmark 与
  Reading List；文件访问严格只读。malformed、过大、Reading List proxy 重复或层级/节点超限
  时必须 fail closed。
- 普通 bookmark 排除 Safari proxy 和 Reading List subtree。item、folder 与 cursor ID 均为
  opaque；cursor 绑定准确 snapshot SHA-256，plist 发生任何变化后必须 stale。
- Reading List add 通过 Safari 官方 AppleScript 命令执行。必须使用严格
  JSON、`--dry-run|--apply`、标准化 URL 幂等、五秒 deadline 和立即有界回读；pending 或
  unknown 结果禁止自动重试。
- 返回值和诊断不得包含 raw plist ID、plist bytes、title、URL、preview、用户路径或
  AppleScript source。
- 0.8.1 仅以受保护的 local-only bookmark/folder CRUD 开放直接 `Bookmarks.plist`
  修改。必须确保 Safari 完全退出、携带准确 source hash、创建 metadata 准确的私有 recovery、
  原子替换并完成有界回读；结果必须明确返回 `syncStatus=local_only`。不得声称 iCloud 同步，
  也不得停止或修改 Safari 同步进程。
- 现有 Safari 数据绝不作为 mutation fixture。每次真实 add 或 direct mutation gate 都需要
  当前任务明确授权，并验证 fixture 零残留。

## Codex 授权与 Computer Use

- 对于不需要密码、Apple ID 或安全确认的授权和设置流程，应由 Codex 自动完成。
- 这包括打开对应的 macOS 设置页面、启动已经授权的本机应用，以及在用户明确请求
  且系统允许的情况下，通过 Computer Use 接受普通权限提示。
- 只有 macOS 要求管理员密码、Apple ID 凭据、安全确认或其他秘密信息时，才将流程
  交给用户在外部 Terminal 或 UI 中输入。
- 不要反复要求用户手动点击 Codex 可以安全完成的步骤；应明确说明剩余的交接点和原因。
- Computer Use 必须严格限制在用户请求的应用和权限范围内，绝不输入、保存或暴露密码、
  token 或其他凭据。

## 兼容性

当前最低部署目标为 macOS 26.0+。使用仓库约定的 Swift/Xcode 工具链，并将 Framework 可用性检查放在 adapter 边界附近。

进行兼容性验证时，必须先重新构建 Release 配置再测试二进制；旧的 `.build/release/mpia` 可能不包含最新源码改动。

## Metadata（0.1）

`metadata` 只属于 JSON contract。Contacts 0.1 不保证把它写入 Apple Contacts；不得偷偷写入 Notes、URL 或其他字段。未来如需持久化，必须先定义版本化编码和迁移规则。

普通读取不得请求头像二进制。头像验证先进行轻量可用性预检；无法安全原地编辑的记录必须使用明确确认的头像替换/重建流程。
