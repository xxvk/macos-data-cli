# Safari adapter 0.8 架构

## 决策

Safari 0.8 采用明确的混合边界：

- 书签和阅读列表通过 Foundation 只读加载
  `~/Library/Safari/Bookmarks.plist` 的有界快照；
- 新增阅读列表使用 Safari scripting dictionary 公开的
  `add reading list item`，通过五秒 Apple Event 执行；
- 0.8.0 永不直接写 `Bookmarks.plist`、Safari 数据库、缓存或 iCloud metadata；
- 0.8.1 第一优先验证直接 plist 写入；只有该 gate 无法证明本机与 iCloud
  安全时，才考虑其他 mutation 路线。

Apple 的 Safari 导出格式也把阅读列表定义为 `com.apple.ReadingList`
folder；本机 Safari 27 plist 使用同一个标识。

## 0.8.0 读取 contract

parser 接受 binary/XML plist，输入最大 32 MiB，最多遍历 50,000 个节点、
深度 64；未知类型、重复 Reading List container 或结构损坏一律 fail closed。
它区分普通 folder、普通 bookmark、唯一 Reading List subtree，并忽略 Safari
内部 proxy 节点。

原始 Safari UUID 会转换为 adapter 管理的 SHA-256 opaque ID。URL、标题、
preview、UUID 和文件路径都不得进入诊断日志。cursor 同时绑定 filter 与准确
plist SHA-256；Safari 数据一旦变化，旧 cursor 必须返回 stale，而不是继续使用
可能漂移的 offset。

Reading List 的 `DateLastViewed` 映射为 `isRead`。字段不存在只表示当前本机
plist 没有 viewed timestamp，不代表另一台设备尚未完成的 iCloud 状态。

## Reading List 新增

输入只能来自 stdin 或一个非 symlink 本地文件，并使用严格 JSON：

```json
{
  "url": "https://example.com/article",
  "title": "可选标题",
  "previewText": "可选预览"
}
```

只接受不含内嵌账号密码的 HTTP/HTTPS URL。总输入上限 16 KiB，URL 4,096
bytes，title 500 字符，preview 4,096 bytes。dry-run 必须在构造或调用 mutation
bridge 前返回；已存在的标准化 URL 是安全 no-op。

apply 需要 Safari Automation 权限。AppleScript 对所有值转义并设置五秒
deadline。Apple Event 成功后立即重新读取 plist：

- `readback_confirmed`：已找到相同标准化 URL；
- `save_accepted_readback_pending`：Safari 已接受，但尚未落盘；稍后 query，禁止自动重试；
- `outcome_unknown`：超时或事件中断；先 query，禁止自动重试。

## 0.8.0 真实 gate 证据

稳定 Debug app 已获得 Safari Automation，同时保持 plist 可读。明确授权的一次性 add 返回
`save_accepted_readback_pending`，调用方没有重试；随后使用原始完整 URL query，找到唯一 opaque
item。取得单独 action-time 确认后，Safari UI 使用完整唯一 URL 搜索并只删除该结果；筛选 UI
变为空，最终准确 URL CLI query 也返回零 item。任何既有 bookmark 或 Reading List 项都未作为
fixture。

## 为什么不操作 SQLite

本机书签和 Reading List 的主数据是 `Bookmarks.plist`。`History.db`、
`CloudTabs.db` 等数据库服务于其他 Safari 功能，不是本 adapter 的 mutation
目标。

## 0.8.1 直接 plist 写入 gate

直接修改代码量很小，但 iCloud sync contract 没有公开，因此必须按以下顺序验证：

1. 只在 synthetic fixture 和复制品上完成 parser/serializer round trip；保留未知
   key、Date/Data 类型、顺序、mode、owner 与 xattr。
2. 创建 mode `0600` 的私有 recovery backup；只记录源 SHA-256、inode、size、mtime、
   schema version 和 xattr 名称，不记录内容。
3. 退出 Safari，证明没有 Safari process 持有 plist，并连续两次观察到稳定文件；
   不终止无关 iCloud process，也不关闭 Safari iCloud sync。
4. 在有人值守的短窗口内，只新增一个唯一 disposable folder/bookmark；使用原子替换，
   禁止经过 JSON 重写。
5. 启动 Safari，通过 UI 和 0.8 parser 双重回读 fixture。
6. 必须由用户确认第二台 iCloud 设备出现 fixture；同一台 Mac 重启不算 iCloud 证明。
7. 只删除 disposable fixture，优先让 Safari UI 自己删除，并在两台设备确认消失；
   如果期间已有其他 Safari 变化，不得恢复整个旧 backup。
8. 核对无 duplicate、无旧节点丢失、无 schema drift、无 sync error，并验证所有未触碰
   subtree hash 不变。

只要出现 resurrection、duplicate、旧节点丢失、schema 被拒绝或远端状态无法证明，
实验即失败；禁止自动重试，也不能升级为公开写命令。

## 0.8.1 失败后的备选

Safari AppleScript 只公开 Reading List 新增，没有 bookmark 的 list/create/update/delete。
Shortcuts 可以继续调查已有 Safari action，但它增加一个用户管理层，目前不能证明通用
bookmark CRUD。Safari WebExtension 必须在实际 Safari host 中 feature-detect；仅看到
WebKit 源码不算 Safari 已支持。最后才考虑不使用坐标的语义化 Accessibility。
