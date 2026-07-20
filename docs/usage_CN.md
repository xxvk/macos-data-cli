# 使用说明

`macos-data` 是一个本地 Terminal CLI。它通过 Apple 公共 Framework 访问 macOS 数据，Agent 不需要专用集成即可调用。

## Contacts

列出当前 Contacts 容器：

```text
macos-data contacts containers --format json
```

默认使用已经验证的 iCloud 容器。也可以显式指定 `iCloud` 或列表返回的
精确的 iCloud container identifier：

```text
macos-data contacts list --container iCloud --format json
macos-data contacts get --external-id <id> --container <icloud-container-id> --format json
```

不存在或非 iCloud 的 container 会直接报错，不会静默回退到本地或
Exchange 账户。

当前版本只使用 iCloud Contacts 容器：

```text
macos-data contacts container
```

如果找不到 iCloud 容器，所有写入操作都会拒绝，不会回退到本地或其他账户。

导出 JSON 快照：

```text
macos-data contacts export --format json
macos-data contacts export --format json --output contacts-snapshot.json
```

`list` 用于实时读取；`export` 用于生成可保存、审计或交给 Agent 批量处理的快照。

带有 `--format json` 的失败响应也使用结构化格式：

```json
{"ok":false,"error":{"code":"CONTACT_QUERY_ERROR","message":"..."}}
```

写入命令使用 `--format json` 时，会在 `data.contact` 返回保存后的联系人
状态，并同时返回操作名称。delete 返回删除前最后读取到的联系人状态：

```json
{"ok":true,"data":{"operation":"updated","contact":{}}}
```

External ID migration 会在 `data.contact` 返回迁移后的联系人，并同时返回
`from` 和 `to` 标识。

检查权限和联系人数量：

```text
macos-data contacts permission
macos-data contacts count
macos-data contacts count --format json
```

JSON 响应使用独立于 CLI 发布版本的 contract `0.1`。成功 envelope 包含
`ok`、`contractVersion` 和 `data`；错误 envelope 包含 `ok`、
`contractVersion` 和 `error`。

以 JSON 读取联系人：

```text
macos-data contacts list --format json
macos-data contacts get --external-id <id> --format json
```

查询支持多个条件，条件之间使用 AND 语义；单次最多三个不同字段：

```text
macos-data contacts query --name "张三"
macos-data contacts query --kind organization
macos-data contacts query --phone "+81"
macos-data contacts query --email "person@example.com"
macos-data contacts query --url "example.com"
macos-data contacts query --organization "Example"
macos-data contacts query --postal-code "10001"
```

从 JSON 创建联系人。写入前应先查看 dry-run：

通过 CLI 创建的每个联系人都必须在 JSON 中包含 `externalID`。外部创建且
没有 external ID 的联系人可以被读取，但 CLI 不会创建或管理没有 ID 的新记录。

```text
macos-data contacts create --input contact.json --dry-run
macos-data contacts create --input contact.json --apply
cat contact.json | macos-data contacts create --stdin --dry-run
cat contact.json | macos-data contacts create --stdin --apply --idempotent
macos-data contacts edit --external-id <id> --input contact.json --dry-run
macos-data contacts edit --external-id <id> --input contact.json --apply
cat patch.json | macos-data contacts edit --external-id <id> --stdin --dry-run
```

第一版通过 `kind` 区分 `person` 和 `organization`。`external_id` 只能存储在 label 为 `macos-data-cli` 的 URL 中，value 格式为 `x-macos-data://external-id/<id>`。其他 URL label 都按普通网址处理。CLI 默认选择已经验证的 iCloud 容器，也可以显式指定 `--container iCloud` 或准确的容器 identifier。

默认情况下重试仍保持严格行为。只有在确认相同 external ID 的持久化字段
等价时，才应给 create 添加 `--idempotent`。JSON-only metadata 和头像可用性
不参与比较；持久化字段不同会返回冲突。删除命令可以添加
`--ignore-not-found`，让已经删除的联系人在重试时返回成功。

读取结果包含 `imageAvailable` 字段。它表示 Contacts.framework 当前报告的
头像数据可用性，不能当作 Contacts.app 是否显示 iCloud 头像的绝对事实。
头像 apply 结果还会包含 `avatar.status`：`readback_confirmed` 表示强回读确认；
`verification_unknown` 表示保存已接受，但 Framework 无法安全读回头像。此时应遵循
`avatar.nextAction`，不能自动重试、删除或重建联系人。

普通编辑不会修改 `external_id`。如果输入 JSON 包含 `externalID`，它必须与 `--external-id` 完全一致；修改 external ID 应单独设计迁移功能。

如果写入返回 CoreData 错误 `134092`，说明 macOS Contacts 记录可能已经损坏或无法保存。应先保留 JSON 表示，再明确确认删除并重新创建联系人，然后重试。`macos-data` 不会自动执行这个破坏性恢复操作。

头像使用独立参数写入，不进入普通联系人 JSON：

```text
macos-data contacts edit --external-id <id> --image ./avatar.png --dry-run
macos-data contacts edit --external-id <id> --image ./avatar.png --apply
```

只读验证已有头像，不会写入联系人：

```text
macos-data contacts avatar verify --external-id <id> --format json
```

结果可能是 `readback_confirmed`、`not_available` 或
`verification_unknown`。轻量预检为 false 时会返回
`verification_unknown`，不会强行读取可能触发 fault 的 `imageData`。

如果已有 iCloud 联系人无法安全原地编辑头像，可以使用独立的替换流程。
该流程会保留 JSON 联系人字段，但会创建新的 Contacts 记录，因此必须明确确认：

```text
macos-data contacts avatar replace --external-id <id> --image ./avatar.png --dry-run
macos-data contacts avatar replace --external-id <id> --image ./avatar.png --apply --confirm "RECREATE CONTACT"
```

头像输入上限为 10 MB，处理后最长边不超过 1024 px，最终文件不超过 200 KB。超过输入上限、无法解码或无法压缩到目标大小时，CLI 会报错且不会修改联系人。

普通编辑是 partial update：未出现的字段保持原值；显式写入 `null` 会清空该字段。

### metadata 规则（0.1）

`metadata` 是 JSON contract 字段。0.1 版本会在 JSON 读取、编辑预览和 export 中保留它，但不会写入 Apple Contacts。这样不会把项目私有结构误写入 Notes 或其他联系人字段。

删除单条联系人必须使用 `external_id`。先预览：

```text
macos-data contacts delete --external-id <id> --dry-run
```

确认删除：

```text
macos-data contacts delete --external-id <id> --apply --confirm "DELETE CONTACT"
```

迁移 external ID 必须使用独立命令。先预览：

```text
macos-data contacts external-id migrate --from <old-id> --to <new-id> --dry-run
```

确认无误后写入：

```text
macos-data contacts external-id migrate --from <old-id> --to <new-id> --apply --confirm "CHANGE EXTERNAL ID"
```

完整的数据格式、错误行为和安全规则请参阅[开发规则](development/rules_CN.md)，本机验证记录请参阅[本机 Contacts 测试数据](development/local-contacts-fixture.md)。
