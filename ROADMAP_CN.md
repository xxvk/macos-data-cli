# macos-data-cli Roadmap

## 当前状态

项目处于从零开始的设计与原型阶段。当前还没有可执行的正式 CLI 命令；README 中出现的命令属于计划中的接口设计，不代表当前版本已经实现。

项目的长期目标是建立一个通用的 macOS 原生数据访问基础设施，让不同 Agent 和脚本通过统一的 CLI 与 JSON contract 使用 Apple 公共 Framework。项目不绑定 Codex、Claude Code 或其他特定 Agent 平台。

## 已确定的 0.1 设计决策

- `external_id` 作为通用 JSON 字段；Contacts adapter 优先将其写入 URL 字段，不依赖 Contacts Notes entitlement。
- 账户或容器必须可以显式指定；第一版优先支持能够与 iCloud Contacts 同步的容器。
- JSON contract 支持 `metadata`，但 0.1 不保证将任意 metadata 写入 Contacts。
- 删除操作必须使用显式确认短语，并继续要求 `--apply`。
- 项目最低目标为 macOS 26+；macOS 27 beta 可作为开发和兼容性测试环境，不作为当前稳定支持基线。

## 0.1：Contacts adapter

第一版先聚焦 macOS Contacts，目标是在 macOS 26.0+ 上提供本地、CLI-first 的联系人访问能力。开发期间可以使用 macOS 27 beta 做前置测试。

### CLI 基础

- [ ] 创建 Swift Package 和 CLI 入口
- [ ] 支持 `--help` 和 `--version`
- [ ] 定义稳定的 JSON 输入与输出格式
- [ ] 定义稳定的退出码和错误格式
- [ ] 支持从标准输入或 JSON 文件读取数据

### 权限与安全

- [x] 检查 Contacts 读写权限
- [ ] 在 CLI 内提供清晰的授权提示
- [ ] 权限不足时返回可操作的错误信息
- [ ] 写入默认使用 dry-run，必须显式确认 apply
- [ ] 日志默认不输出联系人敏感内容

### 读取能力

- [x] 列出联系人并输出 JSON
- [x] 通过 `external_id` 获取单个联系人详情
- [x] 按姓名、电话、邮箱、网址、组织和邮编查询联系人
- [x] 支持最多三个条件的 AND 组合查询
- [x] 创建联系人 dry-run 和 apply 基础流程
- [x] 创建前检查重复 `external_id`
- [x] 支持个人和组织联系人
- [x] 通过 `kind` 区分个人和组织联系人
- [ ] 支持姓名、组织、职位、邮箱、电话、网址、地址和头像
- [x] 支持 JSON 输出

### 匹配能力

- [ ] 支持可选的通用 `external_id`
- [ ] 支持组织名称、邮箱、电话等多因素匹配
- [ ] 匹配到多个结果时返回 `ambiguous`
- [ ] 歧义状态下禁止自动写入
- [ ] 将匹配策略与 Contacts Framework 映射逻辑分离

### 写入能力

- [ ] 创建联系人
- [ ] 更新联系人
- [ ] 删除联系人
- [ ] 支持 `--dry-run` 和 `--apply`
- [ ] 输出写入前后的差异
- [ ] 写入后重新读取并返回最终状态
- [ ] 保证重复执行时尽可能幂等

### 数据模型

- [ ] 定义通用联系人 domain model
- [ ] 定义 Contacts adapter 的字段映射
- [ ] 预留 `external_id`
- [ ] 预留 `metadata`
- [ ] 区分通用 JSON contract 与 Apple Framework 专有字段

## 版本路线

每个版本都以一个 macOS 数据域 adapter 为核心。可靠性、Agent 调用、测试、安装和发布不是独立版本，而是每次迭代都必须同步完善的横向能力。

### 0.2：Calendar adapter

- [ ] 基于 EventKit 访问日历和事件
- [ ] 支持日历、事件、时间、地点、参与者和备注
- [ ] 支持事件查询、创建、更新和删除
- [ ] 支持时区和重复事件的明确表达
- [ ] 支持 dry-run、JSON contract 和权限检查

### 0.3：Reminders adapter

- [ ] 基于 EventKit 访问提醒事项
- [ ] 支持提醒列表、标题、备注、截止时间和完成状态
- [ ] 支持提醒的查询、创建、更新和完成
- [ ] 支持列表选择和多因素匹配
- [ ] 支持 dry-run、JSON contract 和权限检查

### 0.4：Notes adapter

- [ ] 评估 Apple Notes 公共 API 的可用范围
- [ ] 支持笔记查询和读取
- [ ] 明确文件夹、附件、链接和富文本的 MVP 边界
- [ ] 在公开 API 能力不足时记录限制，不依赖私有数据库格式
- [ ] 支持权限检查、稳定错误格式和测试

### 0.5：Mail adapter

- [ ] 评估 Mail 相关公开 Framework 的可用范围
- [ ] 明确邮件读取、搜索、草稿和发送的权限边界
- [ ] 优先实现只读查询和结构化 JSON 输出
- [ ] 对发送、删除等高副作用操作设置更高确认等级
- [ ] 不依赖 Mail 内部数据库或 GUI 自动化

### 0.6：Photos adapter

- [ ] 评估 Photos framework 的访问和授权模型
- [ ] 支持照片和相册的只读查询
- [ ] 支持元数据、创建时间、位置和资源引用
- [ ] 明确导出、修改和删除操作的安全边界
- [ ] 支持权限检查、JSON contract 和测试

## 每个版本的横向完成条件

- [ ] 提供 Terminal、标准输入和标准输出调用示例
- [ ] 更新稳定的 Agent 调用 JSON contract
- [ ] 定义统一退出码、错误格式和权限错误处理
- [ ] 读操作输出结构化 JSON
- [ ] 写操作支持 dry-run、差异预览和显式 apply
- [ ] 重复执行时尽可能保持幂等
- [ ] 增加单元测试、fixture 和必要的集成测试
- [ ] 在 macOS 26+ 测试
- [ ] 更新 CLI 帮助、README 和对应 adapter 文档
- [ ] 提供可复现的源码构建方式
- [ ] 在适合发布时更新二进制和 Homebrew 安装方式

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

测试应优先使用 mock 或 fixture，避免单元测试依赖本机联系人、日历等真实数据；真实系统访问放在明确的 CLI 冒烟测试中。

### 本机 Contacts 集成测试 fixture

详细创建和恢复流程见：[Local Contacts Fixture](docs/development/local-contacts-fixture.md)。

当前本机已经创建两条专用测试联系人，分别覆盖个人和组织类型；后续测试不得重复创建：

```text
姓名：macos-data Test Contact
个人：`xvk-test-contacts-001`
组织：`xvk-test-organizations-001`
创建 smoke test：`org-create-apply-001`
URL 格式：`x-macos-data://external-id/<id>`

当前本机只发现一个名为 `iCloud` 的 Contacts 容器；创建 smoke test 已通过默认容器写入并读回验证。显式 `--container` 选择仍属于后续增强。
```

标准验证命令：

```bash
macos-data contacts get --external-id xvk-test-contacts-001 --format json
macos-data contacts get --external-id xvk-test-organizations-001 --format json
macos-data contacts get --external-id org-create-apply-001 --format json
```

Computer Use 只允许用于首次创建或人工恢复这些 fixture。正常开发、测试、Release 构建和 CLI 冒烟测试都不得重新创建联系人。若 fixture 被删除、URL 或类型被修改，应先恢复，再继续测试。

## 长期方向

- [ ] 评估其他 Apple 公共 Framework
- [ ] 建立统一的 adapter 生命周期和能力声明
- [ ] 提供跨 adapter 的批处理和变更检测
- [ ] 支持稳定的版本化 JSON contract

每个 adapter 都应独立定义：权限要求、domain model 映射、读取能力、写入能力、错误格式和测试策略。

## 暂不考虑

- GUI 自动化和屏幕坐标操作
- Apple 私有 API
- 直接读写 macOS 内部数据库
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
