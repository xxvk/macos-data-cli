# macos-data-cli

面向 Agent 和开发者的 macOS 原生数据访问 CLI 基础设施。

项目希望填补一个实际空白：Agent 需要操作 macOS 原生数据时，通常只能依赖脆弱的 GUI 自动化、特定平台集成，或直接接触不稳定的内部数据格式。`macos-data-cli` 通过 Apple 公共 Framework 提供本地、可脚本化、可测试的访问层。

## 项目状态

Contacts 第一版已经达到 0.1.2。当前支持权限检查、iCloud 容器验证、JSON 读取、查询、受控写入、头像、删除和 JSON 快照导出。

第一版（0.1）先实现 macOS Contacts adapter。路线图中的命令只有标记为已实现的部分可以直接运行。

详细开发计划请参阅：

- [中文路线图](ROADMAP_CN.md)
- [English Roadmap](ROADMAP.md)

使用与开发文档：

- [使用说明](docs/usage_CN.md)
- [开发规则](docs/development/rules_CN.md)
- [安装说明](../../../INSTALL.md)
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
- 邮箱、电话、网址和地址
- 头像
- 可选的 `external_id`
- 组织名称、邮箱、电话等多因素匹配
- JSON 输入和输出
- `--dry-run` 与显式 `--apply`

匹配到多个联系人时，CLI 应返回歧义结果并禁止自动写入。Agent 可以读取结果后自行判断下一步操作。

当前可用的命令：

```text
macos-data contacts permission
macos-data contacts count
macos-data contacts list --format json
macos-data contacts get --external-id <id> --format json
macos-data contacts query --name "..."
macos-data contacts query --phone "..."
macos-data contacts query --email "..."
macos-data contacts query --url "..."
macos-data contacts query --organization "..."
macos-data contacts query --postal-code "..."
macos-data contacts create --input contact.json --dry-run
macos-data contacts create --input contact.json --apply
macos-data contacts edit --external-id <id> --input contact.json --dry-run
macos-data contacts edit --external-id <id> --input contact.json --apply
```

查询条件之间使用 AND 语义，单次最多 3 个条件；同一字段不能重复。`--format json` 不计入条件数量。

计划中的命令示例：

```text
macos-data contacts list --format json
macos-data contacts get --query '{...}' --format json
macos-data contacts create --input contact.json --dry-run
macos-data contacts update --input contact.json --apply
macos-data contacts export --format vcard
```

更新和导出命令当前尚未实现。创建联系人必须显式选择 `--dry-run` 或 `--apply`，并要求 `external_id`。

## 设计边界

- 不复制 Apple SDK 或重新分发 Apple 二进制
- 不直接读写 Contacts 内部数据库
- 不使用 Apple 私有 API
- 不依赖 GUI 自动化、屏幕坐标或 AppleScript 作为核心写入路径
- 不把 Apple 联系人 identifier 当作跨系统稳定主键
- 不上传联系人、地址、电话或头像数据
- 不内置 AI Agent
- 不把 Obsidian 作为公共数据协议的必要组成部分

## 平台

计划最低支持 macOS 26.0+。项目使用 Swift Package Manager，并优先采用 Apple 公共 Framework。

Contacts 数据访问需要用户授予系统权限。CLI 应负责检查权限、说明授权状态，并在写入前要求明确确认。

Homebrew 更新、Gatekeeper、quarantine 处理和本地发布验证流程，请参阅 [`docs/development/distribution-signing.md`](docs/development/distribution-signing.md)。

## 后续方向

后续版本可能增加 vCard、批量操作和变更检测，并逐步支持 Calendar、Reminders、Notes、Mail 等 Apple 公共 Framework。每个 adapter 都应独立定义权限要求、数据映射、错误格式和测试策略。

## 许可证

请参阅 [LICENSE](LICENSE)。
