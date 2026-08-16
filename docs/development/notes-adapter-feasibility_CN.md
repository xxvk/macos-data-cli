# Notes adapter 0.6 可行性决策

状态：接受有边界的只读实现
日期：2026-08-14

## 决策

Apple 没有向第三方 macOS 进程开放可枚举用户 Apple Notes 数据库的 Notes Framework。
macOS 26.5 SDK 中不存在公开的 `Notes.framework` 或 `NoteKit.framework`；通用 Core Data、
CloudKit、Accounts API 也不会授予 Notes.app 私有 store 或 CloudKit container 的访问权。

不过 Notes.app 正式发布了 scripting dictionary。当前 macOS 27.0 开发机上的 Notes 4.13
公开了 account、嵌套 folder、note、attachment、应用拥有的稳定 ID、创建/修改日期、shared/
password-protected 状态、HTML body、只读 plaintext、附件 URL metadata 和 attachment save。
Apple 官方将 scripting dictionary 与 Apple Events 定义为 scriptable app 暴露命令和对象的
接口。

因此 0.6 可以实现有价值的**只读 Apple Events adapter**。文档必须准确称为 Notes.app
Automation，不能称为原生 Notes Framework。禁止读取 Notes 数据库、CloudKit record、缓存、
私有 Framework 或 GUI 坐标。

版本边界已经明确：0.6.0 为只读；受保护 Notes 写入规划为 0.6.1。首个 0.6.1 release scope
只包含 create、rename 和 move，并要求 dry-run/apply、乐观并发控制、适用操作的幂等性和立即
回读。现有 note 正文替换、attachment mutation 和 delete 继续延后，直到各自的破坏性/富内容
安全 gate 通过。

## 建议的 0.6 MVP

```bash
mpia GET "/agent/manifest"
```

0.9.3 可执行 route 请从 manifest 获取；完整示例见 `docs/usage_CN.md`。

query 默认只返回 metadata。body 可能高度敏感且远大于列表字段，因此必须显式 opt-in。
`get` 应限制返回 byte，并在锁定或不可访问 note 上 fail closed。分页使用 adapter 自有 opaque
cursor，并报告完整性；大 Notes library 上的 Apple Events 枚举不能承诺数据库级性能。

## 数据边界

MVP 支持：

- account 与嵌套 folder discovery；
- note ID、标题、创建/修改时间、folder reference、shared、password-protected；
- 显式读取 plaintext 或 HTML body；
- attachment metadata：opaque ID、名称、日期、content identifier、URL、shared。

延后：

- attachment binary export，必须先单独完成单文件、禁止覆盖、byte 上限、私有 staging 和清理 gate；
- 创建或编辑 folder/note，即使 scripting property 可写；
- 删除或移动 note；
- HTML 转 Markdown，或声称可以无损转换富文本。

当前公开 dictionary 不承诺：

- tag 与 smart-folder predicate；
- pinned 状态；
- checklist、table、drawing、scan、collaboration、mention 的结构化语义；
- 完整 attachment graph 或现代 Notes 富内容的无损 round trip。

HTML body 内的 link 可以作为 HTML 保留，但解析 link 不代表恢复了 Notes 内部富文本模型。

## 权限与执行

负责执行的签名 App 需要 `NSAppleEventsUsageDescription` 和 Mail adapter 已使用的
`com.apple.security.automation.apple-events` entitlement。`OPTIONS /notes/permission`
仅查询状态，不接受主动请求授权的参数；查询 route 在未授权时返回稳定错误，不自动打开设置或静默重试。

每次 Apple Event 都必须有 deadline 和对象数量上限。禁止无界读取 `every note` 的 body。
metadata 枚举和 body get 分离；timeout 后启动 circuit breaker。

## 验收 gate

1. synthetic tests 覆盖 mapping、opaque ID、分页、body opt-in、byte 上限、locked note、缺失字段、
   timeout 和稳定错误。
2. CLI contract 证明 metadata-only 默认值，并确保日志不泄露 body。
3. 稳定签名 debug app 通过 LaunchServices 获取 Notes Automation 权限。
4. 隐私安全 live gate 只输出授权状态与 account/folder/note 聚合数量。
5. 一次性测试 note 验证 get/read，并零残留清理；不得修改现有用户 note。

## 受保护写入实现边界

已发布 0.6.1 只增加 create、rename 和同账户 move。本机私有配置保存由用户确认属于 iCloud 的 opaque
account ID；scripting dictionary 没有可靠 account type 字段。写入还必须指定该账户下的非 shared
opaque folder ID。rename/move 使用最近 modification date 作为乐观并发 token。

所有 Notes Apple Event 共用一个串行锁和 5 秒 deadline。默认 dry-run；apply 明确区分回读确认、
保存成功但回读 pending，以及结果未知，Agent 不得自动重试后两者。输出和诊断使用 hash/byte 数，
不回显 title/body。0.6.2 开发切片增加受保护的整体正文替换，但只允许经检查无 attachment 且属于
有界简单 HTML 子集的 note；必须同时提供最新 modification date 和当前 plaintext SHA-256，保留
第一行标题，并在保存后验证新 plaintext hash。0.6.2 也通过公开 `delete note` 命令加入受保护、可恢复的单 Note
soft delete：要求最新整秒 modification date、准确 `DELETE NOTE` 确认、mutation 前直接回读，且
只能操作绑定账户内非 shared、非 locked note。回读确认仅证明相同标题 hash 的 note 已离开原 folder；
dictionary 没有稳定、与语言无关的 Recently Deleted 标志。pending/unknown 禁止重试，永久删除仍只
允许 UI 操作。attachment mutation、跨账户 move 与 shared/locked 写入仍不可用。

Notes 4.13 scripting dictionary 将 folder `name` 标为可写，提供 folder `id`、`shared`、
`container`，并包含 Cocoa Standard 的 `make`、`move` 和 `delete` 命令，但不提供 folder
modification date。因此 0.6.2 开发源码对 folder create/rename、受保护空 folder 删除 preview 和 move preview 使用准确的当前名称
SHA-256；move preview 还要求准确的当前 parent。JSON null 明确表示 account 根目录。default/shared 目标、同级重名、
跨账户 move、循环和不完整的有界 folder 图均 fail closed。目前只证明了生成脚本可编译以及 synthetic
签名 app gate 已证明 nested create、重名拒绝和 rename。Notes 4.13 folder move 无法保持可确认
identity：空 child 从可枚举图中消失，metadata 暂时失效。因此 apply 会在发送 Apple Event 前返回
`NOTES_FOLDER_MOVE_UNSUPPORTED`。
空 folder 删除 preview 必须提供准确名称 hash 与显式 parent，只允许非 default、非 shared 目标，并
重新确认直接 note 数与 child folder 数均为零。真实 apply gate 导致 metadata graph 失效；重启 Notes
后 child 以旧名称和新 opaque ID 再次出现。因此 apply 在任何写 Apple Event 前返回
`NOTES_FOLDER_DELETE_UNSUPPORTED`。
审计入口为 `scripts/run_notes_folder_integration.sh`。默认模式只检查权限、绑定与 create preview；
只有显式 `--apply` 才创建隔离的 root/destination/child tree，验证 create/rename 与 move/delete
fail-closed。UI 清理需要单独的 action-time 明确授权和最终零残留查询。

2026-08-14，取得确认后的 UI 清理按 child、root、destination 顺序完成。重启 Notes 后，签名 app
返回完整 graph；删除前后四个已知 opaque ID 均为零匹配，gate sentinel 前缀名称也为零匹配。

## 证据基线

- 开发机：macOS 27.0 build `26A5388g`。
- 已检查 toolchain SDK：macOS 26.5。
- 已检查 Notes.app：4.13，bundle ID `com.apple.Notes`。
- 使用 `sdef` 检查本机 Apple 签名 Notes scripting dictionary；这是兼容性基线，不代表 Apple
  永远不会调整 dictionary。
- 2026-08-14，稳定签名 debug app 已获得 Notes Automation 权限；隐私安全 discovery gate
  返回 1 个 account、12 个 folder、`complete: true`、未截断，并且没有打印名称、scripting ID、
  note 标题或正文；临时 JSON 已由 gate 删除。
- 2026-08-14，最初按 account 枚举 metadata 错误返回 0 条，因为 Notes 4.13 的
  `notes of account` 不会递归返回嵌套 folder 中的 note。bridge 已改为有界递归 folder 枚举；
  稳定 App metadata gate 随后返回 163 条 note、`complete: true`、未截断，163 条均具有创建与
  修改时间。gate 只打印聚合统计，并在退出时删除临时 JSON。
- 2026-08-14，一条一次性 note 已通过唯一标题 query、metadata-only get、显式 plaintext
  （116 UTF-8 bytes）和显式 HTML（159 UTF-8 bytes）的 sentinel/markup 验证。attachment
  metadata 路径返回空且 complete 的列表，没有读取 binary contents。该 note 先移入 Notes
  Recently Deleted，之后在 action-time 明确批准后通过 Notes UI 永久删除。Notes 公共 scripting
  dictionary 没有稳定、与语言无关的 deleted-folder 标志，因此清理 gate 必须采用 UI 永久删除，
  再通过签名 app 查询确认零匹配。
- 2026-08-14，第二条一次性 fixture 完成签名 app 正文修改端到端 gate：提供准确当前 plaintext
  SHA-256 与 modification date，dry-run 零写入，只执行一次 apply，立即 hash 回读确认，并在两个
  显式非 shared iCloud folder 间完成 rename 和 move。首次 wrapper 运行在 mutation 前安全停止，
  原因是 8 秒输出等待短于 Notes 与 LaunchServices 启动耗时；直接回读证明原正文未变化。wrapper
  后续先使用 20 秒进程输出等待；Xcode 27 app 的完整输出超过该上限，因此现在使用 40 秒并报告准确
  stage，而单次 Apple Event deadline 仍为 5 秒。取得
  action-time 确认后，只通过 Notes UI 永久删除该 fixture，保留无关 Recently Deleted note；
  签名 app sentinel 查询返回零匹配。
- 2026-08-14，单 Note soft-delete gate 经授权执行。wrapper 在 move 输出阶段达到 20 秒上限后
  fail closed，没有重试；只读 get 证明 move 已成功。随后从该已确认状态执行一次 delete dry-run 和
  一次 `DELETE NOTE` apply，返回 `readback_confirmed`；原 folder 零匹配，system-managed folder
  存在唯一可恢复匹配。取得 action-time 明确确认后，仅通过 Notes UI 永久删除本 fixture，并保留
  一条无关的 Recently Deleted note；最终签名 app sentinel 查询返回 `complete=true` 且零匹配。
- 2026-08-14，固定路径签名 debug app 先通过 folder gate 的 permission、有效 write-account 绑定与
  create preview 检查且没有写入；后续经授权的 apply 证据记录如下。
- 2026-08-14，经授权的 folder apply gate 已证明 nested create、重名拒绝、rename 和 UI 清理，并以
  sentinel 零匹配回读结束。gate 同时发现 account 递归枚举会产生重复 folder ID，以及 folder move
  会破坏可确认 identity。现通过 root-only 枚举与 graph validation 防止 crash；folder move apply
  在采用不同设计前保持禁用。
