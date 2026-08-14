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

```text
macos-data notes permission [--request] --format json
macos-data notes accounts --format json
macos-data notes folders [--account-id ID] [--parent-id ID]
  [--limit N] [--cursor C] --format json
macos-data notes query [--account-id ID] [--folder-id ID]
  [--title TEXT] [--modified-after ISO-8601]
  [--limit N] [--cursor C] --format json
macos-data notes get --id <opaque-note-id>
  [--body none|plaintext|html] [--include-attachments] --format json
```

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
`com.apple.security.automation.apple-events` entitlement。`notes permission --request` 只触发
普通 macOS Automation prompt；查询命令在未授权时返回稳定错误，不自动打开设置或静默重试。

每次 Apple Event 都必须有 deadline 和对象数量上限。禁止无界读取 `every note` 的 body。
metadata 枚举和 body get 分离；timeout 后启动 circuit breaker。

## 验收 gate

1. synthetic tests 覆盖 mapping、opaque ID、分页、body opt-in、byte 上限、locked note、缺失字段、
   timeout 和稳定错误。
2. CLI contract 证明 metadata-only 默认值，并确保日志不泄露 body。
3. 稳定签名 debug app 通过 LaunchServices 获取 Notes Automation 权限。
4. 隐私安全 live gate 只输出授权状态与 account/folder/note 聚合数量。
5. 一次性测试 note 验证 get/read，并零残留清理；不得修改现有用户 note。

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
  metadata 路径返回空且 complete 的列表，没有读取 binary contents。该 note 已移入 Notes
  Recently Deleted；Notes 公共 scripting dictionary 没有稳定、与语言无关的 deleted-folder
  标志，因此在永久删除前，普通有界 Apple Events query 仍可能看见这条可恢复数据。
