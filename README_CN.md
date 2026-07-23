# macos-data-cli

面向 Agent 和开发者的 macOS 原生数据访问 CLI 基础设施。

项目希望填补一个实际空白：Agent 需要操作 macOS 原生数据时，通常只能依赖脆弱的
GUI 自动化、特定平台集成，或直接接触不稳定的内部数据格式。`macos-data-cli` 提供
本地、可脚本化、可测试的访问层：优先采用 Apple 公共 Framework；仅当公共 Framework
无法暴露所需数据时，才允许范围明确、有文档、严格只读的本地 adapter。

## 项目状态

Contacts 第一版当前为 0.1.7。已经支持权限检查、iCloud 容器验证、JSON
读取、查询、受控写入、头像、删除、external ID 迁移和 JSON 快照导出。

Mail 0.2 正在开发中；只读 capability 检查、账号和 mailbox 发现、有限邮件 metadata
查询、显式 cached text/raw 读取、Mail.app text fallback 和可视化 reveal 已可用。
adapter 只启用运行时验证通过的 V10 SQLite/EMLX 快路径，且永不写入 Mail store。

第一版（0.1）先实现 macOS Contacts adapter。路线图中的命令只有标记为已实现的部分可以直接运行。

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

## 核心目标

- 通过 Terminal 使用，安装后即可被脚本和 Agent 调用
- 使用稳定的 CLI 和 JSON contract
- 所有 Agent 共用同一个 CLI，不绑定 Codex、Claude Code 或其他平台
- 优先使用 Apple 公共 Framework，不依赖 GUI 自动化
- 对写操作提供 dry-run、差异预览和显式确认
- 在本机运行，不上传联系人或其他系统数据
- 通过 adapter 逐步扩展到不同的 macOS 数据服务

Obsidian 是项目作者的实际使用场景，但不是公共协议的强制依赖。外部系统可以使用自己的稳定 ID；项目不会把某个 Agent 或知识库写死在核心设计中。

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
macos-data contacts permission
macos-data contacts count [--format json]
macos-data contacts list --format json
macos-data contacts get --external-id <id> --format json
macos-data contacts query --name "..."
macos-data contacts query --kind organization
macos-data contacts query --phone "..."
macos-data contacts query --email "..."
macos-data contacts query --url "..."
macos-data contacts query --organization "..."
macos-data contacts query --postal-code "..."
macos-data contacts create --input contact.json --dry-run
macos-data contacts create --input contact.json --apply
cat contact.json | macos-data contacts create --stdin --dry-run
cat contact.json | macos-data contacts create --stdin --apply --idempotent
macos-data contacts edit --external-id <id> --input contact.json --dry-run
macos-data contacts edit --external-id <id> --input contact.json --apply
cat patch.json | macos-data contacts edit --external-id <id> --stdin --dry-run
macos-data contacts edit --external-id <id> --image <file> --dry-run
macos-data contacts edit --external-id <id> --image <file> --apply
macos-data contacts avatar verify --external-id <id> --format json
macos-data contacts avatar replace --external-id <id> --image <file> --dry-run
macos-data contacts avatar replace --external-id <id> --image <file> --apply --confirm "RECREATE CONTACT"
macos-data contacts delete --external-id <id> --dry-run
macos-data contacts delete --external-id <id> --apply --confirm "DELETE CONTACT"
macos-data contacts delete --external-id <id> --apply --confirm "DELETE CONTACT" --ignore-not-found
macos-data contacts external-id migrate --from <old> --to <new> --dry-run
macos-data contacts external-id migrate --from <old> --to <new> --apply --confirm "CHANGE EXTERNAL ID"
macos-data contacts export --format json [--output <file>]
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

## 0.2 开发中：Mail 只读命令

```text
macos-data mail doctor --format json
macos-data mail accounts --format json
macos-data mail mailboxes [--account-id <id>] --format json
macos-data mail query [filters] [--limit <1...200>] [--cursor <cursor>] --format json
macos-data mail get --id <id> [--content metadata|text] --format json
macos-data mail get --id <id> --content raw --output <file|->
macos-data mail reveal --id <id> --format json
macos-data mail attachments verify --id <id> --format json
```

`doctor` 不启动 Mail.app、不触发权限弹窗，也不读取邮件主题、地址或正文。只有运行时
确认 `V10` 必需结构、WAL 和只读数据库状态后，`fastPathAvailable` 才会为 `true`。
metadata 查询默认返回 50 条、最多 200 条，使用参数绑定、opaque local ID、cursor
分页和 query deadline；不会读取正文。
`mail get` 默认只返回 metadata；text/raw 必须显式指定。缓存 text 缺失时可以使用
有上限的 Mail.app Apple Events fallback；raw 仍保持 cache-only 和 byte-exact。raw
bytes 不进入 JSON，且不会覆盖已有输出文件。这里仅 `mail reveal` 会主动激活 Mail.app。
`mail attachments verify` 只比较 SQLite 和缓存 MIME 的数量，不导出附件名或 payload；
partial EMLX 始终保持 unverified。

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

下一步是 0.2 Mail adapter，采用只读 SQLite/EMLX、Mail.app Apple Events 回退和
可视化确认的混合架构；Calendar 顺延到 0.3，之后为 Reminders、Notes 和 Photos。
详见 [Mail 架构决策](docs/development/mail-adapter-architecture_CN.md)。vCard、批量操作和
变更检测属于 Contacts 的后续工作。每个 adapter 都应独立定义权限要求、数据映射、
错误格式和测试策略。

## 许可证

请参阅 [LICENSE](LICENSE)。
