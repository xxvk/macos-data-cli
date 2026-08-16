# mpia-cli

面向 Agent 和开发者的本地、可脚本化 macOS 数据访问层。

[在线交互文档](https://mpia-cli-doc.vercel.app/) ·
[English README](README.md) ·
[安装说明](INSTALL.md) ·
[路线图](ROADMAP_CN.md)

Agent 操作 macOS 原生数据时，通常只能依赖脆弱的 GUI 自动化、特定平台集成或私有数据格式。
`mpia` 优先采用 Apple 公共 Framework；仅当公共 Framework 无法暴露所需数据时，才使用范围明确、
有文档、fail-closed 的本地 adapter。它只在本机运行，绝不上传你的数据。

## Adapter

`mpia` 提供十个 adapter，每个都是独立的命令组，并拥有各自的权限模型：

| Adapter | 命令 | 数据源 / Framework | 访问方式 |
| --- | --- | --- | --- |
| Contacts | `contacts` | Contacts（iCloud 容器） | 读取 + 受控写入 |
| Mail | `mail` | 本地 SQLite/EMLX + Apple Events 回退 | 只读 |
| Calendar | `calendar` | EventKit（iCloud CalDAV） | 读取 + 受控写入 |
| Reminders | `reminders` | EventKit（iCloud CalDAV） | 读取 + 受控写入 |
| Photos | `photos` | PhotoKit | 读取 + 受控导出 |
| Notes | `notes` | Notes.app Apple Events | 读取 + 受控写入 |
| Shortcuts | `shortcuts` | `/usr/bin/shortcuts` + Shortcuts Events | 运行 + 受控创作/编辑 |
| Safari | `safari` | Bookmarks.plist + Apple Events | 读取 + 受控本地 CRUD |
| Messages | `messages` | `chat.db` SQLite（需 Full Disk Access） | 只读 |
| Phone calls | `phone-calls` | `CallHistory.storedata`（需 Full Disk Access） | 只读 |

各 adapter 的命令详情与示例见[使用说明](docs/usage_CN.md)。

## 快速开始

从源码构建，并获取第一个只读资源快照：

```bash
git clone https://github.com/xxvk/mpia-cli.git
cd mpia-cli
export DEVELOPER_DIR="$(xcode-select -p)"
swift build
.build/debug/mpia resources --format json
```

环境要求：macOS 26 或更新版本、Apple Silicon，以及支持 Swift 6.2 的 Xcode。

## 安装

公开二进制目前尚未经过 Developer ID 签名和公证，因此现阶段从源码构建是最可靠的路径。
完整流程与未签名分发边界见[安装说明](INSTALL.md)。规划中的 Homebrew 流程为：

```bash
brew tap xxvk/tap
brew install --cask mpia
```

受保护数据（Contacts、Calendar、Reminders、Photos、Full Disk Access、Automation）
必须授权给安装的 app bundle（`com.xvk.mpia.cli`），而不是裸可执行文件。

## 使用方法

建议从 capability 与权限检查开始——这些命令不会修改数据：

```bash
mpia resources --format json
mpia contacts permission
mpia mail doctor --format json
mpia phone-calls recent --limit 5 --format json
```

每个命令都返回统一的 JSON envelope：

```json
{ "ok": true, "contractVersion": "0.1", "data": {} }
```

获取完整的机器可读命令注册表：

```bash
mpia manifest --format json
```

## 安全模型

- 只读命令绝不修改用户数据。
- 写入需要显式 `--dry-run`（预览）或 `--apply`（持久化）。
- 破坏性操作除 `--apply` 外还需准确的确认短语（例如 `DELETE CONTACT`）。
- 歧义匹配会被报告，绝不静默选中。
- `outcome_unknown` 结果绝不自动重试。
- 一切都在本机运行；联系人、邮件、照片等数据绝不上传。

## 项目状态

源码已交付上表全部十个 adapter 及机器可读 contract。当前重点是 1.0.0——产品打磨：
文档、Developer ID 签名/公证与 demo app。详见[路线图](ROADMAP_CN.md)与
[变更记录](CHANGELOG.md)。

## 文档

- [使用说明](docs/usage_CN.md) — 各 adapter 命令详情与示例
- [开发规则](docs/development/rules_CN.md) — 安全规则
- [CLI contract](docs/development/cli-contract_CN.md) — JSON envelope 与退出码
- [Agent 集成指南](AGENTS.md)
- [中文路线图](ROADMAP_CN.md) · [English Roadmap](ROADMAP.md)
- [架构决策](docs/development/) — 各 adapter 设计说明

## 核心目标

- 通过 Terminal 使用，安装后即可被脚本和 Agent 调用
- 使用稳定的 CLI 和 JSON contract
- 所有 Agent 共用同一个 CLI，不绑定特定平台
- 优先使用 Apple 公共 Framework，不依赖 GUI 自动化
- 对写操作提供 dry-run 与显式确认
- 在本机运行，不上传用户数据
- 通过独立 adapter 逐步扩展

Obsidian 是项目作者的实际使用场景，但不是公共协议的强制依赖。外部系统可以使用自己的稳定 ID。

## 设计边界

- 不复制或重新分发 Apple SDK 或 Apple 二进制。
- 不使用 Apple 私有 API，也不以 GUI/屏幕坐标自动化作为核心写入路径。
- 不直接访问 Apple 内部数据库。仅在公共 Framework 无法暴露数据时保留有文档的例外：
  Mail 的只读本地索引/EMLX、Messages `chat.db`、Call History `CallHistory.storedata`。
  每个 adapter 都在运行时校验 schema、fail closed，且永不写入这些文件。
- 不把 Apple 联系人 identifier 当作跨系统稳定主键。
- 不上传联系人、地址、电话、图片或其他用户数据。
- 不内置 AI Agent。
- 不把 Obsidian 作为公共数据协议的必要组成部分。

## 平台

最低支持 macOS 26.0+，使用 Swift Package Manager 构建，优先采用 Apple 公共 Framework。

## 社区参与

- 提出行为或 contract 变更前，请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。
- 安全问题请使用 [SECURITY.md](SECURITY.md) 说明的私密报告路径。
- 参与本项目时请遵守 [Code of Conduct](CODE_OF_CONDUCT.md)。

## 许可证

请参阅 [LICENSE](LICENSE)。
