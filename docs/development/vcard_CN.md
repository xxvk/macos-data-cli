# vCard 未来 TODO

## 当前标准状态

当前 vCard 的基础规范是 2011 年发布的 vCard 4.0，由 [RFC 6350](https://www.rfc-editor.org/info/rfc6350/) 定义。后续 RFC 对它进行了参数编码、JSContact 转换等扩展，但没有发现已经发布的 vCard 5.0 规范或确定的发布时间。因此当前实现不应等待假想中的 vCard 5.0。

## 在 macos-data-cli 中的定位

vCard 应作为有损的联系人交换格式，而不是 Agent 的权威 contract。JSON 仍然是权威格式，因为它可以明确保存 `external_id`、`kind`、metadata、头像限制和 macOS 特有行为。

## 计划映射

| macos-data-cli | vCard 4.0 | 兼容性说明 |
|---|---|---|
| `givenName`、`familyName` | `N` | 标准字段 |
| 显示名称 | `FN` | vCard 必需字段 |
| `organizationName` | `ORG` | 标准字段 |
| `jobTitle` | `TITLE` | 标准字段 |
| 邮箱 | `EMAIL` | 标准字段 |
| 电话 | `TEL` | 标准字段 |
| 普通网址 | `URL` | 标准字段 |
| 邮政地址 | `ADR` | 需要结构化转义 |
| 头像 | `PHOTO` | 客户端支持程度不同 |
| 人员 / 组织 | `KIND:individual` / `KIND:org` | 不保证所有客户端保留 |

## External ID 方案

可以导出为：

```text
UID:xvk-test-contacts-001
X-MACOS-DATA-EXTERNAL-ID:xvk-test-contacts-001
```

`UID` 是最接近标准的字段，但不同软件可能把它当作自己的联系人记录 ID。`X-` 字段表达更明确，却可能被其他软件丢弃。导入时应同时识别两者，优先使用项目扩展字段，并在 ID 丢失时明确报告。

macOS Contacts 中仍以保留 URL 作为权威存储：

```text
x-macos-data://external-id/<id>
```

## 头像方案

vCard 4.0 支持 `PHOTO`，可以嵌入图片数据，也可以使用 URI。导出时应使用 CLI 已经处理过的头像，并遵循当前 200 KB 限制。导入时支持嵌入的 PNG/JPEG，同时遵守 10 MB 输入上限、1024 px 尺寸限制和 200 KB 输出限制。

## TODO

- 实现单联系人和联系人集合的 vCard 4.0 导出。
- 实现支持折行、转义和 UTF-8 的解析器。
- 将普通 URL 与 external ID 保留 URL 分开处理。
- 导出 `UID` 和 `X-MACOS-DATA-EXTERNAL-ID`，并明确说明可能有损。
- 定义缺少、重复或变更 ID 时的导入冲突策略。
- 在 Apple Contacts 和至少一个其他客户端中验证 `KIND:individual` 与 `KIND:org`。
- 验证内嵌 PNG/JPEG `PHOTO` 的往返和大小规范化。
- 不让 vCard 转换替代 Contacts JSON contract。

