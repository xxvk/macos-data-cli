## 什么是 mpia

`mpia` 的核心产品形态是一个面向 Agent 与开发者的本机 macOS 数据访问 CLI。它让不同 Agent 无需依赖特定厂商或客户端，只需通过统一、可发现、机器可读的命令契约，即可方便地访问 macOS 数据。底层优先使用 Apple 公共框架；在没有公共框架时，使用窄范围、文档化的本地适配器，并保持 fail-closed 的读写边界。它只在本地运行，绝不上传通讯录、邮件、照片或笔记。

## 安装与 TCC

**Homebrew Cask 是第一优先、最推荐的安装方式：**

```bash
brew tap xxvk/tap
brew install --cask mpia
```

bundle 标识符为 `com.xvk.mpia.cli`。访问受保护的 macOS 数据时，请把通讯录、日历、提醒事项、照片、完全磁盘访问或自动化权限授予 Homebrew 安装的 `mpia` app bundle。授予 TCC 权限时不要用裸二进制代替它。

## macOS 演示 App（规划中）

未来将提供一个 SwiftUI macOS 演示 App，用于直观体验 mpia 的权限、资源发现及受保护读写流程。CLI 与机器可读契约仍是正式接口。

## 其他说明

### 安全边界

- 只读命令永不修改用户数据。
- 写操作需要显式 `--dry-run`（预览）或 `--apply`（持久化）。
- 破坏性操作除 `--apply` 外还需精确确认短语（例如 `DELETE CONTACT`）。
- 歧义匹配会被报告，绝不静默自动选择。
- `outcome_unknown` 结果绝不自动重试。

### 机器可读契约

每个命令都返回 JSON：

```json
{ "ok": true, "contractVersion": "0.1", "data": {} }
```

通过以下命令获取命令注册表：

```bash
mpia GET "/agent/manifest"
```
