# mpia-cli

面向 Agent 和开发者的 macOS 原生数据访问 CLI 基础设施。

项目希望填补一个实际空白：Agent 需要操作 macOS 原生数据时，通常只能依赖脆弱的
GUI 自动化、特定平台集成，或直接接触不稳定的内部数据格式。`mpia-cli` 提供
本地、可脚本化、可测试的访问层：优先采用 Apple 公共 Framework；仅当公共 Framework
无法暴露所需数据时，才允许范围明确、有文档、fail-closed 的本地 adapter；任何写入必须
另行定义 recovery、并发、回读与同步边界。

## 快速开始

从源码构建，并获取第一个只读 JSON 资源快照：

```bash
git clone https://github.com/xxvk/mpia-cli.git
cd mpia-cli
export DEVELOPER_DIR="$(xcode-select -p)"
swift build
.build/debug/mpia resources --format json
```

环境要求：macOS 26 或更新版本、Apple Silicon，以及支持 Swift 6.2 的 Xcode。
公开二进制目前尚未经过 Developer ID 签名和公证。安装 Release 二进制或配置 macOS 权限前，
请先阅读[安装说明](INSTALL.md)。

## 使用方法

建议从 capability 与权限状态检查开始；以下命令不会修改用户数据。示例使用已经安装的
`mpia`；在源码 checkout 中请改用 `.build/debug/mpia`：

```bash
mpia resources --format json
mpia contacts permission
mpia mail doctor --format json
```

可能写入数据的命令均提供显式 dry-run/apply 路径，破坏性操作还需要额外确认短语。
完整说明请参阅[命令指南](docs/usage_CN.md)、[安全规则](docs/development/rules_CN.md)和
[稳定 JSON contract](docs/development/cli-contract_CN.md)。

## 项目状态

当前源码版本为 0.8.1。Contacts adapter 在 0.1.7 阶段已支持权限检查、iCloud 容器验证、JSON
读取、查询、受控写入、头像、删除、external ID 迁移和 JSON 快照导出。

Mail 0.2 已提供只读 capability 检查、账号和 mailbox 发现、有限邮件 metadata
查询、显式 cached text/raw 读取、Mail.app text fallback 和可视化 reveal 已可用。
adapter 只启用运行时验证通过的 V10 SQLite/EMLX 快路径，且永不写入 Mail store。

0.2.0 增加了 Mail adapter，同时保留既有 Contacts 命令面。

0.3.0 增加 Calendar：EventKit full-access 权限、唯一 iCloud CalDAV
source 选择、日历和事件查询、ISO 8601 时区、周期规则、opaque occurrence ID，以及
create/edit/delete 的 dry-run 和 apply 路径已经实现。只读和 dry-run 本机验证已通过；
一次性事件的真实 apply CRUD 集成测试也已完成，并确认测试事件最终不存在。这些能力属于
0.3.0 源码范围；公开预编译分发可能晚于源码 tag。

Reminders 0.4 增加权限/list、有限 query/get、受保护 CRUD、complete/reopen、alarm 和
recurrence；基础及周期 iCloud gate 均通过且 fixture 零残留。

Photos 0.5 增加 PhotoKit 权限、album 发现、有界 metadata-only asset query/get、opaque ID、
limited library 语义，以及默认禁网和禁止覆盖的单资源安全 export。

Notes 0.6 增加有界、只读的 Notes.app Automation adapter：权限状态、account 和
嵌套 folder 发现、metadata query、显式 plaintext/HTML 读取与 attachment metadata。
它不访问 Notes 私有 store。Notes 0.6.1 增加受保护 create/rename/move：必须绑定用户确认的
iCloud account，支持 dry-run/apply、乐观并发、隐私安全 hash 和立即回读；仍不支持现有正文替换、
attachment mutation、delete 或 folder CRUD（这是已发布 0.6.1 的边界）。Notes 0.6.2 已增加
面向无 attachment 简单正文的受保护 `notes edit-body`，以及使用 opaque selector、名称 hash/current
parent 前置条件、cycle 防护和隐私安全输出的 folder create/rename、move 与空 folder 删除 preview。一次性签名 app
正文修改 gate 已通过 hash 回读验证并确认 fixture 零残留；folder gate 的 create/rename 已通过，
Notes 4.13 move apply 因 identity 不安全而使用稳定错误 fail closed。
签名 app 的一次性 iCloud
create/rename/move/read-back gate 已通过，并确认测试 note 零残留。
空 folder 删除 preview 会重新核对名称、parent 与空状态，但 Notes 4.13 真实 gate 导致 metadata graph
失效，child 随后以新 opaque ID 再次出现。因此 apply 已禁用并 fail closed。
当前源码也已加入单条 Note 的受保护 soft delete：必须提供最新 modification date 与准确
`DELETE NOTE` 确认，只移动到 Notes Recently Deleted。永久删除仍只允许 UI 操作；签名 app
soft-delete gate 已通过：取得 action-time 明确确认后，仅通过 Notes UI 永久删除一次性 fixture，
保留一条无关的 Recently Deleted note，最终签名 app 查询确认 sentinel 零匹配。

Shortcuts 0.7.0 使用系统 `/usr/bin/shortcuts` 和公开的 `Shortcuts Events`
scripting dictionary，实现 permission、有限 list/get/folders、受保护 run 和 folder move。
synthetic TDD 与一次性真实 gate 已通过：准确文本输出、move preview、move apply/read-back、恢复及
fixture 零残留均已验证。adapter 会在冷启动命令中启动按需运行的 Shortcuts Events helper，并从
系统 CLI 的 stdout 捕获 plaintext 输出；它不读取动作图，也不访问 Shortcuts 私有数据库。
开发树现已加入 0.7.1 受管理源码 validate/build/create/update、私有 registry/receipt 和
managed-forget 代码。create/update 除非提供准确确认短语，否则只 preview；任意已有 Shortcut
不能被静默接管。macOS 27 Beta 5 + Cherri 2.3.0 的一次性 create/run/retain-old update/run/cleanup
gate 已通过，fixture/registry 零残留。两个可正常运行的导入对象公开 action count 都是 `0`，因此
编译 count 与 observed count 分开返回；两者不一致时同名 replace fail closed。
开发树也已加入 0.7.2 受保护的现有对象编辑：`shortcuts edit inspect` 安全分类单个本地 `.cherri` 或
`.shortcut`，不导入、不打开、不持久化，也不回显内容。opaque/signed artifact、未知 action、
magic variable/附件等嵌套结构、疑似 secret 与 device-bound reference 均 fail closed 为人工迁移；
输入严格限于本地文件：iCloud share link 与其他 URI 在读取前拒绝，不下载、不跟随 redirect、不读取
clipboard，也不触发 import；
符合条件的 unsigned artifact 可交给 `shortcuts edit plan`，用输入 SHA-256 保护并在内存 shadow graph
中验证 `insert_text`、`replace_text`、`delete_action`、`move_action`；结果完全脱敏且不写 Shortcuts.app。
仅包含 `replace_text` 的 plan、“graph 已有 Text 且只在末尾 `insert_text`”的 plan，或删除后至少保留
一个 action 的有界全 `delete_action` plan，可使用
`shortcuts edit copy`：dry-run 不读取 AX；apply 要求准确的
可见 editor 名称 SHA-256 和 `EDIT SHORTCUT COPY`，先复制原件，只修改 resolver 认可的 Text value，
并逐步回读。末尾追加使用准确的 `duplicateAction:`；delete 只按 resolver 绑定的 Close button，并等待准确
缩小后的 graph。有界全 `move_action` plan 已开放 copy-first apply：每个相邻 reorder 只调用准确 menu identifier，
并回读完整视觉顺序。中间/无来源 insert、混合 operation plan、同索引 move 与语义不可区分的相邻 action 继续拒绝。
`shortcuts edit ui-inspect` 进一步提供有界、只读 AX 结构发现：不弹授权、不激活、不点击、不输入，
也不返回 label/title/identifier，并始终关闭 apply。
macOS 27 Beta 5 disposable gate 已校准准确的 `editor.shortcutname` marker，脱敏发现唯一 candidate，
随后删除 fixture，并确认搜索与 candidate 均为零残留。
内部 copy-first mutation coordinator 已完成 TDD 设计边界：要求准确确认、预演完整 plan、证明不同 identity
且 graph 完全一致的恢复副本，并逐步回读。
当前设计还把公开脱敏 plan 绑定到不可 Codable 的 private 内存 execution plan，并增加 recovery-first、
准确 sequence 的 guarded bridge。macOS 27 的具体 debug-only gate 已证明 copy-first Text replacement、
append-only Text insertion、有界 action delete 与有界全 move，包括 hash 回读、完整视觉顺序、剩余 action
不变和原件不变。任意位置 insert 与混合 operation 仍不可用；全部 gate fixture 均已明确确认删除并验证零残留。

Safari 0.8 从 Safari property-list snapshot 有界发现 bookmark 与 Reading List，提供 opaque ID、
严格查询、stale cursor 检测和受保护的 Reading List 创建。接下来的本地 CRUD slice 增加 bookmark/
folder create、edit、move、delete，默认 dry-run，并要求乐观 source hash、Safari 完全退出、私有
recovery、原子替换、rollback 与回读。这些 plist mutation 明确只在本机生效，不会同步到 iCloud；
同步研究延后到 0.8.8。

详细开发计划请参阅：

- [中文路线图](ROADMAP_CN.md)
- [English Roadmap](ROADMAP.md)

使用与开发文档：

- [使用说明](docs/usage_CN.md)
- [开发规则](docs/development/rules_CN.md)
- [安装说明](INSTALL.md)
- [Agent 集成指南](AGENTS.md)
- [本机 Debug 与 Contacts 授权](docs/development/local-debug-and-tcc_CN.md)
- [变更记录](CHANGELOG.md)
- [发布签名与 notarization TODO](docs/development/distribution-signing.md)
- [Calendar 0.3 架构](docs/development/calendar-adapter-architecture_CN.md)
- [Photos 0.5 架构](docs/development/photos-adapter-architecture_CN.md)
- [Notes 0.6 可行性决策](docs/development/notes-adapter-feasibility_CN.md)
- [Shortcuts 命令与安全边界](docs/usage_CN.md#shortcuts070-开发切片)
- [Shortcuts 0.7.1 authoring 边界](docs/development/shortcuts-authoring_CN.md)
- [Shortcuts 0.7.2 现有 Shortcut 编辑边界](docs/development/shortcuts-existing-editing_CN.md)
- [Safari 0.8 架构与 direct-plist 可行性 gate](docs/development/safari-adapter-architecture_CN.md)

## 核心目标

- 通过 Terminal 使用，安装后即可被脚本和 Agent 调用
- 使用稳定的 CLI 和 JSON contract
- 所有 Agent 共用同一个 CLI，不绑定 Codex、Claude Code 或其他平台
- 优先使用 Apple 公共 Framework，不依赖 GUI 自动化
- 对写操作提供 dry-run、差异预览和显式确认
- 在本机运行，不上传联系人或其他系统数据
- 通过 adapter 逐步扩展到不同的 macOS 数据服务

Obsidian 是项目作者的实际使用场景，但不是公共协议的强制依赖。外部系统可以使用自己的稳定 ID；项目不会把某个 Agent 或知识库写死在核心设计中。

## Mail 0.2 的只读边界

Mail 0.2 明确只读：不发送、起草、回复、转发、移动、归档、删除或标记邮件，也不修改
mailbox、账户或 Mail 偏好设置。任何类似写入的未支持命令，都必须在访问 Mail store 或
Mail.app 之前返回 usage error。这个边界属于 `0.2.0` contract；未来若要改变，必须在
单独版本中重新定义权限、确认和回滚策略。

## 0.1 范围：Contacts adapter

第一版计划支持 macOS Contacts 中个人和组织联系人的读取与受控写入，并通过 `kind` 明确区分记录类型：

- `person`
- `organization`

支持内容包括：

- 姓名、组织、部门和职位
- `phoneticGivenName` 与 `phoneticFamilyName` 假名字段
- 邮箱、电话、网址和地址
- 头像
- CLI 创建的每个联系人都必须有 `external_id`
- 组织名称、邮箱、电话等多因素匹配
- JSON 输入和输出
- `--dry-run` 与显式 `--apply`

头像 apply 结果包含验证状态。`readback_confirmed` 表示保存后成功读回非空
头像数据；`verification_unknown` 表示保存已接受，但 Contacts Framework 无法
安全读回头像。对于 iCloud 头像，`imageAvailable` 不是 GUI 显示状态的绝对事实。

匹配到多个联系人时，CLI 应返回歧义结果并禁止自动写入。Agent 可以读取结果后自行判断下一步操作。

当前可用的命令：

```text
mpia contacts permission
mpia contacts count [--format json]
mpia contacts list --format json
mpia contacts get --external-id <id> --format json
mpia contacts query --name "..."
mpia contacts query --kind organization
mpia contacts query --phone "..."
mpia contacts query --email "..."
mpia contacts query --url "..."
mpia contacts query --organization "..."
mpia contacts query --postal-code "..."
mpia contacts create --input contact.json --dry-run
mpia contacts create --input contact.json --apply
cat contact.json | mpia contacts create --stdin --dry-run
cat contact.json | mpia contacts create --stdin --apply --idempotent
mpia contacts edit --external-id <id> --input contact.json --dry-run
mpia contacts edit --external-id <id> --input contact.json --apply
cat patch.json | mpia contacts edit --external-id <id> --stdin --dry-run
mpia contacts edit --external-id <id> --image <file> --dry-run
mpia contacts edit --external-id <id> --image <file> --apply
mpia contacts avatar verify --external-id <id> --format json
mpia contacts avatar replace --external-id <id> --image <file> --dry-run
mpia contacts avatar replace --external-id <id> --image <file> --apply --confirm "RECREATE CONTACT"
mpia contacts delete --external-id <id> --dry-run
mpia contacts delete --external-id <id> --apply --confirm "DELETE CONTACT"
mpia contacts delete --external-id <id> --apply --confirm "DELETE CONTACT" --ignore-not-found
mpia contacts external-id migrate --from <old> --to <new> --dry-run
mpia contacts external-id migrate --from <old> --to <new> --apply --confirm "CHANGE EXTERNAL ID"
mpia contacts export --format json [--output <file>]
```

查询条件之间使用 AND 语义，单次最多 3 个条件；同一字段不能重复。`--format json` 不计入条件数量。

机器可读响应使用独立于 CLI 发布版本的 JSON contract `0.1`。统一 envelope
包含 `ok`、`contractVersion`，以及 `data` 或 `error`。
稳定退出码和错误码详见 [CLI contract 规则](docs/development/cli-contract_CN.md)。

当前限制与 0.1 收尾事项：

```text
- 默认使用已经验证的 iCloud 容器，也可以显式指定 `--container iCloud`
  或准确的 iCloud 容器 identifier
- `--idempotent` 只对 create 重试生效；同一 external ID 对应不同持久化字段时仍会报错
- `--ignore-not-found` 只对 delete 重试生效
- 真实 CLI CRUD 集成测试仅在本机执行，不由 `swift test` 自动运行
- vCard 导入/导出、批量操作和变更检测尚未实现
```

## 0.2：Mail 只读命令

```text
mpia mail doctor --format json
mpia mail accounts --format json
mpia mail mailboxes [--account-id <id>] --format json
mpia mail query [filters] [--limit <1...200>] [--cursor <cursor>] --format json
mpia mail get --id <id> [--content metadata|text] --format json
mpia mail get --id <id> --content raw --output <file|->
mpia mail reveal --id <id> --format json
mpia mail attachments verify --id <id> --format json
```

`doctor` 不启动 Mail.app、不触发权限弹窗，也不读取邮件主题、地址或正文。只有运行时
确认 `V10` 必需结构、WAL 和只读数据库状态后，`fastPathAvailable` 才会为 `true`。
metadata 查询默认返回 50 条、最多 200 条，使用参数绑定、opaque local ID、cursor
分页和 query deadline；不会读取正文。
如果 V10 schema/FDA 快路径不可用，但 Mail.app 已运行且 Automation 已授权，账号、
顶层 mailbox 和 message metadata 会使用 5 秒有限 Mail.app fallback；最多检查 32 个
账号、200 个 mailbox 和 25 个 message 候选。query 始终标记 `incomplete`、不返回
cursor，并使用独立的 `appmsg_` opaque ID。
`mail get` 默认只返回 metadata；text/raw 必须显式指定。缓存 text 缺失时可以使用
有上限的 Mail.app Apple Events fallback；raw 仍保持 cache-only 和 byte-exact。raw
bytes 不进入 JSON，且不会覆盖已有输出文件。这里仅 `mail reveal` 会主动激活 Mail.app。
`mail attachments verify` 只比较 SQLite 和缓存 MIME 的数量，不导出附件名或 payload；
partial EMLX 始终保持 unverified。raw 导出和 attachment verify 不使用 metadata fallback。

## 0.3：Calendar adapter

```text
mpia calendar permission
mpia calendar sources --format json
mpia calendar calendars --format json
mpia calendar query --start <iso8601> --end <iso8601> --format json
mpia calendar conflicts --start <iso8601> --end <iso8601> --format json
mpia calendar get --id <opaque-event-id> --format json
mpia calendar create --input event.json --dry-run|--apply [--idempotent] --format json
mpia calendar edit --id <id> --input patch.json --dry-run|--apply [--span this|future] --format json
mpia calendar delete --id <id> --dry-run [--span this|future] --format json
mpia calendar delete --id <id> --apply --confirm "DELETE EVENT" [--span this|future] --format json
```

默认只使用唯一验证通过的 iCloud CalDAV source，不会回退到 Local、Exchange 或其他
账户。事件 ID、source ID、calendar ID 和 cursor 都是本机 opaque 值。周期事件 edit/delete
必须显式指定 `this` 或 `future`；参与者支持读取，但 0.3 暂不支持写入或发送邀请。
普通事件使用 ISO 8601 timestamp；全天事件使用 `YYYY-MM-DD` 的开始日期和不包含在事件内的
结束日期。相对/绝对 alarm 支持查询、写入、替换和以 `alarms: []` 清空。
完整 JSON 和安全规则参阅 [Calendar 0.3 架构](docs/development/calendar-adapter-architecture_CN.md)。

## 设计边界

- 不复制 Apple SDK 或重新分发 Apple 二进制
- 不直接读写 Contacts 内部数据库
- 不使用 Apple 私有 API
- 不依赖 GUI 自动化、屏幕坐标或 AppleScript 作为核心写入路径
- Mail 0.2 存在一个明确记录的例外：由于 Apple 没有提供通用 mailbox 枚举 Framework，
  允许严格只读访问 Mail 本地索引和缓存文件。adapter 必须验证 schema、未知版本
  fail closed，并且永远不得写入这些文件。
- 不把 Apple 联系人 identifier 当作跨系统稳定主键
- 不上传联系人、地址、电话或头像数据
- 不内置 AI Agent
- 不把 Obsidian 作为公共数据协议的必要组成部分

## 平台

计划最低支持 macOS 26.0+。项目使用 Swift Package Manager，并优先采用 Apple 公共 Framework。

Contacts 数据访问需要用户授予系统权限。CLI 应负责检查权限、说明授权状态，并在写入前要求明确确认。

Homebrew 更新、Gatekeeper、quarantine 处理和本地发布验证流程，请参阅 [`docs/development/distribution-signing.md`](docs/development/distribution-signing.md)。

## 后续方向

Calendar 0.3、Reminders 0.4、Photos 0.5 和有界只读的 Notes 0.6 源码版本已完成。
受保护的 Notes create/rename/move 写入归入 0.6.1。Notes 集成属于 Automation，
不是原生 Notes Framework，也不得读取 Notes 私有 store。
`mpia` 在整个 0.x 阶段保持 canonical command，正式命名复审延后至 1.0.0 发布前。
当前 Reminders 开发切片支持 full-access 发现、受限 query/get，以及带 read-back 状态和
可选短期幂等的 `create --dry-run|--apply`。部分编辑和受保护的单条删除已实现；编辑真实写入
验证已通过。complete/reopen 已实现安全重复 no-op，真实写入验证也已通过。自动 cleanup
gate 已实现；一次性 create/get/edit/complete/reopen/delete gate 已在本机 iCloud
通过，最终同名匹配数量为 0。详见
[Reminders 使用说明](docs/usage_CN.md)。
Photos 当前提供 permission/resource discovery、有限 album metadata 分页，以及默认隐藏精确
位置的 metadata-only asset query/get，并支持默认禁网、禁止覆盖的单资源安全 export，详见
[Photos 架构](docs/development/photos-adapter-architecture_CN.md)。
Mail 0.2 采用
只读 SQLite/EMLX、Mail.app Apple Events 回退和可视化确认的混合架构。
详见 [Mail 架构决策](docs/development/mail-adapter-architecture_CN.md)。vCard、批量操作和
变更检测属于 Contacts 的后续工作。每个 adapter 都应独立定义权限要求、数据映射、
错误格式和测试策略。

## 社区参与

- 提出行为或 contract 变更前，请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。
- 安全问题请使用 [SECURITY.md](SECURITY.md) 说明的私密报告路径。
- 参与本项目时请遵守 [Code of Conduct](CODE_OF_CONDUCT.md)。

## 许可证

请参阅 [LICENSE](LICENSE)。
