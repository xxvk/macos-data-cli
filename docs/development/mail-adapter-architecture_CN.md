# Mail adapter 架构决策（0.2.0）

状态：进入实施规划  
日期：2026-07-21

## 决策

0.2.0 以只读、本地优先的 Mail adapter 开始，直接使用本机 Mail.app 已经
同步和展示的数据；Calendar 顺延到 0.3。

读取链路采用三层混合架构：

1. 严格只读打开 Mail 的 `Envelope Index` SQLite，查询账号、邮箱、邮件
   envelope、数量和元数据。
2. 读取本地缓存的 `.emlx` / `.partial.emlx`，获得 RFC 822 原文、正文和附件元数据。
3. 正文未缓存、账号类型不落 `.emlx`，或用户要求在 Mail.app 中可视化定位时，
   回退到 Mail.app 的 Apple Events。

MailKit 不作为核心读取接口。Apple 将 MailKit 定位为 Mail Extension Framework，
主要覆盖新邮件 action、compose、内容拦截和邮件安全；它没有向独立 CLI 提供任意
枚举已有邮箱的通用 API。

完整技术评估、命令草案、安全约束、测试门槛和外部参考见
[English architecture decision](mail-adapter-architecture.md)。以下是中文执行摘要。

## 为什么采用混合架构

- 数据来自用户正在 Mail.app 中看到的本地状态，不再保存第二套邮箱 OAuth/token。
- SQLite 适合高速、分页、可重复的元数据检索；Apple Events 负责正确性回退与
  Mail.app 内的可视化确认。
- 先发布只读能力，把非公开数据格式的风险压缩在可替换的 adapter 边界内。
- CLI 和 JSON contract 是公共核心；MCP、Skill 或其他 Agent 集成以后只需调用 CLI。

## 开发机基线与当前 macOS 26 状态

此前在 macOS 27 开发机上完成过 Mail store 结构勘察，没有读取或输出邮件正文：

- macOS 27.0（`26A5368g`），Xcode SDK 26.5。
- Mail 数据位于 `~/Library/Mail/V10`。
- `V10/MailData/Envelope Index` 使用 SQLite WAL，存在 `-wal` 与 `-shm` sidecar。
- 关键表包括 `messages`、`mailboxes`、`addresses`、`subjects`、`recipients`、
  `summaries` 和 `attachments`。
- 当前库的 `date_received` 使用 Unix epoch；它仍然是非公开 schema，必须通过
  fixture 和启动时 capability probe 验证，不能把本机观察当成 Apple 保证。
- 本地正文以 `.emlx` 保存：首行为 RFC 822 数据的字节长度，随后是准确长度的
  RFC 822 字节和可选 Apple metadata。
- Mail.app 的 scripting dictionary 暴露了 account、mailbox、message、subject、
  sender、content、收发时间、Message-ID 和 read status。

这些观察是历史兼容性基线，不是 Apple 的公开 schema 保证。

当前开发机已切换为：

- macOS 26.4（build `25E241`，Apple Silicon）。
- Xcode 26.6（build `17F113`）。
- macOS SDK 26.5。

2026-07-23 在当前 macOS 26.4 机器上完成了不读取正文的只读 probe：

- 动态发现 `~/Library/Mail/V10`；`Envelope Index`、`-wal`、`-shm` 均存在。
- SQLite 以 `mode=ro` 打开，`journal_mode=wal`，`quick_check=ok`。
- `messages`、`mailboxes`、`subjects`、`addresses`、`recipients`、`attachments`、
  `summaries` 等核心表及所需日期、外键、状态字段可读；已存在对应索引。
- 当前库可见约 124,479 条 message metadata、36 个 mailbox；Mail root 下有约
  43,298 个 `.emlx` 文件。
- 当前 V10 库中所有 `mailboxes.source` 都是 null。因此 0.2.0-b 从 mailbox URL 的
  scheme 和 authority 派生账号作用域，只返回 hash 派生的 opaque account ID，绝不
  输出原始 authority 或完整 URL。
- 抽样 `.emlx` 符合“首行 RFC 822 字节长度 + 后续内容”的容器格式；未读取或输出正文。
- 已实现的 0.2.0-c resolver 在本机通过 variable-depth ROWID 路径定位到完整缓存邮件；
  text 解码与准确 raw 导出均通过临时文件 smoke，未打印内容，临时文件自动删除。

因此，**V10 SQLite/EMLX 快路径在当前 macOS 26.4 机器上兼容且具备实现条件**。
这不是 Apple 对私有 schema 的兼容保证；`mail doctor` 仍必须在启动时重新发现版本、
校验 schema fingerprint、确认 WAL 可读性，并在不满足条件时 fail closed。Full Disk
Access 与 Mail.app Automation 尚未由本次 SQLite probe 单独判定，应该作为独立能力项返回。

## macOS 26 支持基线与 V10 条件

项目 deployment target 保持 macOS 26.0，并以 macOS 26 SDK 编译；当前本机 SDK 为
26.5。计划使用的 `Foundation`、Apple Events 和系统 `sqlite3` 都能在该基线使用。
MailKit 相关声明从 macOS 12.0 起可用，因此在 macOS 26 也能编译；不选择它作为查询
接口，是因为它的 extension 执行模型不支持历史 mailbox 枚举，而不是 API level 不够。

`V10` 是 Mail 的本地数据格式版本，不是 macOS API level，Apple 没有保证所有
macOS 26 安装都一定是 `V10`。因此 0.2.0 按运行时能力定义支持：

| 运行状态 | 0.2.0 行为 |
| --- | --- |
| macOS 26.x + 可读 `V10` + 已识别 schema fingerprint | 启用完整 SQLite/EMLX 快路径 |
| macOS 26.x + 其他 `V*` 或未知 schema | 禁用直接读取；仅当 Mail 已运行且 Automation 已授权时使用有限 metadata fallback，否则 fail closed |
| macOS 26.x + `V10` 但没有 Full Disk Access | 提示 FDA；可用时使用相同的有限 Mail.app metadata fallback，否则 fail closed |
| Mail 未配置或没有本地 store | `mail doctor` 返回 `MAIL_STORE_NOT_FOUND` |
| 开发机 macOS 27 + 已识别 `V10` | 仅作为前向兼容测试，不改变正式 macOS 26 基线 |

所以“macOS 26 + `~/Library/Mail/V10`”这个要件可以满足，但必须由运行时 probe
确认，不能硬编码推断。`MailStoreLocator` 动态发现最高数字版本的 `V*`；首个
`MailV10Schema` 只有在必要表、字段、索引、时间戳范围和 WAL 可读性全部符合时才启用。

`mail doctor --format json` 应返回 `osVersion`、`sdkBaseline`、
`mailStoreVersion`、`schemaFingerprint`、`fullDiskAccess`、`automation` 和
`fastPathAvailable`，以便在真实 macOS 26 主机上验收。

## 按复杂度与耗时排序

令 `N` 为邮件总数、`K` 为返回行数、`B` 为单封 RFC 822 字节数、`F` 为 Mail
目录文件数、`df(t)` 为 FTS term 的 document frequency。不同变量之间不能做严格的
数学全序，下面按各路径承担目标查询时的实际延迟和扩展性排序：

| 优先级 | 查询路径 | 时间复杂度 | 本机证据或预期耗时 |
| ---: | --- | --- | --- |
| 1 | SQLite 精确 ROWID/外键查询 | `O(log N)` | 热连接中位 `<0.01 ms`；包含新建 `sqlite3` 进程约 `4.7 ms` |
| 2 | SQLite 按日期/mailbox/subject/recipient 的索引分页 | `O(log N + K)` | 热连接 50 行 `<0.01 ms`；含进程启动约 `4.5 ms` |
| 3 | 已知 ID 直接定位并读取 `.emlx` | 路径 `O(1)`，读取/解析 `O(B)` | 200 个缓存样本：中位 `0.19 ms`，p95 `0.36 ms`；MIME 解析另加线性开销 |
| 4 | 可选本地 FTS5 正文索引 | 查询约 `O(sum(df(t)) + K log K)`；首次建索引 `O(缓存总字节)` | 参考实现约 `7 ms`；不作为 0.2.0 依赖 |
| 5 | SQLite `LIKE '%term%'` 无索引扫描 | `O(N + K)` | 约 12.4 万封邮件、无匹配热扫描：subject `11.4 ms`、summary `15.5 ms`，随数据线性增长 |
| 6 | Spotlight / `mdfind` | Apple 未公开复杂度 | 常见为几十到几百 ms，但完整性和确定性分页无保证 |
| 7 | 定向 Mail.app Apple Event | 本地定位 + IPC；未缓存正文还包含网络耗时 | 单封预算 3 秒；本地常见可能为几十到几百 ms |
| 8 | Mail.app 全量枚举/搜索 | 至少 `O(N)` 加逐对象 IPC | 大邮箱通常为秒级并可能超时，不作为首选 |
| 9 | 递归扫描 `.emlx` | 先 `O(F)`，再读取 `O(B)` | 当前 Mail root 无匹配全扫描 `1.83 s`；禁止成为自动 fallback |

测量使用只读 live `V10`、约 12.4 万封邮件、热文件缓存；没有输出邮件内容，且除特别
说明外不包含 JSON/MIME 序列化。它们是工程证据，不是 SLA。

默认性能预算：索引 SQLite 100 ms、默认 50 行且最大 200 行；无索引有限扫描
250 ms；缓存 `.emlx` 读取每封 100 ms 并设置显式字节上限；单封 Apple Event 3 秒；
有限列表 fallback 5 秒且最多 25 个候选。Apple Event 超时后开启 30 秒熔断，不自动
重试，也不升级成全目录扫描。

## 效率优先的 fallback 状态机

进程启动时只构建一次 capability snapshot：Mail root/version、schema、只读
SQLite/WAL、`.emlx`、可选 FTS 与 Automation 状态。之后按操作选计划：

1. **元数据查询：**索引 SQLite -> 仅在条件无索引时做有时间上限的 SQLite scan ->
   仅当 SQLite 不可用、Mail 已运行且 Automation 已授权时读取 Mail.app metadata
   snapshot。snapshot 上限为 32 个账号、200 个顶层 mailbox、25 个 message 候选和
   5 秒；不提供 cursor 且始终 incomplete。SQLite 返回完整空结果后不再回退。
2. **读取已知邮件：**SQLite 定位 -> 直接 `.emlx` -> 仅在文件缺失/partial 时调用一次
   定向 Mail.app Apple Event -> Automation 不可用则明确返回 `metadata_only`。
3. **正文搜索：**可选本地 FTS -> 标记为 `incomplete` 的 Spotlight discovery ->
   显式限定最近范围的 `.emlx` 扫描。全 Mail.app/文件系统枚举只能由 slow mode 主动开启。
4. **Mail.app 可视化：**先用 SQLite 确定候选，再发送一个定向 Apple Event；不使用
   Accessibility 或坐标 GUI fallback。

每次 fallback 都必须返回 `backend`、`elapsedMs`、`fallbackReason`、`cacheState`、
`truncated` 和 `incomplete`。更快但不完整的结果不得标为 complete。自动模式没有
provider API、IMAP、递归文件扫描或 GUI automation 兜底。
fallback 生成的 `ambx_` / `appmsg_` selector 是 backend-specific opaque 值。
`appmsg_` 可用于定向 metadata/text read 或 reveal；raw export 与 attachment cross-check
仍只允许 SQLite/EMLX。fallback 不枚举嵌套 mailbox，无匹配结果也绝不视为完整搜索。

## MailKit 到底做什么

MailKit 是由 Mail.app 在特定 extension 生命周期中主动调用的框架，不是查询 Mail.app
历史数据的 client object model。它主要用于：

- **Message Action：**Mail 下载新邮件时检查内容，必要时等正文下载后再调用；可标记
  read/unread、flag/颜色，或移动到 Archive、Junk、Trash。
- **Compose Session：**跟踪写信窗口、标注/校验收件人、提供 extension UI、阻止不合规
  发送或增加 header。
- **Content Blocker：**为 Mail 的 WebKit message view 提供远程内容拦截规则。
- **Message Security：**签名、加密、解密，以及展示签名人/证书信息。

`MEMessage` 是 Mail 在这些 callback 中交给 extension 的对象；框架没有“列出账号”、
“搜索全部历史邮件”或“按 ROWID 读取”的方法。未来可以做一个可选 MailKit companion
extension，用 `MEMessageActionHandler` 把从安装启用之后新下载的邮件增量送入独立本地
FTS；它无法回填历史邮件，而且需要签名 host app 与用户在 Mail 中启用 extension。
因此这是可能的 0.2.x 优化，不是 0.2.0 核心读取接口。

## 0.2.0 MVP

```text
macos-data mail doctor --format json
macos-data mail accounts --format json
macos-data mail mailboxes [--account-id <id>] --format json
macos-data mail query [filters] [--limit <n>] [--cursor <cursor>] --format json
macos-data mail get --id <opaque-local-id> [--content metadata|text] --format json
macos-data mail get --id <opaque-local-id> --content raw --output <file|->
macos-data mail reveal --id <opaque-local-id> [--format json]
macos-data mail attachments verify --id <opaque-local-id> --format json
```

首版查询支持 account、mailbox、from、to、subject、received-after/before、
unread、flagged 和 has-attachment。`get` 默认只返回 metadata；读取正文必须显式指定。

每次结果都返回来源信息，例如：

```json
{
  "backend": "sqlite_emlx",
  "cacheState": "complete",
  "limitations": []
}
```

0.2.0 不包含发送、回复、草稿、删除、移动、修改已读/flag、任意附件导出、
全邮箱后台 FTS 索引和任意 SQL。

`attachments verify` 是 release diagnostic，不是附件提取。它只返回 SQLite/MIME
count 和 verification state，不返回附件名、路径、content ID 或 payload bytes；
partial EMLX 永远不能产生 `matched`。

## CLI 语法与参数哲学

统一语法是：

```text
macos-data <domain> <operation> [selector] [projection] [rendering]
```

在 Mail 中，`mail` 是数据域；filter 和 `--id` 负责选择；`--content` 决定对选中
邮件读取多少内容；`--format` 只决定序列化方式。选择、内容投影和输出表现互不混用，
避免底层存储或显示格式改变查询语义。

设计遵循六条规则：

1. **先发现、后查询：**`doctor`、`accounts`、`mailboxes` 先建立能力和作用域。
2. **从命令名表达 cardinality：**`query` 返回零到多个 envelope；`get` 必须唯一，
   否则返回 not-found/stale 错误。
3. **默认最少数据：**列表永不带正文；`get` 默认 metadata；正文和 raw 必须显式要求。
4. **UI 副作用显式：**普通读取不激活 Mail.app；只有 `reveal` 进入原生界面。
5. **调用者表达意图，不选择 backend：**正常参数不暴露 SQLite/EMLX/Apple Events
   开关；planner 选择最快的完整路径，并在结果中报告实际 backend。
6. **兼容 Unix 与 Agent：**成功数据写 stdout，诊断写 stderr；调用者先按 exit code
   分支，再解析带独立版本的 JSON envelope。

| 命令 | cardinality / effect | 参数形状的原因 |
| --- | --- | --- |
| `mail doctor` | 一个 capability report | Mail 可用性由 store、schema、FDA、Automation、cache 和 fast path 共同决定，不是单一 permission bit |
| `mail accounts` | 0..N collection | 在 mailbox/message 操作前建立稳定账号作用域；0.2.0 只有只读 collection 语义，所以省略冗余 `list` |
| `mail mailboxes` | 0..N collection | 把层级发现与计数从邮件搜索分离；`--account-id` 高效解决多账号歧义 |
| `mail query` | 0..N envelopes | 有上限、cursor 分页的候选搜索，不读取正文 |
| `mail get` | 唯一一封 | 把唯一定位与集合搜索分离，并显式控制内容投影 |
| `mail reveal` | 一次可见 Mail.app 行为 | 把 Apple Events/UI 激活隔离在纯读取之外；reveal 表示在来源 app 中定位，不表示导出 |

`mail doctor` 默认必须非交互、无副作用：不启动 Mail.app、不触发 Automation prompt、
不自动打开 System Settings。`--open-settings` 之类的帮助行为必须显式指定。

`accounts` 和 `mailboxes` 返回 adapter 稳定 ID；display name 可能重复、本地化或被改名，
不能作为可靠 selector。`query` 使用 typed filter 与 AND 语义，默认 50、最大 200，
通过 cursor 而不是容易漂移的 page number 分页，并且永不接受任意 SQL。

### ID 与内容投影

公开的 `--id` 是 `query`/`get` 返回的 opaque adapter ID，不是裸 SQLite ROWID：

```json
{
  "id": "mail:v1:opaque-value",
  "idScope": "local",
  "messageID": "<optional-rfc822-id@example.com>"
}
```

这样内部 locator 编码可以演进而不破坏 CLI contract。该 ID 仍只在本机有效；Mail
重建索引或移动数据后可能 stale，必须返回 `STALE_LOCAL_ID`，不能静默选中别的邮件。

`--content` 是 projection，不是 format：

- `metadata`：header、地址、日期、flag、mailbox、大小和附件 metadata；默认值。
- `text`：安全解码的纯文本，不加载 HTML 远程资源。
- `raw`：准确 RFC 822 bytes。

RFC 822 可能不是 UTF-8 且体积很大，因此 raw 不直接嵌入 JSON。`--content raw`
必须配合 `--output <file>` 或 `--output -`：写文件时 stdout 返回小型 JSON/人类确认；
`--output -` 时 stdout 是原始 bytes，不能再使用 `--format json`。

`--format json` 只改变 rendering。Terminal 默认可读输出，Agent 显式请求 JSON。
`reveal` 也接受 `--format json`，让 Agent 在执行可见 UI 行为后获得结构化确认。

## Agent 与 MCP 边界

Mail 的真实实现属于 `macos-data` CLI，不属于 Codex plugin 或 MCP server。路径发现、
TCC 诊断、schema 适配、MIME 解析、输出限制和稳定 JSON contract 都由 CLI 统一负责，
保证人类在 Terminal 与任意 Agent 使用的是同一套经过审计的本地行为。

未来 MCP 可以把 `mail_search`、`mail_get` 等工具翻译为 CLI 调用，Plugin/Skill 可以
提供安全工作流说明；它们不得重复打开 `Envelope Index`、解析 `.emlx` 或维护第二套
权限逻辑。0.2.0 不把任何 MCP package 引入运行时依赖。

## 不可突破的安全边界

- SQLite 必须使用 `SQLITE_OPEN_READONLY`；禁止写入、VACUUM、checkpoint、
  attach、load extension 或把用户参数拼成 SQL。
- 读取 live WAL；不能只复制主库，也不能对实时数据库使用会忽略 WAL 更新的
  `immutable=1`。
- 动态发现最高的可读 `V*`，不能把 macOS 版本机械映射为固定 Mail 版本。
- 启动时验证所需表和字段；未知 schema 必须 fail closed，返回
  `MAIL_SCHEMA_UNSUPPORTED`。
- ROWID 只是本机定位符，不是跨机器稳定 ID；RFC 822 Message-ID 单独返回，并说明
  它也可能为空或重复。
- `.partial.emlx` 必须明确标记，不能把尚未下载的正文误报为空邮件。
- 不加载 HTML 远程资源；正文默认不进入列表结果和日志。
- 日志不得记录主题、邮箱地址、mailbox 名称、正文、附件名、RFC 822 原文或完整本机路径。
- 任何未来写操作都只能走公开的 Mail.app automation，并具有 preview/dry-run 与单独确认；
  永远不能写 `Envelope Index` 或 `.emlx`。

## 权限模型

- SQLite/EMLX：需要把 Full Disk Access 授予真正启动 CLI 的 responsible process，
  可能是 `macos-data.app`、Terminal 或 Agent host。
- Mail.app fallback / reveal：需要 Automation 权限。
- app 的 Info.plist 必须包含 `NSAppleEventsUsageDescription`；启用 Hardened Runtime 的
  签名 app 还需要 `com.apple.security.automation.apple-events` entitlement。
- Full Disk Access 不能由 CLI 静默授予；`mail doctor` 应精确区分未配置 Mail、
  权限拒绝、schema 不支持与 Automation 拒绝，并给出 System Settings 路径。

## 交付顺序

- 0.2.0-a：Mail 路径发现、FDA/schema doctor、fixture、稳定错误。**已实现并在 macOS 26.4 验证。**
- 0.2.0-b：账号、mailbox、有限 envelope query、分页。**已实现并在 macOS 26.4
  完成只读验证。**
- 0.2.0-c：`.emlx` raw/text 读取和 partial 状态。**已实现并在 macOS 26.4 完成只读验证。**
- 0.2.0-d：Apple Events 回退与 `mail reveal` 可视化确认。**已实现，并通过签名 Debug
  app 在 macOS 26.4 验证。**text fallback 只用于没有精确本地正文的显式读取；raw
  保持 cache-only。bridge 串行发送事件，3 秒超时，超时后熔断 30 秒；普通 fallback
  不启动 Mail.app。
- 0.2.0：签名/TCC 流程、文档、本机只读 smoke matrix。

全正文 FTS 和附件提取可在只读 contract 稳定后进入 0.2.x；Calendar 从 0.3 开始。

macOS 26.4 的真实 Automation 验证在登录用户 GUI bootstrap session 中成功 reveal 一条
由 V10 定位的消息。最近 200 条有限样本中没有 `metadata_only` 候选，因此没有为测试
强制触发真实正文 fallback；synthetic fixture 已覆盖成功、拒绝、Mail 未运行、定位失败、
超时和熔断路径，且不暴露真实邮件内容。

attachment cross-check 在 Mail.app 同步期间以只读方式执行；当时 V10 可见 1,146 条
attachment rows、509 封未删除的 attachment-bearing messages，509/509 都只解析到
`.partial.emlx`，partial MIME 中没有可匹配的 attachment parts。这是明确的
unverified 状态，不表示 SQLite row 失效。未来有限导出必须要求独立可用的 complete
content 或单独的公开 Mail.app 路径，不能只凭 SQLite metadata 合成文件。

可复现的非 UI 本机 release gate 已在 macOS 26.4 通过：72 个测试、Release build、
签名 Debug app，以及 doctor/metadata/content/attachment smoke。Automation 作为独立的
人工在场检查：一次成功；另一次在 Mail.app 正忙于同步时于 3 秒 budget 返回
`MAIL_APP_TIMEOUT` 并停止，没有自动重试，从而验证了 timeout 边界。

登录用户 GUI session 中的隐私安全 forced-fallback smoke 也已通过：3 个账号 scope、
35 个顶层 mailbox、1 条有限 message 结果，并通过其 `appmsg_` selector 完成定向
metadata get。JSON 仅保存在自动删除的临时目录，终端没有输出 message 字段。

## 重点参考实现

- [PsychQuant/che-apple-mail-mcp](https://github.com/PsychQuant/che-apple-mail-mcp)（MIT）：Swift SQLite/EMLX 与 AppleScript fallback；重点参考 variable-depth EMLX 路径、partial 文件和 fallback 可观察性。
- [joargp/amcli](https://github.com/joargp/amcli)（MIT）：小型只读 CLI；重点参考动态 `V*` 发现、doctor 和只读 SQL gate。
- [imdinu/apple-mail-mcp](https://github.com/imdinu/apple-mail-mcp)（GPL-3.0）：证明独立 FTS5 正文索引可行，但不得把 GPL 源码复制进本 MIT 项目。
- [macos-cli-tools/apple-mail-cli](https://github.com/macos-cli-tools/apple-mail-cli)（MIT）：AppleScript 命令覆盖与性能边界参考。
- [Apple MailKit](https://developer.apple.com/documentation/MailKit)、[Apple Events usage description](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)、[SQLite WAL](https://www.sqlite.org/wal.html)。

公开代码不等于可以直接复制。任何复用都要先核对许可证、必要 attribution，并用本项目
自己的 contract、fixture 和 macOS 26/27 回归测试重新验证。
