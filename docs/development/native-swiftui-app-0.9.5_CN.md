# mpia-cli 0.9.5：原生授权宿主与可视化命令控制台

状态：`planned`

本文只记录未来实施计划，不代表 0.9.5 已实现、已验证或已授权发布。
当前 `VERSION` 不因本计划变更；实施、版本提升、提交、tag、push 与发布需要分别授权。

## 目标

将 mpia 从“CLI 包装成 App”升级为真正的 SwiftUI macOS 产品：

- `mpia.app` 是唯一稳定的 TCC 权限与 adapter 执行主体。
- App 内嵌 `mpia` CLI；CLI 通过本机受限 IPC 请求 App 执行，不再直接访问系统数据。
- GUI 覆盖 Manifest 中全部 106 条 route、11 个主题。
- 每条命令都有自动生成的参数表单、执行入口和结果视图。
- 每个主题至少提供一个优化后的领域视图。
- 权限首页采用“状态、用途、授权、重新检查”的设置中心模式，并扩展为完整操作控制台。
- 0.9.5 承接原 `1.0.0-d` GUI 主体；1.0.0 只保留体验打磨、Developer ID、
  公证和正式发布。

## 架构与契约

### App、Runtime 与 CLI 分层

将现有执行逻辑拆为：

- `MPIARuntime`：dispatcher、adapter handlers、schema validation 和事务安全。
- `MPIAIPC`：App 与 CLI 共用的版本化请求/响应协议。
- `MPIAApp`：SwiftUI、权限宿主和后台执行服务。
- `mpia`：App Bundle 内的薄 CLI 客户端。

App Bundle 目标结构：

```text
mpia.app/
  Contents/MacOS/mpia-app
  Contents/Helpers/mpia
  Contents/Resources/...
```

CLI 接口保持不变：

```text
mpia METHOD /path --params ... --body ...
```

CLI 执行流程：

1. 连接用户专属 Unix socket。
2. App 未运行时自动启动并进行有界等待。
3. 发送结构化 route 请求。
4. App 使用同一 `CLIDispatcher` 执行并返回现有 JSON contract。
5. 无 GUI session 或协议不兼容时 fail-closed。

新增稳定错误：

```text
APP_HOST_UNAVAILABLE
IPC_PROTOCOL_MISMATCH
MANIFEST_HASH_MISMATCH
APP_PERMISSION_REQUIRED
APP_UPDATE_REQUIRED
```

IPC socket 权限为 `0600`，不接受 shell、任意 executable 或参数数组；请求大小、
deadline 和输出限制沿用 0.9.3。

### Manifest 驱动 GUI

扩展 route metadata：

- 稳定 `routeId`
- `topic`
- 本地化标题 key
- 所需权限列表
- 参数和结果展示提示
- 推荐结果布局
- 风险等级与现有 safety contract

GUI 不手写第二份命令表。门禁必须证明：

- 106/106 route 都能从 Manifest 生成 GUI。
- 每个 route 只出现一次。
- 参数、body schema、确认短语和读写属性与 CLI 完全一致。
- Manifest 新增 route 时，没有 GUI metadata 就构建失败。

## 权限中心

首页显示以下能力：

- Contacts
- Calendar
- Reminders
- Photos
- Full Disk Access 能力探针
- Mail、Notes、Safari、Shortcuts 的逐目标 Automation
- Shortcuts GUI 辅助操作所需 Accessibility
- CLI 安装状态
- Runtime/IPC 状态
- Login Item 状态

状态枚举：

```text
not_determined
authorized
partial
denied
restricted
manual_action_required
restart_required
unavailable
```

首次启动采用逐项引导：

1. 解释用途和影响范围。
2. 用户点击 Start Setup。
3. App 逐项发起系统支持的请求。
4. Full Disk Access 等不能直接请求的权限打开准确设置页。
5. 返回 App 后自动重新检查。

不请求当前功能不需要的 Camera、Microphone 或 Screen Recording。App 只能发起请求和
回读，macOS 最终授权仍由用户确认。

## SwiftUI 信息架构

使用 `NavigationSplitView`：

- Home / Permissions
- 11 个 adapter 主题
- Commands
- Recent Activity
- Settings

每条 route 页面包含：

- 命令用途与权限要求
- Schema 生成的参数和 body 表单
- 文件参数使用原生文件选择器
- Advanced JSON 编辑模式
- Preview / Dry Run
- Apply
- 结果表格、树、详情或 Raw JSON
- Copy、Export 当前结果
- 错误与权限修复建议

每个主题的首个领域视图：

- Contacts：联系人表格与详情
- Calendar：事件列表或时间线
- Reminders：按列表分组
- Notes：列表与正文预览
- Mail：邮件 metadata 列表
- Messages：会话摘要
- Phone：最近通话表
- Photos：相册或缩略图网格
- Safari：书签树
- Shortcuts：快捷指令列表
- Agent：Manifest/route explorer

## 写入安全闭环

GUI 写操作保持：

```text
form
-> preview/dry-run
-> diff
-> explicit confirmation
-> apply
-> read-back
-> final status
```

- 普通写入使用独立确认 sheet。
- 破坏性操作必须输入 Manifest 中的精确确认短语。
- preview 后任何对象、参数、权限或 Manifest 漂移都会使计划失效。
- GUI 不缓存授权、不替用户确认。
- CLI 与 GUI 使用同一个 mutation contract。

## 生命周期、安装与隐私

- App 默认注册为 Login Item，登录后隐藏启动。
- 关闭窗口后保留菜单栏服务，CLI 可继续使用。
- 菜单栏提供 Open mpia、Runtime Status 和 Quit。
- App 设置页提供 Install Command Line Tool。
- 优先安装到已有且可写的 Homebrew bin；否则使用 `~/.local/bin` 并提示 PATH。
- 保留 Bundle ID `com.xvk.mpia.cli`，避免不必要的 TCC identity 迁移。
- 0.9.5 使用每台机器本地生成、不得提交或同步的自签名证书。
- 验证连续两次构建的 designated requirement 稳定；不满足时阻止 0.9.5 验收。
- 完整版保持非沙盒；1.0.0 再切换 Developer ID、公证和官网/Homebrew 分发。
- 中、日、英三语随系统自动选择，并允许设置覆盖。
- 执行历史只保存 route、时间、状态、耗时和事务 ID；不保存 params、body、正文、
  路径或结果。
- 普通历史保留 30 天或最多 1,000 条；事务证据遵循原有安全记录规则。
- 完整结果仅存在当前会话内存，退出 App 后清除。

## 实施顺序

1. `GUI-01`：冻结 0.9.5 contract、Bundle、签名和权限模型。
2. `GUI-02`：把 dispatcher/handlers 从 CLI target 提取到共享 Runtime。
3. `GUI-03`：实现 Unix socket 服务、薄 CLI、自动唤醒和协议门禁。
4. `GUI-04`：实现 SwiftUI App、Login Item、菜单栏和权限中心。
5. `GUI-05`：实现 Manifest/Schema 驱动的 106 条命令表单。
6. `GUI-06`：完成 11 个领域视图与事务化写入闭环。
7. `GUI-07`：CLI 安装器、三语、本地历史、无障碍和诊断。
8. `GUI-08`：live-Mac 权限验收、文档、Roadmap reconciliation 和 release gate。

0.9.4 的后台 Mac Runner 将复用相同 App Host/IPC，不再建立第二个 TCC 主体；
0.9.5 不负责实施公网 Gateway。

## 测试与验收

自动化测试必须覆盖：

- 106 条 route 的 GUI 覆盖率与 Manifest 漂移。
- 所有参数类型、JSON Schema、文件选择和默认值。
- IPC 权限、请求上限、超时、并发、stale socket 和协议不匹配。
- App 未运行时自动启动；无 GUI session 时稳定失败。
- dry-run、确认短语、stale preview、apply 和 read-back。
- mock permission 的全部状态转换。
- 历史记录不落盘敏感数据。
- 中日英字符串完整性、键盘操作、VoiceOver label 和高对比度。
- 所有手写 Swift 文件遵守 300 行硬限制。

Live-Mac 验收：

- App 成为权限保护操作的实际执行进程。
- Contacts、Calendar、Reminders、Photos、Automation、FDA 和 Accessibility 均可引导及回读。
- 关闭主窗口后，Terminal 中的 `mpia HEAD /version` 和至少一条受保护读取仍成功。
- 11 个主题各完成一条真实 GUI 操作。
- 至少一个可逆写入完成 preview、apply 和 read-back。
- 连续两次自签名更新后授权状态保持稳定。
- CLI 与 GUI 对同一路由产生等价 JSON 结果。
- 完整 Swift tests、CLI contracts、GUI tests、Release build、签名检查和
  `git diff --check` 通过。

## 假设与非目标

- 0.9.5 以完成并稳定的 0.9.3 REST-style CLI/Manifest 为基础；当前未提交的
  0.9.3 工作不得被 GUI 开发混入或覆盖。
- macOS 26 为最低系统版本。
- 0.9.5 不实现云端 Gateway、不提交发布凭据，也不申请 Apple Developer 账号。
- `VERSION` 在全部验收通过前保持当前已发布状态；版本提升、commit、tag、push 和发布
  分别授权。
- Roadmap 中原 `1.0.0-d Demo SwiftUI App` 的重复范围在未来实施时改为引用 0.9.5；
  1.0.0 聚焦正式签名、公证、安装体验和产品发布。
