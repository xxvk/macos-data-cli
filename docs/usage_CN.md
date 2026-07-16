# 使用说明

`macos-data` 是一个本地 Terminal CLI。它通过 Apple 公共 Framework 访问 macOS 数据，Agent 不需要专用集成即可调用。

## Contacts

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

检查权限和联系人数量：

```text
macos-data contacts permission
macos-data contacts count
```

以 JSON 读取联系人：

```text
macos-data contacts list --format json
macos-data contacts get --external-id <id> --format json
```

查询支持多个条件，条件之间使用 AND 语义；单次最多三个不同字段：

```text
macos-data contacts query --name "张三"
macos-data contacts query --phone "+81"
macos-data contacts query --email "person@example.com"
macos-data contacts query --url "example.com"
macos-data contacts query --organization "Example"
macos-data contacts query --postal-code "10001"
```

从 JSON 创建联系人。写入前应先查看 dry-run：

```text
macos-data contacts create --input contact.json --dry-run
macos-data contacts create --input contact.json --apply
macos-data contacts edit --external-id <id> --input contact.json --dry-run
macos-data contacts edit --external-id <id> --input contact.json --apply
```

第一版通过 `kind` 区分 `person` 和 `organization`。`external_id` 使用保留 URL 格式 `x-macos-data://external-id/<id>` 存储。当前写入 macOS 默认 Contacts 容器；显式容器选择属于后续功能。

普通编辑不会修改 `external_id`。如果输入 JSON 包含 `externalID`，它必须与 `--external-id` 完全一致；修改 external ID 应单独设计迁移功能。

头像使用独立参数写入，不进入普通联系人 JSON：

```text
macos-data contacts edit --external-id <id> --image ./avatar.png --dry-run
macos-data contacts edit --external-id <id> --image ./avatar.png --apply
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
