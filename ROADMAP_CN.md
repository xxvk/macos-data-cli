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
- [x] 完成稳定 App Automation 与一次性 note live gate
  - query、metadata-only get、plaintext、HTML 和零附件读取均已通过稳定 App；一次性 note 当前
    已在 action-time 明确批准后通过 Notes UI 永久删除，签名 app 最终标题查询确认零匹配

### 0.6.1：Notes 受保护写入

版本决策：0.6.0 保持为有界只读 Notes release；Notes 写入作为独立的 0.6.1 开发和发布。
全部必做实现与本机 release gate 通过后，才修改源码版本号。

- [x] 定义 fail-closed 写 contract 和稳定 write/read-back 状态
  - 所有 mutation 默认 `--dry-run`，只有 `--apply` 才持久化；返回
    `readback_confirmed`、`save_accepted_readback_pending` 或 `outcome_unknown`；后两者 Agent
    均不得自动重试
- [x] 在一个显式 folder 中创建 note
  - 正文只接受 input file/stdin，不允许作为 CLI 参数进入 shell history；支持 plaintext 安全
    转义为 HTML 和显式 HTML，UTF-8 输入上限 256 KiB；拒绝未知字段、locked/shared target 和
    folder 歧义，并使用私有短期 idempotency receipt
- [x] 使用乐观并发控制实现 note rename
  - 必须提供一个 opaque note ID 和预期 `modificationDate`；dry-run 只返回不泄露 title/body 的
    metadata diff；apply 只 save 一次并立即回读
- [x] 使用显式目标 folder 实现 note move，并验证 identity
  - 必须提供一个 opaque destination folder；account scope 有歧义时 fail closed；验证移动后的
    note 以及 opaque ID 是否变化；绝不通过 folder title 猜测目标
- [x] 现有 note 的 body replacement 不进入首个 0.6.1 release gate
  - 整体替换 HTML 可能破坏未支持的富内容和 attachment reference；以后必须单独实现 expected
    modification token、body hash preview、复杂内容拒绝和一次性 rich-note gate
- [x] attachment mutation 和 note delete 不进入首个 0.6.1 release gate
  - attachment add/remove 需要独立的文件大小、本地文件、清理和回读规则；delete 只允许软删除，
    需要准确确认短语并记录 Recently Deleted 可见性；不支持永久删除或清空废纸篓
- [x] 完成 synthetic TDD、CLI 负向 contract，以及一次性 iCloud
  create/rename/move/read-back/cleanup 集成 gate，并确认 active residue 为 0
  - 28 项 Notes test 与 204 项 Swift 总测试通过；CLI 负向 contract 覆盖缺失输入、未知字段、
    mode 冲突、缺失 ID 和绑定确认短语
  - 稳定签名 app 已在两个显式非 shared iCloud folder 中完成 create、rename、move 和立即回读。
    真实 gate 发现并修复生成脚本缺少换行以及 HTML 规范化导致的假 pending，并加入只编译测试与
    canonical plaintext hash 测试。经逐条核对，4 条测试 note 已通过 Notes UI 永久删除，原本的
    非测试 Recently Deleted note 被保留；签名 app 标题查询确认 fixture 为零匹配
- [x] 只有全部 0.6.1 必做 gate 通过后，才更新 `notesLibrary` writable capability、help、README、
  usage、CHANGELOG 和版本 metadata

### 0.6.2：Notes 正文与 folder 生命周期

版本决策：开发期间源码保持 0.6.1；全部必做测试、签名 app 真实 mutation gate 和清理验证通过后，
所有版本入口已统一更新为 0.6.2。

当前前向兼容基线：Xcode 27.0 Beta 5（`27A5237l`）、Swift 6.4、macOS SDK 27.0 已完成
Release/debug app 编译并通过全部 222 个 Swift tests。标准测试使用
`scripts/run_swift_tests.sh`，避免在本 iCloud/File Provider checkout 内生成 XCTest bundle。

- [x] 受保护地替换已有 Note 正文
  - 新增独立 `notes edit-body` 命令，不把正文修改混入 `rename`
  - 只接受 file/stdin strict JSON，字段包括 `bodyFormat`、`body`、
    `expectedModificationDate` 和 `expectedBodySHA256`
  - 保持 256 KiB 输入上限、默认 dry-run、显式 apply、只输出 hash/byte 数、串行 Apple Events
    和立即回读状态
  - 拒绝 shared、password-protected、含 attachment 或未支持富内容结构的 note；首版只替换能够
    证明属于受支持 plaintext/HTML 子集的正文，不承诺无损修改 checklist、table、drawing、scan
    或 collaboration 内容
  - 实现、strict CLI 解析、生成脚本编译、dry-run 零写入证明、hash/并发检查、attachment/富内容
    拒绝、timeout 和 synthetic 回读测试已完成；32 项 Notes test、208 项 Swift 总测试、CLI
    no-apply contract 和 release build 均通过。一次性签名 app gate 已在两个显式非 shared iCloud
    folder 间完成 create、正文修改、hash 回读确认、rename 和 move。取得 action-time 确认后，
    只永久删除该 fixture，保留无关 Recently Deleted note；最终签名 app sentinel 查询为零匹配
  - 首次 gate 在 mutation 前安全停止，因为 wrapper 的 8 秒输出等待短于 Notes 与 LaunchServices
    启动耗时；回读证明原正文未变化。wrapper 曾改为 20 秒；Xcode 27 app 的启动/输出又超过该上限，
    因此现改为最多等待 40 秒并报告准确 stage，Apple Event deadline 仍保持 5 秒
- [x] 创建、重命名 Notes folder，并重新评估 move
  - 只允许在本机已绑定的 iCloud account 内操作；parent 和 destination 必须使用 opaque folder
    ID，绝不通过显示名称推断 folder
  - 只接受 file/stdin strict JSON，默认 dry-run、显式 apply、立即回读并保持隐私安全输出；create
    使用短期 idempotency receipt，并拒绝无法判断的重复创建结果
  - 实现前先验证 Notes 4.13 scripting dictionary 对嵌套 create/rename/move、identity 变化、shared
    folder、同名 folder，以及移动到自身或子孙节点的实际行为；无法提供稳定前置条件或回读时
    fail closed
  - create/rename 实现、strict JSON、隐私安全输出、名称 hash/current parent 前置条件、default/shared/跨账户/重名/
    cycle 拒绝、idempotency receipt、timeout 状态、生成脚本编译、定向 Store test 和 CLI no-apply
    contract 已完成
  - 签名 app gate 已证明 nested create、重名拒绝、rename、hash 回读和清理。Notes 4.13 folder move
    无法保持可确认 identity：空 child 从可枚举图中消失，metadata 暂时失效。apply 现使用
    `NOTES_FOLDER_MOVE_UNSUPPORTED` 禁用；未来 move 必须采用新设计和独立 gate，不得重试当前公开
    AppleScript 命令
  - live gate 还发现 account-level folder 枚举与递归组合时会产生重复 scripting ID。discovery 现只从
    真正 root folder 开始，并验证 graph 唯一性；异常时 fail closed，不再触发 Swift fatal crash
  - 取得明确清理授权后，三个一次性 folder 已通过 Notes UI 永久删除。最终签名 app 查询返回
    `complete=true`，三个 opaque ID 均为零匹配，`macos-data-folder-gate-*` sentinel 也为零匹配
- [x] 评估受保护空 folder 删除并 fail closed
  - 只删除绑定账户中显式选择的非 shared、非 default 空 folder；含 note、含子 folder 或要求
    recursive delete 时一律拒绝
  - 必须使用 `--apply`、准确确认短语 `DELETE EMPTY NOTES FOLDER`、删除前重新检查为空，并在
    删除后回读确认不存在；不提供永久清空废纸篓
  - preview 实现与 synthetic TDD 已覆盖 strict parent/name-hash 输入、非递归 note/child 拒绝、
    稳定错误 `NOTES_FOLDER_NOT_EMPTY`、CLI negative contract 和隐私安全输出
  - 签名 app apply gate 删除 renamed child 后导致 metadata graph 失效；重启 Notes 后，child 以旧名称
    和新的 opaque ID 再次出现。短时间消失无法证明 iCloud 持久删除
  - apply 现于任何写 Apple Event 前返回 `NOTES_FOLDER_DELETE_UNSUPPORTED`。未来启用必须采用不同
    的公开机制并重新执行独立 gate
  - 取得 action-time 明确确认后，三个一次性 fixture 已通过 Notes UI 按叶节点优先删除。重启后
    签名 app 查询返回 `complete=true`，删除前后四个已知 opaque ID 均为零匹配，
    `macos-data-folder-gate-*` sentinel 也为零匹配
- [x] 受保护地删除单条 Note
  - 只实现可恢复的 soft delete，目标是 Notes Recently Deleted；不提供永久删除或清空废纸篓
  - 必须提供 opaque note ID、`expectedModificationDate`、`--apply` 和准确确认短语
    `DELETE NOTE`；拒绝 shared/locked note，并确认 note 已从原 active folder 消失
  - 无法证明 Recently Deleted 状态时返回明确 pending/unknown 与 `nextAction`，禁止 Agent 自动重试
  - 实现与 synthetic TDD 已完成：strict modification-date JSON、mutation 前直接回读、shared/locked/
    stale 拒绝、准确 `DELETE NOTE` 确认、隐私安全输出、生成脚本编译、timeout unknown 和 no-apply
    CLI contract 均通过
  - 经授权的签名 app gate 已完成 create、正文修改、rename 和 move。wrapper 在等待 move 输出 20 秒后
    停止，因此没有重试；只读 get 证明 move 已实际成功。流程从该确认状态继续，只执行一次 dry-run
    与一次 delete apply，返回 `readback_confirmed`、原 folder 零匹配和另一 system-managed folder
    一条可恢复匹配。取得 action-time 明确确认后，仅通过 Notes UI 永久删除该 fixture，保留一条
    无关的 Recently Deleted note；最终签名 app sentinel 查询返回 `complete=true` 且零匹配
- [x] 完成 0.6.2 TDD、签名 app 集成和清理 gate
  - 最终 synthetic 基线为 222 个 Swift tests 与 CLI no-apply contracts 全部通过，覆盖 strict JSON、
    并发/hash 冲突、富内容拒绝、folder cycle 防护、非空 folder 删除拒绝、确认
    短语、timeout unknown、safe no-op 和诊断脱敏
  - 一次性 simple/rich note 与隔离嵌套 folder tree 已验证正文修改、folder create/rename、move 和
    folder-delete fail closed、note soft delete；经 action-time 确认的 UI 清理保留无关 Recently
    Deleted 数据，最终签名 app sentinel 查询均为零匹配
  - 最终本机 release gate 已通过版本一致性、Release/签名 debug 构建、CLI/Calendar contracts、Mail
    只读 smoke 与 `git diff --check`。本机当前有两个符合条件的 iCloud Calendar source，因此 Calendar
    live smoke 验证稳定歧义错误后跳过，未擅自选择账户
  - 全部 gate 通过后，help、README、usage、架构文档、CHANGELOG、capability 与所有版本入口才统一
    更新为 0.6.2

### 0.7.0：Shortcuts 稳定运行与组织能力

版本边界：只使用 `/usr/bin/shortcuts`、Shortcuts URL scheme 和公开的
`Shortcuts Events` scripting dictionary；不读取或修改 Shortcuts 私有数据库，也不编辑动作图。

- [x] 实现 `shortcuts list` 与 `shortcuts get`
  - 返回 opaque shortcut ID、名称、folder、subtitle、颜色、图标、是否接受输入和 action count；
    不把名称作为稳定身份，不声称能够读取动作或参数
  - 支持有界分页、稳定排序、strict JSON、结构化 Automation/Shortcuts helper 错误和隐私安全日志
  - Shortcuts synthetic tests 中的 metadata/opaque ID/pagination 项已通过；真实只读 gate 返回
    2 个 shortcut、6 个 folder、`complete=true`，单条 opaque-ID get 通过且未输出用户字段
- [x] 实现 `shortcuts run`
  - 支持明确选择的 shortcut ID、文件或 stdin 输入以及有界输出；交互式 prompt shortcut 必须明确
    标记为不适合无人值守 Agent 调用
  - 定义 deadline、取消、输出大小上限，以及 `outcome_unknown` 时禁止自动重试的规则
  - opaque-ID system CLI bridge、最多 16 个 input、1～300 秒 deadline、256 KiB inline UTF-8、
    no-overwrite file output、SHA-256 与准确确认短语已实现并通过 synthetic/negative contract。
    一次性真实 fixture 返回准确的 28-byte plaintext sentinel 并验证 SHA-256；plaintext 从系统
    CLI 的 stdout 捕获，因为该文本结果不适用 `--output-path`
- [x] 实现 `shortcuts folders` 与 `shortcuts move`
  - folder discovery 返回 opaque ID；move 只能使用 shortcut ID 和 destination folder ID，禁止按名称猜测
  - move 默认 dry-run，apply 前重新读取 source/destination，写后验证 folder identity；相同 folder 为安全 no-op
  - folder discovery、filter-bound pagination、move preview/no-op、raw-ID mutation bridge 与即时 read-back
    已实现；真实 fixture 已通过 preview、apply/read-back、destination get、恢复与最终 source-folder get
- [x] 完成 synthetic TDD、CLI negative contract 和一次性真实 gate
  - 覆盖 helper 不可用、Automation 拒绝、stale ID、同名 shortcut、超时、输出截断和日志脱敏
  - 使用专用 fixture 验证 list/get/run/move/read-back，并在测试后恢复原 folder；不执行用户现有 shortcut
  - 已使用一个专用两动作文本 fixture 与两个明确测试 folder 完成；清理后 fixture shortcut/folder 均为
    0，原有 2 个 shortcut、6 个 folder 恢复且 `complete=true`
  - 冷启动回归允许实际 bridge 启动按需运行的 Shortcuts Events helper，避免在 Apple Event 发送前
    因 helper 空闲未运行而错误拒绝正常命令
  - 0.7.0 release gate 已通过版本一致性、全量 Swift suite、Release/签名 Debug build、共享
    CLI/Calendar contracts，以及 Mail doctor/metadata/content/attachment smoke。本机存在多个匹配的
    iCloud Calendar source，因此 Calendar live smoke 保持稳定 fail-closed，未执行 Calendar 写入
  - 与 Release byte-identical 的 candidate 已并行安装为
    `/opt/homebrew/bin/macos-data-0.7.0-rc`，未覆盖 Homebrew 管理的 0.6.2 canonical command。
    最终组合 gate 以 `installedSmoke=true` 通过，覆盖 0.7.0 版本、Calendar/Shortcuts contracts 和
    Mail SQLite fast path；canonical Homebrew symlink 等待单独授权的公开发布后再切换

### 0.7.1：Cherri 受管理源码 authoring

版本边界：只创建和更新以 `.cherri` 源码作为 SSOT、由 macos-data registry 管理的 shortcut。
Cherri 作为可选外部编译器调用，不复制其 GPL-2.0 源码；Apple 未公开的 Shortcut 文件格式必须明确
标记为 experimental，并为每个受支持 macOS/Shortcuts 版本设置兼容性 gate。

- [x] 实现 `shortcuts author validate` 与 `shortcuts author build`
  - validate 检查 Cherri 可用性、源码大小、允许的 include/package、敏感值规则和目标 action 定义
  - build 在私有临时目录生成 `.shortcut`，使用系统 `shortcuts sign`，返回 source/compiled SHA-256、
    action count 和签名模式，不输出源码、参数或 secret
  - Cherri 2.3.0 validate/build 与系统签名已在 macOS 27 Beta 5 通过；非导入 gate 还验证
    `0600`、拒绝覆盖和结果脱敏。只复制源码字节可避免继承 `com.apple.provenance` 导致签名器拒绝
- [x] 实现受保护的 `shortcuts create`
  - 默认 dry-run；apply 需要准确确认短语，并通过 Shortcuts.app 完成可见导入
  - 使用短期 idempotency receipt；导入后按 opaque ID、名称、action count 和显式 smoke input/output 回读
  - runtime、receipt、确认、dry-run、脱敏、registry、可见导入和准确黑盒 sentinel 输出均已通过
- [x] 实现受保护的 `shortcuts update`
  - 只接受 registry 中已有的 managed shortcut，要求 expected source hash，禁止把任意用户 shortcut
    静默纳入管理
  - Apple 没有公开原地动作图替换 API，因此首版采用“编译候选版本 -> 导入 -> 验证 -> 明确确认替换/保留旧版”；
    失败时保留旧版，禁止先删后装
  - managed-only 并发保护、retain-old 打包、禁止自动重试和 registry identity 原子替换已通过；
    macOS 27 Beta 5 出现 public/compiled count 不一致时，replace 保持 fail closed
- [x] 建立私有本机 registry 和完整 gate
  - registry 只保存 opaque shortcut ID、source/compiled hash、action count、版本和时间；权限为目录 `0700`、
    文件 `0600`、原子写入，不保存动作参数、源码、Token 或其他 secret
  - registry 实现及 `0700`/`0600`、原子写入、字段校验、脱敏、managed-list 和只清 registry 的 forget
    测试已完成
  - disposable fixture 覆盖 validate、build、sign、import、运行、源码修改、再次导入、回读和清理；
    macOS/Shortcuts 大版本变化时必须重新执行
  - macOS 27 Beta 5 + Cherri 2.3.0 gate 已通过 create、准确 sentinel 运行、retain-old update、
    第二次准确运行、语义化 UI 清理和 fixture/registry 零残留。两个可运行导入的 Shortcuts Events
    count 都是 `0`，因此编译 count 与 observed count 保持独立字段

### 0.7.2：任意现有 Shortcut 的实验性编辑

版本边界：目标是修改不是由 macos-data 创建的现有 shortcut。Apple 当前没有公开动作图 CRUD API，
因此本版本只能在明确 `experimental`、显式授权和 fail-closed 条件下实现，不承诺跨系统版本稳定。

- [x] 完成现有 Shortcut 的本地安全采集与能力分级
  - `shortcuts edit inspect --input <local.cherri|local.shortcut>` 仅读取用户显式提供的单个本地
    non-symlink regular file，通过 `O_NOFOLLOW` 防止跟随链接，输入上限 10 MiB，只返回 SHA-256、
    字节/count metadata、风险 flag 与稳定 capability/reason enum
  - signed file 无法可靠反编译、未知 action、device-bound reference、secret 或未支持结构必须拒绝或要求
    用户在 Shortcuts.app 中手工迁移，不访问 SQLite/CloudKit/private framework
  - 12 个定向测试与 process-level no-apply CLI contract 已覆盖有限 unsigned input、opaque input、
    Cherri route、脱敏、symlink、大小、未知 action、secret、device-bound reference，以及 magic variable/
    附件等嵌套结构；classification 本身不授权 semantic apply
- [x] 增加脱敏的 action-level edit-plan contract
  - `shortcuts edit plan` 要求准确 input SHA-256 与 strict JSON，在内存 shadow graph 中验证最多 64 个
    顺序执行的 insert-text、replace-text、delete-action、move-action
  - 8 个定向测试及 process-level contract 覆盖严格字段、并发冲突、边界、action 类型安全、脱敏和输入
    零修改；不存在可到达的 apply、Apple Event、Accessibility event 或 artifact 输出
- [x] 单独评估 iCloud share-link acquisition，并在 0.7.2 保持禁用
  - Apple 文档说明，创建 iCloud link 会把 Shortcut 副本交给 Apple 验证并通过 iCloud 提供链接；接收
    链接仍是可见 Get Shortcut/import 流程，不是公开 headless graph API
  - 0.7.2 只接受显式本地 `.cherri`/`.shortcut` path，不请求或下载 share link，不跟随 redirect、不读取
    clipboard，也不触发 import
  - reader 现在强制 `isFileURL`；红绿测试证明即使 HTTPS URL 的 path 映射真实本地 fixture，也会在读取前
    拒绝。CLI 同时拒绝 URI syntax，且错误输出不回显输入 link
  - 只有未来具备独立 opt-in command、action-time 隐私确认、有界下载、redirect/domain policy 与单独
    visible-import contract 后，才重新考虑
- [x] 增加有界、只读的语义 Accessibility discovery
  - 仅按 AX role、identifier、label 和结构定位控件，禁止屏幕坐标、图像匹配和无界点击
  - `shortcuts edit ui-inspect` 不弹授权、不启动或激活 Shortcuts.app，遍历上限 2,000 节点/深度 32，
    只返回 count；generic、ambiguous 或 unbounded tree 全部 fail closed
  - 8 个 synthetic test 与 no-apply CLI contract 证明零 action API、permission/target 状态、歧义、边界、
    semantic marker 要求及 label/title/identifier 脱敏；discovery 本身不授权 semantic apply
- [x] 使用 disposable macOS 27 Beta 5 fixture 验证只读 AX discovery
  - 首次真实运行因 Shortcuts 27 使用 `editor.shortcutname` 作为 editor marker 而安全返回 no-candidate；
    先用红灯测试固化兼容性缺口，再把这一准确 normalized marker 加入 allowlist
  - 校准后在 2 个窗口/373 节点中只返回 1 个有界 editor candidate，JSON 不包含 label、title、identifier
    或 action text；语义 UI 删除后，唯一名称搜索为 No Results，CLI 在 1 窗口/139 节点中返回 0 candidate
- [x] 在 macOS 27 Beta 5 校准准确 Text/Comment semantic element
  - 第二个仅限本地的 fixture 确认唯一 `editor.shortcutname` field、外层 action canvas、直接
    Text/Comment title、Close button、嵌套 scroll area，以及每个支持 action 唯一可写 text area
  - 纯 semantic resolver 忽略独立的 action-library scroll area，对所有私有 value 取 hash，并在未知
    action、field 结构异常、candidate 歧义或遍历越界时 fail closed；4 个定向测试覆盖该 graph
  - 只读 menu 检查记录 `duplicateShortcut:`、`duplicateAction:`、`rearrangeItemUp:`、
    `rearrangeItemDown:`、`insertCommentAction:`，仅作为当前版本证据；没有调用 action，cleanup 后 library
    数量恢复且准确名称为零匹配
- [x] 设计受保护的语义 Accessibility mutation
  - 纯 coordinator 消费已实现的 action-level edit plan，在读取 editor 前要求准确
    `EDIT SHORTCUT COPY` 确认，并在创建 recovery object 前预演整份 operation sequence
  - mutation 采用 copy-first：恢复候选必须具有不同的 hashed identity，并与原对象的初始 semantic graph
    完全一致；每一步都准确回读，错误或不一致返回 `outcome_unknown`、保留原对象并禁止自动重试
  - strict patch parse 现在同时产生 public plan 与不可 Codable、debug 强制脱敏的内存 execution plan；
    coordinator 在读取 AX 状态前核对每个 private text 的字节数与 SHA-256，仅有 summary 永远不能执行。
    edit-plan 与 coordinator 当前分别有 10 和 11 个定向测试
  - plan-bound guarded bridge 只暴露 inspect、duplicate、insert/replace text、delete、move session 方法；
    强制 recovery-first 与准确 sequence，拒绝 altered/extra operation，session mutation error 后永久 poisoned，
    并由 5 个定向测试覆盖
  - 当前仍没有通用 AX action API；公开 apply 仅限下面单独 gate 的 replace-text copy 路径
- [x] 通过首次具体 copy-first `replace_text` gate
  - system session 只允许准确 `duplicateShortcut:` 与 Text-area value replacement；insert/delete/move 固定
    禁用。5 个定向测试覆盖该 session 和经过确认的 existing-copy recovery
  - 有界 driver 只读取 toolbar name 与 action canvas，只选择唯一 main/focused editor，并设置 5 秒 AX deadline
  - macOS 27 Beta 5 fixture 证明副本 identity、graph 相同、replacement hash 回读、Comment 不变和原件不变；
    两窗口 fail-closed 后只恢复已验证副本，没有再次 duplicate
  - 两个 fixture 在单独永久删除确认后清理；library 从 4 恢复到 2，准确名称搜索为 No Results
  - fixture harness 仅限 debug，不属于公开 recovery interface
- [x] 通过受保护 CLI contract 开放已证明的 copy-first `replace_text`
  - `shortcuts edit copy` 要求一个本地 artifact、一个 strict patch、准确可见 editor 名称 SHA-256，且
    dry-run/apply 必须二选一
  - dry-run 在构造 system AX bridge 前返回；apply 必须在构造 bridge 前准确确认
    `EDIT SHORTCUT COPY`
  - 该 gate 最初只开放全为 replace-text 的 plan；下方末尾 insert gate 随后扩展同一 contract。其他
    insert/delete/move 在 mutation 前返回稳定 unsupported-capability error
  - 6 个 service test 与 process-level CLI contract 覆盖 preview 隔离、确认、hash/mode 校验、unsupported
    operation 拒绝与输出脱敏；本次接线没有额外创建真实 fixture
- [x] 证明并开放 verified copy 上的末尾 `insert_text`
  - 唯一开放的 insert index 是当前 action count，且 graph 必须已有 resolver 批准的 Text action；中间插入
    或无 Text graph 插入均在 mutation 前 fail closed
  - 有界 driver 只聚焦该已知 Text field，并调用 Edit menu 的准确 `duplicateAction:` identifier；确认只有一个
    duplicate 追加到末尾后，只修改新增 value，再回读完整 semantic graph
  - macOS 27 Beta 5 fixture 证明 Text + Comment 只在副本中变成 Text + Comment + Text，原件保持不变；结果为
    `readback_confirmed`，3 个 action 全部验证，JSON 不含 private value
  - delete gate、stale-read-back recovery 与 mixed-family guard 使 ShortcutsTests 达到 105/105；定向覆盖包括
    12 acquisition、13 edit-plan、11 coordinator、7 service、5 guarded-bridge、4 resolver 与 9 system-session tests
  - 取得单独确认后，两个 fixture 均通过 Shortcuts UI 删除；All Shortcuts 从 4 恢复为 2，两个准确名称
    搜索均返回 No Results
- [x] 使用 disposable fixture 证明并开放 copy-first `delete_action`
  - synthetic 实现为每个支持 action 精确解析唯一 `Close` AXButton，拒绝会清空 graph 的删除，只按绑定 path
    执行 press，并由 coordinator 回读完整删除后 graph
  - plan、public dry-run 与 guarded apply 已接线并保持脱敏；apply 只接受删除后至少保留一个 action 的全 delete plan
  - debug-only `copy-delete` harness 已准备，可验证 Text + Comment 只在副本中变为 Text，原件保持不变
  - [x] 经授权的 macOS 27 Beta 5 Text + Comment fixture 已证明：只有副本丢失 Comment，副本回读为一个
    未变化的 Text action，原件回读仍为原始 Text + Comment graph
  - [x] 首次删除后回读暴露真实 stale-graph 时间窗。命令 fail closed 且未重试；只读 existing-copy recovery
    确认 mutation，新增 red/green test 要求 delete 等待准确缩小后的 graph 稳定
  - [x] 两个 fixture 对象已从 All Shortcuts 移除；数量从 4 恢复为 2，准确名称搜索为 No Results
  - [x] 第二个 disposable fixture 在单次命令中通过修正后的不中断 gate，随后原件验证也通过
  - [x] 取得明确永久删除确认后，第二次 gate 的两个对象均已删除；All Shortcuts 从 4 恢复为 2，准确名称
    搜索为 No Results
- [x] 通过经过验证的副本支持受限的现有对象修改
  - [x] 使用一次性 Text + Comment fixture 证明 copy-first `move_action`：复制后通过准确的
    `rearrangeItemUp:` 将 Comment 从 index 1 移到 index 0，回读 Comment + Text，再独立确认原件仍为
    Text + Comment。真实 gate 暴露普通 `AXChildren` 顺序滞后；现以闭集验证的
    `AXChildrenInNavigationOrder` 和左上角坐标 Y 顺序回读完整视觉 graph。副本与未变原件均通过 hash-bound
    回读，public 全 move apply 已开放
  - [x] 取得单独 action-time 确认后永久删除 move 原件与恢复副本；All Shortcuts 从 4 恢复为 2，两个准确
    名称搜索均返回 No Results
  - 后续 allowlist 覆盖已验证 action 的删除、移动、更多位置插入和参数替换；控制流、magic variable、第三方 action
    和 device-bound reference 必须分别通过 fixture 后才能启用
  - 使用 shortcut ID、expected action count 和可获取的 metadata 作为并发保护；因公开接口无法读取完整动作图，
    不得宣称具备完整事务或无损 round trip
  - 重新评估“原地修改”表述：已批准的 coordinator 只编辑经过验证的副本并保留原对象；除非以后能证明
    rollback，否则继续禁止直接修改原对象
- [x] 完成 0.7.2 surface 在 macOS 27 Beta 5 上的 UI fixture 与恢复 gate
  - disposable fixture 已证明 copy-first replace-text、末尾 insert、有界 delete 与有界全 move，并保持原件不变
  - 每次 apply 都创建或恢复不同 identity 的已验证副本，回读完整受支持 semantic graph；无法证明结果时返回
    `outcome_unknown` 且禁止自动重试
  - 所有 disposable fixture 均在取得单独 action-time 确认后永久删除，准确名称搜索为 No Results
- [ ] 未来声明支持新的 macOS/Shortcuts 版本前，重新运行该版本的 semantic fixture gate；0.7.2 不承诺跨版本稳定

### 0.8.0：Safari 书签与阅读列表

架构文档：[Safari adapter 0.8](docs/development/safari-adapter-architecture_CN.md)。

- [x] 在不修改数据的前提下审计 Safari 27 公开接口和本机存储
  - Safari scripting dictionary 只公开 Reading List 新增，不提供 bookmark CRUD，
    也不提供 Reading List read/update/delete
  - 本机主数据是 `~/Library/Safari/Bookmarks.plist`，不是所检查的 Safari SQLite
- [x] 实现有界、严格只读的 bookmark 与 Reading List snapshot
  - Foundation parser 支持 binary/XML plist，限制 32 MiB、50,000 nodes、depth 64，
    schema 异常一律 fail closed
  - 原始 UUID 转为 hash opaque ID；普通 bookmark 不混入 proxy/Reading List；
    URL、title、preview、UUID、path 不进入 diagnostics
  - query 使用 AND 语义、最大 200 分页；cursor 绑定 filter 与准确 plist SHA-256，
    Safari 状态变化后旧 cursor 必须 stale
- [x] 增加 `safari permission`、bookmark list/query/get、Reading List
  list/query/get，使用共享 JSON contract 和 exit 10
- [x] 实现受保护 Reading List add
  - 严格 stdin/file JSON、仅 HTTP/HTTPS、有界 title/preview、显式 dry-run/apply、
    标准化 URL no-op、五秒 Safari Apple Event、立即 plist 回读，以及 pending/unknown
    禁止自动重试
  - AppleScript 已通过 compile-only 检查；尚未写入真实项目
- [x] synthetic TDD、no-apply CLI contract、真实 Safari list/get 与 add dry-run
  隐私 smoke 均通过；私有临时 JSON 已删除
- [x] 为稳定 Debug app 请求 Safari Automation，并在另行明确授权后执行一次性
  Reading List add/read-back/UI cleanup gate
  - Apple Event 返回 `save_accepted_readback_pending`，CLI 未重试；随后按准确 URL query
    找到唯一 opaque Reading List item
  - 取得单独 action-time 确认后，Safari UI 只删除精确筛选的 fixture；UI 搜索和准确 URL
    CLI query 最终均为零匹配
- [x] 运行完整 Swift、Release/no-apply gate 和文档审计
- [x] 全部本机 gate 通过后把源码版本从 0.7.2 更新为 0.8.0；commit/push/tag/release
  仍需单独授权

### 0.8.1：Safari 本地书签修改

原先分别编号为 0.8.1 可行性、0.8.2 安全引擎和 0.8.3 CRUD 的开发里程碑，统一合并到
公开的 0.8.1 源码版本。历史 gate 名称继续作为证据保留；正式 contract 是受保护的
local-only CLI，绝不暗示 iCloud 同步。

- [x] 在 synthetic fixture 与真实 plist 的自动删除私有副本上证明语义 round trip
  - 未知 plist 值、Children 顺序、mode、owner、group 和源 xattr 的每个值均保留；
    symlink、覆盖、重复 UUID、未知节点类型和目标 ancestry 之外的变化一律 fail closed
  - Foundation 重新序列化后真实 binary plist 并非 byte-identical（914,933 变为
    914,917 bytes），因此安全判据改为所有未触碰 subtree 的类型化 canonical hash，
    不能使用整个文件字节相等
  - 测试 carrier 重写私有副本时 macOS 会额外附加 `com.apple.provenance`；必须显式报告，
    任何其他新增 xattr 都会失败。真实源文件保持 byte-for-byte 不变
- [x] 实现并完成本机有人值守的 quiescence/backup gate 审计
  - Safari app 正在运行或任意进程持有准确 plist 时拒绝继续；间隔 500 ms 的两次 snapshot
    必须具有相同 device、inode、size、mtime、mode、owner、group、SHA-256 和 xattr-value hash
  - 在 mode 0700 目录创建准确 recovery copy 与隐私安全 JSON manifest，两份文件均为 0600；
    随后再次检查 quiescence 和完全相同的第三次 source snapshot，失败时自动清理不完整 artifact
  - 真实只读审计在 Safari 已退出、无打开句柄时通过：0600 recovery 数据准确、源文件不变，
    临时 recovery 目录已自动删除。另行授权 mutation 前必须立即重新执行，旧 gate 结果不能复用
- [x] 执行一次有人值守的 disposable bookmark 原子写入，并通过 Safari UI 与 0.8 parser
  回读 fixture
  - 真实写入前 TDD 已完成：writer 拒绝 stale/tampered recovery，创建同目录 candidate，
    重新写入准确 source xattr value，使用 `RENAME_SWAP`，同时验证新旧两侧，并在任意
    read-back 失败时 swap-back
  - 在真实 Safari schema 的自动删除副本中，已向唯一内建 `BookmarksBar` 准确新增一个
    bookmark；206 个未触碰 subtree 的 canonical hash 保持不变，真实源文件未变化
  - session `3f6c5b6f-aa0c-4a21-98e8-fe66c578a781` 只新增一个 fixture；Safari UI 与
    公开 CLI 均能找到，0600 recovery 仍完整保留
  - Reading List 从 89 条变为 0 是用户另行手动删除，不是 fixture 写入造成；该变化不计入
    mutation 安全结论
- [x] 在第二台 iCloud 设备验证并记录 fixture **未出现**；直接替换 plist 只证明本机写入，
  不会生成 Safari 私有的 iCloud change transaction
- [ ] 通过 Safari 自己的路线只删除 fixture，并在两台设备证明消失；不得出现 duplicate、
  resurrection、旧节点丢失、schema drift 或 sync error
- [x] 给出拆分结论：**本机 local-only 可行，iCloud sync 不可行**。不得宣称跨设备持久化，
  也不得把重启私有 sync daemon 当成受支持的同步按钮
- [x] 在开放 direct-plist 写命令前增加明确 local-only contract 与警告：
  `syncStatus=local_only`、保留 recovery，并用 `nextAction` 提示若要 iCloud 副本必须走
  Safari-owned import

#### 已合并到 0.8.1 的内部安全引擎里程碑

- [x] 将受保护 direct-plist 基础能力产品化为明确的 local-only mutation engine，绝不暗示更新 iCloud
  - Apache-2.0 `safari-bookmarks-mcp` 中值得参考的 contract 设计与本地 CRUD 细节，统一移入下面的
    0.8.3
  - 不采用其较弱的 persistence 路线；macos-data 必须保留 Safari 退出/open-handle gate、乐观
    source identity/hash、metadata/xattr 保留、fsync、rollback、私有 recovery 与真实 read-back
- [x] 向 Safari adapter 提供可复用 prepare/apply/read-back/rollback primitive、隐私安全 receipt，
  以及稳定的 local-only result/error code
- [x] 完成 synthetic 与真实 plist 私有副本 TDD：stale source、并发变化、中断写入、rollback failure、
  metadata drift 与安全 no-op

#### 已合并到 0.8.1 的内部 CRUD 里程碑

- [x] 参考 Apache-2.0
  [`chikingsley/safari-bookmarks-mcp`](https://github.com/chikingsley/safari-bookmarks-mcp)
  中有价值的 **contract 概念**，由 macos-data 独立实现，不复制其 persistence 实现
  - 现有节点使用 opaque UUID 定位；放置位置必须显式提供 parent UUID 与 child index。
    人类可读 path 只用于发现和 dry-run 展示，不得作为可能歧义的写入 identity
  - 为 bookmark add/edit/move/remove 与 folder create/rename/move/remove 定义严格 JSON；
    未知字段、重复 UUID、非法 index、父节点不存在、修改 root、bookmark/folder 类型不符一律拒绝
  - 拒绝把 folder 移入自身或 descendant；非空 folder 默认禁止删除。若未来提供 recursive delete，
    必须是独立操作并要求准确的破坏性确认短语
  - 所有 mutation 默认 dry-run；`--apply` 必须携带当前 source identity/hash token，并返回变化节点与
    parent 的 opaque ID，同时明确输出 `syncStatus=local_only`、iCloud limitation 和 `nextAction`
- [x] 保留 macos-data 更强的 persistence/privacy gate，不采用参考项目的普通 read-modify-write
  - 要求 Safari 完全退出、无 open handle、连续稳定 snapshot、乐观 source identity/hash、私有
    `0700` recovery、`0600` backup/receipt、准确保留 metadata/xattr、同目录 atomic swap、fsync、
    有界 read-back、rollback 和诊断脱敏
  - 未知 plist 字段及未触碰 subtree 的顺序/hash 必须保留；selected ancestry 之外发生变化时 fail closed
- [x] 使用 TDD 和分阶段证据实现
  - unit fixture 覆盖所有 CRUD、path/UUID 解析、cycle/recursive-delete 拒绝、strict JSON、stale token、
    no-op、rollback、schema drift 与隐私安全 diagnostics
  - [x] 已在真实 plist 的私有副本完成 bookmark create → edit → move → remove，以及 folder create →
    rename → move → empty-delete，并证明零残留
  - [x] 另行明确授权的一次性真实 fixture 已通过 create、Safari UI/CLI 回读、bookmark
    edit/move/delete 与 folder rename/move/empty-delete。最终 fixture 零残留、Reading List 未变化；
    原有 117 个节点除 Safari 对两个内建根目录标题的规范化外完全一致

合并后的 0.8.1 源码版本在本地 CRUD 与 release gate 全部通过后作为发布目标。它不依赖
iCloud 同步，正式二进制也不得调用 Safari 私有 Framework 或同步 daemon。

### 0.8.8：Safari iCloud 同步研究

- [x] 记录当前 no-go 证据
  - 直接替换 plist 在本机可见，但没有生成 `Sync.Changes`，第二设备也未出现
  - 私有 `WebBookmarkGroup` create/save 确实生成唯一 matching `Sync.Changes` `Add`，并且单参数
    sync request 只调用一次，但第二设备仍未出现 fixture
  - 远端回读失败后，已通过 UUID 重新解析对象并删除、save，本机验证零匹配，同时只调用一次 cleanup
    sync request；没有自动重试或重启 daemon
- [ ] 只有本地 CRUD 发布稳定后才重新研究同步；分别评估 Safari-owned HTML import、Shortcuts Safari
  action、实际 Safari WebExtension capability 与非坐标语义 Accessibility
- [ ] 未来任何私有 Framework 实验都必须重新取得明确授权，使用 disposable fixture、全新 recovery、
  compatibility/signing 审计、单次尝试 receipt、第二设备 create/delete 回读和零残留证明。私有 selector
  被调用或本机存在 `Sync.Changes` 都不等于同步成功
- [ ] 在某条受支持或用户明确接受的路线通过重复跨设备 create/update/move/delete、conflict、duplicate
  与 recovery gate 前，不得公开 iCloud-syncing contract

### 0.9.0：Phone 与 Messages CLI 可行性调研

- [x] 调研 macOS Phone/FaceTime 与 Messages 能否形成安全、本机、只读的 CLI adapter，目标是
  获取最近通话记录与最近消息
  - 先盘点受支持 macOS 版本和实际安装 app；不得假定每台受支持 Mac 都存在 `Phone.app`，
    也不得假定它一定是通话记录的 owner
  - 优先审计公共 Framework、app scripting dictionary、Shortcuts action、Apple Events、
    Continuity 边界和官方 export；之后才考虑本地 store
  - 如果公共接口不足，另行评估严格只读的本地 database/index：要求 Full Disk Access、运行时
    schema fingerprint、immutable connection、有界 query 和版本不兼容时 fail closed；没有形成
    单独架构与隐私决策前，不实现或公开该 fallback
- [x] 先设计但不承诺 metadata-first 候选 contract：`phone calls recent` 返回方向、时间、时长、
  missed 状态；`messages recent` 返回 service、方向、时间、conversation 和有界正文 projection。
  联系方式、正文、attachment path、raw local ID 与 account identifier 必须另行定义显式 projection
  和脱敏规则
- [x] 明确 Full Disk Access、Automation、Contacts 名称解析、Messages 数据和 Phone/FaceTime
  数据对应的 TCC/用户授权行为。permission status 不得弹窗；只有显式 request 路径可发起普通授权
- [x] 0.9.0 调研及可能的初始 adapter 保持只读：不发送/回复消息、不发起通话、不修改 voicemail、
  不 mark-read、不 reaction、不导出 attachment、不删除 conversation 或通话记录
- [x] Phone/通话记录与 Messages 分别给出 go/no-go 决策。parser 只使用 synthetic fixture；任何
  真实 smoke 都必须隐私最小化、有界、另行明确授权，且不得打印个人联系方式或正文

**Go/no-go（2026-08-16 已记录）**：两者均无公开框架可读历史——Phone.app / FaceTime.app 无
AppleScript sdef 且 CallKit 仅 iOS；Messages.app 的 sdef 只暴露 `send`/`login`/`logout`（无
`message` 类），读不了历史。因此 0.9 全系走「只读本地库」回退，复用 Mail 的 SQLite fast-path
模式（Full Disk Access + 运行时 schema 指纹 + immutable + 有界查询 + fail-closed）。数据源：
Messages = `~/Library/Messages/chat.db`（SQLite，schema 已确认，风险较低）；Phone =
`~/Library/Application Support/CallHistoryDB/CallHistory.storedata`（Core Data SQLite，schema 需
逆向，风险较高）。两者均为高敏感个人数据，投影/redaction 必须先行。结论：go。

### 0.9.1：Messages adapter（只读 recent）

架构：[Messages adapter 0.9.1](docs/development/messages-adapter-architecture.md)。

- [x] `messages permission` — 状态查询：Full Disk Access + `chat.db` 可读性探测（不弹窗）
- [x] `messages recent [--limit N] [--cursor C] [--service imessage|sms]` — 只读、最新在前、游标分页
- [x] 运行时 `chat.db` schema 指纹门禁（不匹配即 fail-closed）、immutable 只读 SQLite、有界 query + deadline
- [x] metadata-first 契约：opaque local ID、`service`、`isFromMe`、时间戳、opaque conversation ID、有界正文投影（默认 500 字符截断 + `truncated` 标记）
- [x] 脱敏：绝不返回 raw handle/电话/邮箱/`ROWID`/`guid`/`chat_identifier`/attachment path；live smoke 只打印聚合计数
- [x] 0.9.1 不发消息/回复、mark-read、reaction、附件导出或任何写入

### 0.9.2：Phone adapter（只读最近通话记录）

架构：[Phone adapter 0.9.2](docs/development/phone-adapter-architecture.md)。

- [x] 逆向 `~/Library/Application Support/CallHistoryDB/CallHistory.storedata`（Core Data SQLite）schema，记录运行时指纹
  - 存储为 WAL 模式的 Core Data SQLite；`com.apple.callhistory.databaseInfo.plist` 报告 `DatabaseVersionPerm = 46`。
  - 表：`ZCALLRECORD`（通话记录）、`ZHANDLE`（参与者句柄）、`ZCALLDBPROPERTIES`、`ZEMERGENCYMEDIAITEM`、`ZSAINTDAVIDSCOUNTS`、`Z_2REMOTEPARTICIPANTHANDLES`（群呼关联），以及 Core Data 记账 `Z_METADATA`/`Z_MODELCACHE`/`Z_PRIMARYKEY`。
  - `ZCALLRECORD` 关键列：`Z_PK`（主键）、`ZDATE`（TIMESTAMP = Apple 纪元**秒**，带小数；+978307200 → Unix）、`ZDURATION`（FLOAT 秒）、`ZORIGINATED`（0=呼入 / 1=呼出）、`ZANSWERED`（呼入已接听标记）、`ZCALLTYPE`（1=音频、8=视频）、`ZHANDLE_TYPE`（1=电话 / 2=邮箱）、`ZUNIQUE_ID`（TEXT UUID），另有 `ZADDRESS`/`ZNAME`/`ZLOCATION`（参与者 PII——永不读取）。
  - 未接语义在 272 行真实数据上确认：呼入 + `ZANSWERED=0` ⇒ 未接（`ZDURATION` 全为 0）；呼出 `ZANSWERED` 不可靠，以 `ZDURATION>0` 判定「已接通」。
  - 运行时指纹 = 对 `sqlite_master` 行做 SHA-256（与 Messages/Mail 同门）。
- [x] `phone-calls permission` — 状态查询（不弹窗）
- [x] `phone-calls recent [--limit N] [--cursor C]` — 方向/时间/时长/未接状态，最新在前，游标分页
- [x] 脱敏：绝不返回对方号码原文或账号标识
- [x] 与 Messages/Mail 相同的 fail-closed、有界、immutable、deadline 纪律

### 0.9.3：REST 风格 CLI 破坏性重构

0.9.3 不提供旧 adapter/subcommand 兼容层。除 `--help`、`--version` 和 `-v`
外，统一入口为 `mpia METHOD "/path"`，manifest 是运行时路由、参数、body schema、
安全约束和输出 schema 的单一事实源。它是本机 CLI contract，不是网络 HTTP 服务。

- [x] 增加严格 METHOD/path parser、dispatcher，以及稳定的未知路径、方法不匹配和
  `LEGACY_SYNTAX_REMOVED` 错误
- [x] 增加严格内联 JSON object：`--params` 32 KiB、`--body` 384 KiB；拒绝重复键、
  未知字段、类型错误、缺少必填字段和不允许的 body
- [x] 将 `--dry-run`、`--apply`、`--confirm` 保留为 JSON 外的独立安全 flags，
  写入 route fail-closed
- [x] manifest 公开输出只保留 `cli`、`routes`、`schemas`，OpenAPI 直接描述可执行 route
- [x] 将 README、usage、开发文档和本机测试脚本迁移到 METHOD/path 形式
- [x] 拆分 2,617 行的 `CLI.swift`；REST 入口和各 adapter handler/parser 均低于 300 行
- [x] 完成全仓旧语法扫描、Swift tests、CLI contracts、文档生成、Release build、
  `git diff --check` 和版本一致性门禁
- [x] 门禁全部通过后，统一把 VERSION、Info.plist、CLI version、CHANGELOG 更新为 0.9.3
- [ ] 清理全仓历史代码行数债务：当前仍有 24 个手写 Swift source/test 文件超过
  主库 300 行硬上限；0.9.3 新增的 CLI/route 文件已经全部低于 300 行，但在这些
  旧文件拆分前不能宣称“全仓行数门禁通过”
- [ ] commit、tag、push 和 Release 等待单独授权

### 1.0.0：文档完备、体验、清晰度与 demo app

1.0.0 是产品打磨门：8 个既有 adapter + Messages（0.9.1）+ Phone（0.9.2）全部交付后，
交付物从「可用」升级为「完备、清晰、可安装」。这是路线图里第一个非 adapter 里程碑。

#### 1.0.0-a：契约与清晰度（地基）

- [x] 把 90 个命令的描述从单句扩成多句（做什么、关键参数、读写边界、安全、返回结构）
- [x] 补齐 230 个字段描述和缺失的标量 `example`（patch/enum 字段按设计不设 example）
- [ ] 统一各 adapter 字段命名；需要改契约的项在 1.0.0 前单独决策
- [ ] manifest 保持单一事实源：描述 + example 流入文档，绝不在文档层手写维护
- [x] contacts + resources 批（15 个命令）已端到端完成，作为模板

#### 1.0.0-b：文档完备（从 manifest 生成）

- [ ] per-adapter 数据流图（SVG；Scalar markdown 不渲染 Mermaid），放 `docs-site/assets`
- [ ] 从增强后的描述渲染每命令详细说明
- [ ] 从 schema `example` 生成完整请求 JSON sample（成功 + 错误）
- [ ] 命令总览章节：按 adapter 列命令 + HTTP 方法映射 + 读写边界 + 确认短语

#### 1.0.0-c：体验优化

- [ ] Developer ID 签名 + 公证（清爽 `brew install` 的前提；取决于 Apple Developer 账号）
- [ ] 重写 `INSTALL.md` 为清爽的 `brew install mpia-cli` 流程（若 1.0.0 时签名未就绪则保留明确的 unsigned 边界说明）
- [ ] 截图：demo app + CLI 真实运行截图（有界数量，约 5–8 张），放 README/INSTALL 与 docs guide

#### 1.0.0-d：Demo 原生 SwiftUI macOS app

- [ ] 薄 SwiftUI app，复用 mpia Core/Sources：只读展示各 adapter 数据 + 权限状态 + 安全 dry-run 预览
- [ ] 兼作 TCC 授权承载进程与截图来源
- [ ] 不做写 apply、不做 GUI 坐标自动化；明确不是 CLI 重实现

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

- 通用 GUI 坐标自动化和图像匹配；0.7.2 仅评估严格限定、语义化且显式标记为 experimental 的
  Shortcuts Accessibility backend
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
