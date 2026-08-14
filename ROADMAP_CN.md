# macos-data-cli Roadmap

## 当前状态

项目当前正在准备 Calendar adapter 源码版本 `0.3.0`。Contacts、只读 Mail 与 Calendar
流程均已实现并通过本机验证；本路线图区分已完成能力、后续 adapter 与外部分发工作。

项目的长期目标是建立一个通用的 macOS 原生数据访问基础设施，让不同 Agent 和脚本
通过统一的 CLI 与 JSON contract 优先使用 Apple 公共 Framework；公共 Framework
缺位时，只允许范围明确、可测试的本地只读 adapter。项目不绑定 Codex、Claude Code
或其他特定 Agent 平台。

## 已确定的 0.1 设计决策

- `external_id` 作为通用 JSON 字段；Contacts adapter 优先将其写入 URL 字段，不依赖 Contacts Notes entitlement。
- 第一版目标是能够与 iCloud Contacts 同步的容器。当前 CLI 已验证并使用该
  容器，也支持通过 `--container iCloud` 或准确 identifier 显式选择。
- JSON contract 支持 `metadata`，但 0.1 不保证将任意 metadata 写入 Contacts。
- 删除操作必须使用显式确认短语，并继续要求 `--apply`。
- 项目最低目标为 macOS 26+；macOS 27 beta 可作为开发和兼容性测试环境，不作为当前稳定支持基线。

## 0.1：Contacts adapter

第一版先聚焦 macOS Contacts，目标是在 macOS 26.0+ 上提供本地、CLI-first 的联系人访问能力。开发期间可以使用 macOS 27 beta 做前置测试。

### CLI 基础

- [x] 创建 Swift Package 和 CLI 入口
- [x] 支持 `--help`、`--version` 和 `-v`
- [x] 定义已实现命令的 JSON 输出、错误格式和退出码
- [x] 支持通过 `--stdin` 从标准输入读取 JSON；同时保留 JSON 文件输入

### 权限与安全

- [x] 检查 Contacts 读写权限
- [x] 在 CLI 内提供授权提示和权限不足时的恢复信息
- [x] 写入支持 dry-run，并要求显式 apply
- [x] 日志默认不输出联系人敏感内容

### 读取能力

- [x] 列出联系人并输出 JSON
- [x] 通过 `external_id` 获取单个联系人详情
- [x] 按姓名、电话、邮箱、网址、组织和邮编查询联系人
- [x] 支持最多三个条件的 AND 组合查询
- [x] 创建联系人 dry-run 和 apply 基础流程
- [x] 创建前检查重复 `external_id`
- [x] 支持个人和组织联系人
- [x] 通过 `kind` 区分个人和组织联系人
- [x] 支持通过 `--kind person|organization` 按类型筛选查询
- [x] 支持姓名、组织、职位、邮箱、电话、网址、地址和头像
- [x] 在 JSON contract 和 Contacts adapter 中支持 `phoneticGivenName` 与 `phoneticFamilyName`
- [x] 支持 JSON 输出
- [x] 在不读取头像二进制的情况下返回头像是否存在
- [x] 头像 apply 后返回明确的写入回读验证状态
- [x] 增加只读 `contacts avatar verify`，返回三态验证结果
- [x] 增加需要明确确认的头像替换/重建流程，处理无法安全原地写入的 iCloud 记录

### 匹配能力

- [x] CLI 创建联系人必须有 `external_id`，同时支持多因素匹配
- [x] 支持组织名称、邮箱、电话等查询条件的多因素匹配
- [x] 匹配到多个结果时返回 `ambiguous` 并阻止自动写入
- [x] 将查询匹配和唯一匹配解析放在不依赖 Framework 的 `Core` 层

### 写入能力

- [x] 创建联系人
- [x] 更新联系人
- [x] 删除联系人
- [x] 支持 `--dry-run` 和 `--apply`
- [x] 编辑 dry-run 输出写入前后的差异
- [x] create、edit、头像和 delete 的 apply 返回最终状态
- [x] external ID migration 的 apply 返回并在本机验证最终状态
- [x] 支持显式请求的 create 和 delete 重试幂等行为

### 数据模型

- [x] 定义通用联系人 domain model
- [x] 定义 Contacts adapter 的字段映射
- [x] 预留 `external_id` 和 `metadata`
- [x] 区分通用 JSON contract 与 Apple Framework 专有字段
- [x] 支持 JSON 快照导出
- [x] 支持 `contacts containers` 和显式 `--container iCloud`/identifier 选择
- [x] 增加并在本机运行真实 CLI CRUD 集成测试；临时联系人已创建、编辑、写入头像、删除并验证不存在

## 版本路线

每个版本都以一个 macOS 数据域 adapter 为核心。可靠性、Agent 调用、测试、安装和发布不是独立版本，而是每次迭代都必须同步完善的横向能力。

### 0.2：Mail adapter

架构决策：[Mail adapter 0.2.0 中文摘要](docs/development/mail-adapter-architecture_CN.md)。

- [x] 实现只读 `mail doctor`，检查 Mail store、Full Disk Access、Automation 和 schema capability
- [x] 保持 macOS 26.0 正式基线；首个直接读取快路径仅对运行时验证通过的 `V10` schema 启用
- [x] 动态发现最高的受支持 `~/Library/Mail/V*`
- [x] 以严格只读 SQLite 连接查询账号、mailbox、数量和有限邮件元数据
- [x] 解析本地 `.emlx` / `.partial.emlx`，显式读取 raw/text 并报告 partial cache
- [x] 在未来有限附件导出前，枚举并交叉校验 SQLite/EMLX attachment count；
  partial-only 内容保持明确的 unverified 状态
- [x] 显式 text 读取且正文未缓存时回退到公开 Mail.app Apple Events；raw 仍只允许
  byte-exact 的本地缓存导出
- [x] 在不放宽 V10 metadata/schema fail-closed gate 的前提下，把有限 fallback 扩展到
  不受支持的账号存储
- [x] 增加不修改邮件的 `mail reveal`，在 Mail.app 中可视化确认结果
- [x] 返回 backend 来源、cache state、分页截断状态和结构化权限/schema 错误
- [x] 使用 opaque local message ID，分离 selector/content/rendering，并要求 raw RFC 822 通过显式 `--output` 输出
- [x] 强制查询 deadline、结果上限和 Apple Event 熔断，禁止递归文件扫描成为自动 fallback
- [x] 永不写入 Mail SQLite、WAL/SHM、`.emlx` 或账号配置

### 0.3：Calendar adapter

架构决策：[Calendar adapter 0.3 中文说明](docs/development/calendar-adapter-architecture_CN.md)。

- [x] 完成 0.3 命名决策：0.3.0 和整个 0.x 阶段继续使用 `macos-data` 作为唯一 canonical
  command，不增加别名；`xvk-data` 已否决。正式命名复审延后为 1.0.0 release gate，且不
  预先承诺改名。见 [`ADR 0001`](docs/development/adr/0001-cli-name-until-1.0_CN.md) 和
  [`命名审计`](docs/development/naming-audit_CN.md)。
- [x] 基于 EventKit 访问日历和事件；本机 full-access 授权和隐私安全只读 smoke 已通过
- [x] 支持日历、事件、时间、地点、参与者和备注；参与者在 0.3 明确保持只读
- [x] 支持事件查询、创建、更新和删除
  - 查询、get、create/edit/delete 代码路径与 dry-run 已实现
  - `calevent_` 使用 calendar item + occurrence start 精确定位周期 occurrence
  - 一次性事件 create → read-back → edit → read-back → delete → absence verification 已在本机 iCloud Calendar 通过
  - Alarm、全天 date-only、60 秒隐私最小化幂等 receipt、冲突检测已实现
  - 真实 6-occurrence gate 已覆盖幂等重试、Alarm、this/future 编辑删除和最终清理
  - 真实 feature gate 已覆盖全天事件回读、相对/绝对/清空 Alarm、非等价幂等重试拒绝、
    严格重叠与仅边界相接，并确认最终测试残留为 0
  - Calendar 加固测试已覆盖东京、UTC、DST 开始和结束、receipt 过期与权限、幂等内容
    不一致、损坏 contract 和 200 事件上限
- [x] 支持时区和重复事件的明确表达，包括 IANA time zone、周期结束和 ordinal weekday
- [x] 支持 dry-run、JSON contract、full-access 权限检查、稳定错误码和 Calendar exit 5
- [x] 将 `VERSION`、CLI `--version`、两份 Info.plist、README、INSTALL、测试和 CHANGELOG
  统一为 0.3.0；本机 Release 与安装到 Homebrew prefix 的 CLI 均报告 0.3.0
- [x] 通过默认 no-apply 的 0.3.0 release gate：121 个 Swift tests、全局与 Calendar CLI
  contract、Calendar read/dry-run smoke、Mail 只读 smoke、Release build、签名 Debug app、
  版本审计和 diff check
- [ ] 提交最终 release candidate、合并到 `main`、在干净 `main` worktree 重跑 gate，
  然后创建 annotated tag `v0.3.0`

### 0.4：Reminders adapter

- [x] 基于 EventKit 访问提醒事项
  - 已建立独立 `RemindersAdapter` target、full-access 权限、唯一 iCloud source
    选择、列表发现和稳定 exit 6 错误 contract
  - query/get 已使用 EventKit 异步 fetch 与 opaque ID；包含 10 秒 timeout、Task
    cancellation、5,000 条 fetch 后上限和有界日期 predicate
- [x] 支持提醒列表、标题、备注、截止时间和完成状态
  - 读取 JSON 已覆盖列表、标题、备注、URL、优先级、完成状态/时间、start/due
    DateComponents、alarm 和 recurrence
  - 日期区分 date-only、floating timed 和 IANA 时区 timed value
- [x] 支持非周期提醒的查询、创建、更新和完成
  - query/get 已支持状态、due 范围、列表、标题、limit 和隐私安全 anchor cursor
  - `create --dry-run|--apply [--idempotent]` 已实现：严格 JSON、日期/alarm/recurrence
    校验、可写 list 解析、EventKit 单次 save、opaque ID、即时 read-back 状态和私有
    60 秒 receipt
  - 单条 delete dry-run/apply 已实现；apply 要求 `--confirm "DELETE REMINDER"`，只 remove
    一次，并区分 absence confirmed 和 read-back pending
  - 一次性 create/get/edit/complete/reopen/delete gate 已在本机 iCloud 通过 trap cleanup
    和最终零匹配验证
  - 部分 edit 已实现严格 patch 解码、可空字段清空、可写 iCloud list 移动、地点 alarm
    保护、单次 save 和明确回读状态；真实 edit apply 已通过且最终零残留
  - complete/reopen 已实现明确 completion timestamp、安全重复 no-op、单次 save、回读状态
    和周期 `nextOccurrence`；真实 apply 与重复 no-op 验证已通过
- [x] 真实验证周期 reminder 完成后的 EventKit 行为
  - 创建一次性 daily recurrence，完成当前 occurrence，在不虚构隐藏实例的前提下验证
    下一未完成 occurrence，最后清理整个测试 fixture 并确认零残留
  - 本机 iCloud gate 已通过：due 日期向后推进，EventKit 复用了同一个 opaque reminder
    ID，`nextOccurrence` 与 query 结果一致，清理后同名 reminder 数量为 0
- [x] 支持列表选择和多因素匹配
  - query 以 AND 语义组合状态、due 范围、list 和标题；list 可用 opaque ID 或唯一标题
    选择，歧义时拒绝继续
- [x] 支持 dry-run、JSON contract 和权限检查
  - 权限、JSON envelope、exit 6、read contract tests、Release 编译和隐私最小化
    本机 read smoke 已实现
  - `resources` 在 guarded create apply 实现后将选中的 Reminders iCloud source
    报告为 readable/writable；不代表其他 mutation 已完成

### 0.5：Photos adapter

- 架构文档：[Photos adapter 0.5](docs/development/photos-adapter-architecture_CN.md)
- [x] 评估 Photos framework 的访问和授权模型
  - PhotoKit 公开 API 可用；第一阶段只读 metadata，不读取私有数据库，也不下载媒体字节
  - full 和 limited 权限必须区分；limited 返回 `complete: false`，add-only 不能满足读取
  - export 独立实现，默认禁止网络，并区分可用 metadata 与 iCloud-backed 原始文件
  - TDD permission/resource 基础已实现：limited scope、status-only/request 命令、Info.plist、
    稳定 exit/error code，并通过完整回归和无写入 CLI contract
- [x] 支持照片和相册的只读查询
  - album discovery 已实现用户 folder 层级、user/smart kind、重名 title、opaque ID、
    kind-bound anchor cursor、默认 50/最大 200 分页和 limited `complete: false`
  - synthetic TDD 与 permission-before-fetch 已通过；稳定 app 身份下的隐私最小化真实图库
    gate 已通过：共 34 个集合（11 user、23 smart、0 folder），`complete: true`、未截断，
    且未输出 title/identifier/location/media
  - asset query/get 已支持最长 366 天的 creation range、album/media/favorite filter、
    hidden/location opt-in、opaque ID、稳定排序、filter-bound pagination 和纯 metadata PhotoKit fetch
- [x] 支持元数据、创建时间、位置和资源引用
  - payload 包含媒体类型/subtype、尺寸、时长、创建/修改时间、favorite/hidden/burst/
    Live Photo、opaque asset ID 和 opt-in 坐标；媒体 byte 可用性明确保持 `unknown`
- [x] 明确导出、修改和删除操作的安全边界
  - export 每次只处理一个 asset，默认禁止网络、禁止覆盖，不把媒体 byte 写入 JSON/stdout，
    区分资源变体，并通过私有临时文件和原子移动完成输出
  - runtime command 与 TDD file coordinator 已实现。离线真实 gate 检查 5 个 iCloud-only
    candidate，全部 fail closed 为 `PHOTOS_CONTENT_NOT_LOCAL`，未下载、未留输出。2026-08-14
    经用户明确批准的网络 gate 从同一组 5 个 candidate 中成功导出 1 个 original，验证非零
    byte 与 `0600` 权限，并在退出时删除私有临时输出
  - import 和 metadata mutation 继续延后，必须先具备 dry-run/apply 与一次性 fixture cleanup；
    delete 最后实现，并保留 Recently Deleted 语义和准确确认短语
- [x] 支持权限检查、JSON contract 和测试
  - 19 项 Photos adapter 测试、176 项 Swift 总测试和 CLI 负向 contract 已通过；真实 gate
    通过稳定 LaunchServices app 身份运行，asset JSON 只进入私有临时目录，对外仅打印聚合数量；
    30 天 sample 返回 5 条上限记录，并通过一条 opaque-ID get 回读

### 0.6：Notes adapter

- 可行性决策：[Notes adapter 0.6](docs/development/notes-adapter-feasibility_CN.md)
- [x] 审计 Apple Notes 公开 API 的可用范围，不提前承诺版本或实现
- [x] 判断 public-interface-only adapter 是否足以支持 note/folder query 和 read
  - macOS 26.5 SDK 没有公开 Notes 内容 Framework；Notes.app 4.13 正式发布 scripting
    dictionary，因此接受的边界是只读、受 TCC 管理且准确标记为 Automation 的 Apple Events adapter
- [x] 明确 attachment、link 和 rich text 的 MVP 边界
  - 0.6 支持 attachment metadata 和显式 opt-in 的 plaintext/HTML；binary export 延后；不承诺
    tag、pinned、富内容结构或 HTML/Markdown 无损 round trip
- [x] 分配 0.6，并要求权限检查、稳定错误、JSON contract、有界 Apple Events、synthetic TDD
  和隐私安全 live gate
- [x] 明确禁止私有 Notes 数据库、私有 Framework、直接访问 Notes CloudKit container 和 GUI 坐标自动化
- [x] 实现 permission 与 capability foundation
  - 已加入 status-only/显式 request 命令、稳定 Automation 状态与错误、统一只读
    `notesLibrary` resource、Info.plist usage text、4 项 synthetic test 和 CLI contract；本机
    非交互 probe 正确返回 `requiresConsent`
- [x] 实现 account 和嵌套 folder discovery，并使用 opaque ID
  - discovery 上限为 32 account、200 folder、16 层和 5 秒；SHA-256-derived ID 隐藏原始
    scripting identifier；synthetic test 覆盖层级、默认 account、shared、scope-bound 分页和完整性
  - 稳定 App 真实 gate 返回 1 个 account、12 个 folder、`complete: true`、未截断，只输出聚合
    结果并清理临时 JSON
- [x] 实现有界 metadata query 与 filter-bound pagination
  - metadata-only query 支持 account、folder、标题 substring 和修改时间 filter，以及与全部
    filter 绑定的 opaque cursor；最多枚举 200 条 note、递归 16 层 folder，并设置 5 秒
    Apple Events deadline
  - 19 项 Notes adapter 测试、195 项 Swift 总测试和 CLI 负向 contract 已通过；
    稳定 App 真实 gate 返回 163 条 note、
    `complete: true`、未截断、创建与修改时间覆盖完整，并且只打印聚合数量
- [x] 实现单条 note get，plaintext/HTML body 必须显式 opt-in
  - 默认 metadata-only，且不调用 body bridge；plaintext/HTML 必须显式选择，password-protected
    note fail closed，返回 UTF-8 正文上限为 256 KiB，诊断日志不记录正文
  - synthetic test 覆盖 metadata-only、projection 隔离、scripting ID 转义、locked note 和超限
    body；一次性 note 正文回读仍保留在最终稳定 App live gate
- [x] 加入 attachment metadata；binary export 延后到独立安全 gate
  - 显式 opt-in 最多返回 100 条 opaque attachment metadata，绝不读取 contents 或调用
    save/export；synthetic mapping 与脚本边界测试通过，真实零附件路径返回空且 complete 的列表
- [ ] 完成稳定 App Automation 与一次性 note live gate
  - query、metadata-only get、plaintext、HTML 和零附件读取均已通过稳定 App；一次性 note 当前
    可恢复地位于 Recently Deleted，永久清理和最终零匹配仍需要 action-time 明确批准

### 0.6.1：Notes 受保护写入

版本决策：0.6.0 保持为有界只读 Notes release；Notes 写入作为独立的 0.6.1 开发和发布。
在实现与 release gate 全部通过前，不修改源码版本号。

- [ ] 定义 fail-closed 写 contract 和稳定 write/read-back 状态
  - 所有 mutation 默认 `--dry-run`，只有 `--apply` 才持久化；返回
    `readback_confirmed` 或 `save_accepted_readback_pending`，Agent 不得自动重试后者
- [ ] 在一个显式 folder 中创建 note
  - 正文只接受 input file/stdin，不允许作为 CLI 参数进入 shell history；支持 plaintext 安全
    转义为 HTML 和显式 HTML，UTF-8 输入上限 256 KiB；拒绝未知字段、locked/shared target 和
    folder 歧义，并使用私有短期 idempotency receipt
- [ ] 使用乐观并发控制实现 note rename
  - 必须提供一个 opaque note ID 和预期 `modificationDate`；dry-run 只返回不泄露 title/body 的
    metadata diff；apply 只 save 一次并立即回读
- [ ] 使用显式目标 folder 实现 note move，并验证 identity
  - 必须提供一个 opaque destination folder；account scope 有歧义时 fail closed；验证移动后的
    note 以及 opaque ID 是否变化；绝不通过 folder title 猜测目标
- [ ] 现有 note 的 body replacement 不进入首个 0.6.1 release gate
  - 整体替换 HTML 可能破坏未支持的富内容和 attachment reference；以后必须单独实现 expected
    modification token、body hash preview、复杂内容拒绝和一次性 rich-note gate
- [ ] attachment mutation 和 note delete 不进入首个 0.6.1 release gate
  - attachment add/remove 需要独立的文件大小、本地文件、清理和回读规则；delete 只允许软删除，
    需要准确确认短语并记录 Recently Deleted 可见性；不支持永久删除或清空废纸篓
- [ ] 完成 synthetic TDD、CLI 负向 contract，以及一次性 iCloud
  create/rename/move/read-back/cleanup 集成 gate，并确认 active residue 为 0
- [ ] 只有全部 0.6.1 必做 gate 通过后，才更新 `notesLibrary` writable capability、help、README、
  usage、CHANGELOG 和版本 metadata

## 每个版本的横向完成条件

- [x] 提供 Terminal、标准输入和标准输出调用示例
- [x] 更新稳定的 Agent 调用 JSON contract
- [x] 定义统一退出码、错误格式和权限错误处理
- [x] 读操作输出结构化 JSON
- [x] 写操作支持 dry-run、差异预览和显式 apply
- [x] 显式请求时让重复执行保持幂等
- [x] 增加单元测试、fixture 和必要的集成测试
- [x] 在 macOS 26+ 测试（当前已在 macOS 26.4、Xcode 26.6、SDK 26.5 验证；
  更早的开发也在 macOS 27.0 运行过）
- [x] 更新 CLI 帮助、README 和对应 adapter 文档
- [x] 提供可复现的源码构建方式
- [x] 构建 0.2.0 Release 二进制并安装到本机 Homebrew prefix
- [ ] 发布已签名的 0.2.0 asset，并更新 Homebrew Cask

## 发布前加固 TODO

- [x] 增加进程级 CLI 测试：损坏 JSON、空 stdin、缺少参数、重复 external ID
  冲突，以及 container 参数组合（`scripts/run_cli_contract_tests.sh`）
- [x] 在明确授权后运行一次本机真实写入集成流程，覆盖 create、edit、头像、
  external ID migration、delete 和清理
  (`scripts/run_local_contacts_integration.sh --with-writes`)
- [x] 单独验证本机安装的二进制，而不仅是源码 Release build
  （`scripts/run_installed_release_smoke.sh`：0.2.0、V10 fast path、SQLite query backend）
- [ ] 发布 asset 后，在干净环境单独验证公开 Homebrew Cask
- [x] 使用一位明确授权的日文联系人完成 phonetic 字段 apply 和回读验证
  (`xvk-test-contacts-001`)

## 0.2.0 CTO 发布审计 TODO

以下项目是 `0.2.0` 正式公开发布前的审计清单。每项都必须记录目标范围、验证结果和
未解决限制；完成代码、测试和文档中的对应部分后，才可以勾选。除非特别注明，均只做
本机验证，不加入 CI，也不自动提交、推送或发布。

### 必须完成：发布阻塞项

- [x] **冻结 0.2.0 范围**
  - 目标：明确 Mail 仅提供只读能力；不支持发送、回复、移动、归档、删除、标记或账户修改。
  - 范围：CLI、README、`docs/usage*`、CHANGELOG 和帮助文本保持一致。
  - 验证：逐条检查命令表，确认不存在未文档化的写入路径；对未支持动作运行负向测试。

- [x] **完成版本一致性审计**
  - 目标：`VERSION`、CLI `--version`、`Info.plist`、CHANGELOG、公开 `v0.2.0`
    Release asset 和 Tap Formula 全部声明 `0.2.0`。
  - 验证：源码 Release、公开 Release asset、公开 Tap 和安装后 CLI 均已分别检查；
    本机 Homebrew CLI 已从旧版本升级并报告 `0.2.0`。

- [x] **完成完整本机测试矩阵**
  - 目标：验证 Swift 单元测试、CLI contract、Mail release gate、Mail Automation/GUI gate、
    Release build 和安装后 smoke。
  - 验证：87 个 Swift tests、CLI contract、两个 Mail release gate、独立 Release build
    和安装后 smoke 均通过；未忽略失败。未签名二进制执行前按已记录规则移除了本机 quarantine。

- [x] **确认 macOS 26+ 支持基线**
  - 目标：以 macOS 26.x 为正式支持基线；macOS 27 beta 仅作为前置兼容性测试。
  - 验证：已记录当前 macOS 27.0（`26A5388g`）、Xcode 26.6、SDK 26.5、Swift 6.3.3；
    macOS 26.4 的 Release 验证记录仍作为正式基线证据，当前 27.0 仅作为前置兼容性验证。

- [x] **完成 Mail 权限失败矩阵**
  - 目标：为 Full Disk Access、Mail Automation、Mail.app 未运行、同步中、数据库不可读
    分别提供稳定错误码和恢复提示。
  - 验证：已通过 doctor、metadata、release gate 和 GUI session Automation smoke；
    当前 FDA 为 `available`、Automation 为 `available`、V10 schema 为 `supported`。
    Mail.app 未运行和 `requires_consent` 路径也已观测并结构化返回；不读取邮件正文。

- [x] **未知 Mail schema 必须 fail closed**
  - 目标：只启用运行时明确识别的 schema；遇到未知 `V*` 版本必须拒绝快路径，不猜测字段。
  - 验证：`MailDoctorTests` 的 8 个专项测试全部通过，覆盖未知 schema、缺失结构、
    fallback 不可用和 `MAIL_SCHEMA_UNSUPPORTED` 错误映射。

- [x] **完成只读边界审计**
  - 目标：SQLite、WAL/SHM、EMLX、账户配置均不得被写入、移动、删除或修改。
  - 验证：代码审计确认 SQLite 使用 `SQLITE_OPEN_READONLY` 和 `query_only=ON`，
    EMLX 使用 `FileHandle(forReadingFrom:)`；本机 metadata smoke 前后
    Envelope Index/WAL/SHM 的 SHA-256 与 metadata 均未变化。

- [x] **锁定 JSON contract 与退出码**
  - 目标：固定 `contractVersion`、`backend`、`cacheState`、`complete`、`truncated`、
    `limitations`、错误码和退出码的语义。
  - 验证：CLI contract 文档与帮助一致；Swift contract、Mail doctor、fallback、
    timeout、stale opaque ID 和分页测试通过；本机进程检查确认成功 JSON 写 stdout，
    错误 JSON 写 stderr，查询返回退出码 0，stale ID 返回 4，未支持命令返回 64。

- [x] **统一账户 / 容器 / source 能力模型**
  - 目标：为 Contacts 的 iCloud container、Mail 的 account scope、Calendar 的
    EventKit source 定义统一的只读资源描述、稳定 opaque ID、显示名称、类型、能力和权限状态。
  - 个人选择策略：Contacts 默认选择个人 iCloud container；Calendar 默认选择个人 iCloud
    source；Mail 默认优先选择 `aim-tech.jp` 工作邮箱 account，不默认选择 iCloud Mail。
  - 范围：只统一 Core contract、能力声明和可验证的选择策略；不强行把这些 Apple 对象当成同一种
    对象，也不把 Apple ID、邮箱地址或内部 account identifier 写死在公共 contract 中。
  - 验证：每个 adapter 都能列出资源并标记 `readable` / `writable` / `selected` /
    `permission`；未知或不可用资源返回结构化错误；opaque ID 不暴露邮箱地址、账户 URL
    或内部数据库路径；当偏好资源不存在或有歧义时必须停止，不得静默切换到其他账户。
  - 当前本地实现：`macos-data resources --format json` 会列出已验证的 Contacts 容器和脱敏的
    Mail account scope。Calendar 不伪造资源，而是返回 `calendar_adapter_not_implemented`；
    在不泄露账号信息且尚未完成 `aim-tech.jp` 偏好验证前，Mail account 不标记为 selected。

- [x] **跨 adapter 统一分页协议**
  - 目标：让 Contacts、Mail、Calendar 使用一致的 `limit`、opaque `cursor`、`truncated`、
    `nextCursor`、`complete` 和结果上限语义，支持 Agent 分页处理和中断恢复。
  - 范围：先定义 Core contract，再由已有 Mail 和后续 Contacts/Calendar 命令逐步实现；cursor
    必须 backend-specific、不可由调用方解析，过期时返回结构化 stale cursor 错误。
  - 验证：合成 fixture 覆盖第一页、最后一页、重复 cursor、过期 cursor、结果上限和排序稳定性；
    不要求一次性把整个数据域加载到内存。
  - 当前已实现：Core `PagedResult` / `Pagination` 语义、Contacts `list` / `query` 分页、Mail
    统一的 `items` 字段，以及 stale cursor 的 fail-closed 校验。旧的 Mail `messages` 字段仍作为
    兼容别名保留；Mail.app fallback 明确不提供可恢复 cursor。
  - 验证：Core、Contacts、SQLite Mail 和 Mail.app fallback fixture 已覆盖第一页/最后一页、
    opaque cursor 往返、无效/过期 cursor、结果上限及 incomplete fallback 语义。

- [ ] **完成公开 Homebrew Cask 验证**
  - 目标：从公开 Tap 安装真实 `0.2.0` asset，确认 URL、SHA-256、解包目录和二进制路径。
  - 验证：在干净或隔离 Homebrew 环境运行 `brew update`、`brew install`、`--version`、`--help`。

- [x] **明确未签名二进制发布边界**
  - 目标：在没有 Apple Developer Program 的情况下，明确 Gatekeeper 警告、人工允许方式、
    SHA-256 校验和安全限制；不得宣称“安装后无额外操作”。
  - 验证：已在本机确认 Release binary 为 ad-hoc signature，`spctl --assess` 被拒绝；
    INSTALL 已记录先校验 SHA-256、不要全局关闭 Gatekeeper，以及 quarantine workaround
    不等同于签名 notarization。

### 可选完成：不阻塞 0.2.0

- [x] **正文全文搜索**：实现本地 EMLX 文本搜索，最多扫描 200 个候选、时间预算 1 秒，明确
  缓存缺失/截断等 limitation，不 fallback 到 Mail.app 或远程内容，并以 fixture 验证。
- [x] **附件导出**：实现 `attachments export --id <id> --output <directory>`，仅使用本地缓存
  EMLX，禁止自动覆盖和路径穿越，单个附件上限 20 MiB，并通过 MIME fixture 验证。
- [ ] **邮件写入能力**：另立版本设计发送、回复、移动、归档、删除和标记，不进入当前只读承诺。
- [ ] **更多 Mail schema 支持**：每增加一个 schema 必须有独立 fixture、运行时探测和 fail-closed 测试。
- [x] **线程/会话模型**：已确认当前 fixture 中 `conversation_id` 可作为显式关联字段，并实现只读
  `mail threads`；只聚合明确的正数 ID，不根据主题或参与者推断关系，thread ID 对外保持 opaque。
- [x] **性能与规模基准**：新增手动 5,000 条合成 SQLite metadata 记录 benchmark，使用 XCTest
  clock/memory metrics。该 benchmark 不进入 CI、不作为发布 gate；未来只能在相同硬件和工具链下比较数值。
- [x] **拒绝增量变更检测**：当前不引入 snapshot、change token、系统通知或额外 Agent 记忆层。
  默认采用直接、有限、可重复的当前状态查询；只有未来出现明确性能瓶颈或同步需求时，
  才重新评估增量模型，并要求单独的架构审计。
- [x] **拒绝 Intel Mac 支持**：项目正式定位为 Apple Silicon（arm64）only；不评估 Intel 构建、
  Rosetta 行为或 x86 Homebrew asset。未来若改变平台策略，必须单独进行架构设计和发布审计。
- [ ] **Agent 包装**：在 JSON contract 持续稳定后，再评估 MCP 或其他 Agent wrapper；不绑定单一 Agent 平台。

## 标准开发流程：TDD 到本机发布

每个新功能都应遵循以下顺序，不以“代码能编译”作为完成标准：

1. **明确行为**：先定义 CLI 命令、输入、输出、退出码、权限要求和失败行为。
2. **先写测试**：在对应的测试目录中先写预期行为；测试第一次运行应失败，证明测试确实覆盖了尚未实现的功能。
3. **最小实现**：只实现让测试通过所需的最小代码，并保持 Core、adapter 和 CLI 职责分离。
4. **自动测试**：运行 `swift test`，所有测试必须通过。
5. **CLI 构建验证**：运行 `swift run macos-data ...` 验证帮助、错误和成功路径。
6. **Release 构建**：运行 `swift build -c release`，确认发布配置可以编译。
7. **本机安装**：将 release 二进制安装到本机 Homebrew 前缀，例如 `/opt/homebrew/bin/macos-data`。
8. **安装后冒烟测试**：通过 PATH 直接运行安装后的 CLI，至少验证版本、帮助和本次新增功能。
9. **文档同步**：更新 README、路线图、命令示例和必要的权限说明。
10. **交付检查**：运行 `git diff --check`，确认测试结果、安装路径和工作区变更范围。

涉及系统权限的功能必须同时包含：

- 已授权路径测试
- 未授权或拒绝路径测试
- 真实本机权限检查
- 清晰的用户修复提示

测试应优先使用 mock 或合成 fixture，避免单元测试依赖本机联系人、邮件、日历等
真实数据；真实系统访问放在明确的 CLI 冒烟测试中。Mail fixture 绝不能从真实用户的
`Envelope Index` 或 `.emlx` 缓存复制。

### 本机 Contacts 集成测试 fixture

详细创建和恢复流程见：[Local Contacts Fixture](docs/development/local-contacts-fixture.md)。

当前本机已经创建两条专用测试联系人，分别覆盖个人和组织类型；后续测试不得重复创建：

```text
姓名：macos-data Test Contact
个人：`xvk-test-contacts-001`
组织：`xvk-test-organizations-001`
创建 smoke test：`org-create-apply-001`
URL 格式：`x-macos-data://external-id/<id>`

当前本机只发现一个名为 `iCloud` 的 Contacts 容器；创建 smoke test 已通过默认容器写入并读回验证，显式 `--container` 选择也已针对该容器完成验证。
```

标准验证命令：

```bash
macos-data contacts get --external-id xvk-test-contacts-001 --format json
macos-data contacts get --external-id xvk-test-organizations-001 --format json
macos-data contacts get --external-id org-create-apply-001 --format json
```

Computer Use 只允许用于首次创建或人工恢复这些 fixture。正常开发、测试、Release 构建和 CLI 冒烟测试都不得重新创建联系人。若 fixture 被删除、URL 或类型被修改，应先恢复，再继续测试。

## 长期方向

- [ ] 评估其他 Apple 公共 Framework，并记录 Framework 无法暴露 adapter 所需数据的情况
- [ ] 建立统一的 adapter 生命周期和能力声明
- [ ] 提供跨 adapter 的批处理能力（不包含当前已拒绝的增量变更检测）
- [x] 让 JSON contract 独立于 CLI 发布版本并提供稳定版本号

每个 adapter 都应独立定义：权限要求、domain model 映射、读取能力、写入能力、错误格式和测试策略。

## 暂不考虑

- GUI 自动化和屏幕坐标操作
- Apple 私有 API
- 写入 macOS 内部数据库；Mail adapter 仅允许文档化、可替换、严格只读的本地索引读取
- 云端上传或集中式联系人同步
- 内置 AI Agent
- 绑定单一 Agent 平台
- 将 Obsidian 作为公共数据协议的强制依赖

## 后续仍需细化的问题

- URL 中 `external_id` 的正式格式和保留 scheme
- iCloud 容器的识别方式，以及无法找到目标容器时的错误行为
- `metadata` 未能映射到 Contacts 时的 warning 格式
- 删除确认短语是否需要包含联系人名称或外部 ID
- macOS 26 与 macOS 27 之间的 API 和权限回归测试范围
