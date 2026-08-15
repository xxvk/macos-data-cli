## 什么是 mpia

`mpia` 是面向 agent 与开发者的本机 macOS 数据访问层，优先使用 Apple 公共框架；在没有公共框架时，使用窄范围、文档化的本地适配器，并保持 fail-closed 的读写边界。它只在本地运行，绝不上传通讯录、邮件、照片或笔记。

## 安全边界

- 只读命令永不修改用户数据。
- 写操作需要显式 `--dry-run`（预览）或 `--apply`（持久化）。
- 破坏性操作除 `--apply` 外还需精确确认短语（例如 `DELETE CONTACT`）。
- 歧义匹配会被报告，绝不静默自动选择。
- `outcome_unknown` 结果绝不自动重试。

## 适配器

通讯录、邮件（只读）、日历、提醒事项、照片、笔记、快捷指令和 Safari 各自维持明确的权限与读写边界。

## 安装与 TCC

bundle 标识符为 `com.xvk.mpia.cli`。自 0.9.0 从 `macos-data` 改名后，macOS 会把它当作全新应用：通讯录、日历、提醒事项、照片、完全磁盘访问与自动化都需重新授权。要进行 TCC 授权的读取，请运行签名 app bundle，而非裸二进制。

## 机器可读契约

每个命令都返回 JSON：`{ "ok": true, "contractVersion": "0.1", "data": … }`。命令注册表可通过 `mpia manifest --format json` 获取。
