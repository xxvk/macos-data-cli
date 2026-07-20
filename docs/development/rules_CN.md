# 开发规则

## 测试驱动流程

每个新功能都遵循以下流程：

1. 先定义 CLI 行为和 JSON contract。
2. 先增加一个失败的单元测试或集成测试。
3. 用最小改动让测试通过。
4. 运行完整测试套件。
5. 如果涉及 macOS Framework，则构建 release、安装本地版本，并用真实 CLI 验证。
6. 更新使用说明和路线图状态。

测试不能在每次运行时重复创建真实联系人。映射和匹配使用确定性的纯测试；端到端验证使用文档中记录的本机测试联系人。

真实 Contacts CLI 集成测试与 `swift test`、CI 分离，默认只执行读取和
dry-run：

```bash
bash scripts/run_local_contacts_integration.sh
```

验证进程级 JSON contract 和错误路径时，运行：

```bash
bash scripts/run_cli_contract_tests.sh
```

该测试仅在本机运行，不会写入或删除 Contacts 记录。

只有在明确验证真实写入时，才执行一次性联系人流程：

```bash
bash scripts/run_local_contacts_integration.sh --with-writes
```

写入流程只创建并清理临时集成联系人，不能对固定的 person、organization
或 create smoke-test 联系人执行删除。

## Contacts contract

- `kind` 只有 `person` 和 `organization`，来源是原生 Contacts 记录类型。
- 读取模型中的 `external_id` 可以为空，但创建联系人时必须提供。
- CLI 永远不得创建没有 `external_id` 的联系人；这是 Contacts 的固定规则，不是未来待办功能。
- `external_id` 使用 `x-macos-data://external-id/<id>` 写入 URL 字段。
- 保留 URL 的 label 必须严格为 `macos-data-cli`；读取端不得把 `Homepage` 或其他 label 识别为 `external_id`。
- 保留 URL 的 value 格式为 `x-macos-data://external-id/<id>`。
- `imageAvailable` 只表示 Contacts.framework 报告的头像数据可用性，不能据此断言 Contacts.app 是否显示 iCloud 头像。
- 头像 apply 结果包含 `avatar.status`：`readback_confirmed` 表示保存后成功读回非空头像数据；`verification_unknown` 表示保存已接受，但 Contacts.framework 无法安全读回头像。Agent 应遵循 `avatar.nextAction`，不能自动删除、自动重建或自动重试头像写入。
- `contacts avatar verify` 会先进行轻量头像可用性预检；预检为 false 时跳过 `imageData` 读取，以降低 iCloud fault 风险。
- `contacts avatar replace` 是无法原地编辑头像时的明确恢复流程。它要求确认短语 `RECREATE CONTACT`，会创建新的 Contacts 记录，绝不能自动调用。
- 如果写入时出现 CoreData 错误 `134092`，CLI 必须认为该记录可能已损坏，保留诊断信息，并提醒 Agent 先保存 JSON 字段、在明确确认后删除并重新创建联系人，再重试操作。CLI 不得自动删除或自动重建联系人。
- Apple 联系人 identifier 只是本地实现细节，不能作为跨系统 ID。
- 查询按字段类型做规范化；组合查询使用 AND 语义，最多三个不同字段。
- 多条匹配必须返回歧义错误，不能静默选择联系人进行写入。

## 安全与隐私

- 读写前都必须检查 Contacts 权限。
- 写入必须显式选择 `--dry-run` 或 `--apply`。
- 不直接访问 Contacts 私有数据库，也不上传联系人数据。
- 0.1 只允许 iCloud 容器；找不到时必须拒绝写入，不得回退到本地或其他账户。
- 诊断日志只保留 `external_id` 作为关联键。邮箱、国际电话号码、绝对路径
  和底层异常文本在写入 `~/Library/Logs/macos-data-cli/diagnostics.log`
  前必须脱敏。
- 诊断日志不得包含姓名、组织、邮政地址、头像二进制数据或完整联系人 JSON。

## 兼容性

当前最低部署目标为 macOS 26.0+。使用仓库约定的 Swift/Xcode 工具链，并将 Framework 可用性检查放在 adapter 边界附近。

进行兼容性验证时，必须先重新构建 Release 配置再测试二进制；旧的 `.build/release/macos-data` 可能不包含最新源码改动。

## Metadata（0.1）

`metadata` 只属于 JSON contract。Contacts 0.1 不保证把它写入 Apple Contacts；不得偷偷写入 Notes、URL 或其他字段。未来如需持久化，必须先定义版本化编码和迁移规则。

普通读取不得请求头像二进制。头像验证先进行轻量可用性预检；无法安全原地编辑的记录必须使用明确确认的头像替换/重建流程。
