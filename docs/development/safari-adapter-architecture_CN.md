# Safari adapter 0.8 架构

## 决策

Safari 0.8 采用明确的混合边界：

- 书签和阅读列表通过 Foundation 只读加载
  `~/Library/Safari/Bookmarks.plist` 的有界快照；
- 新增阅读列表使用 Safari scripting dictionary 公开的
  `add reading list item`，通过五秒 Apple Event 执行；
- 0.8.0 永不直接写 `Bookmarks.plist`、Safari 数据库、缓存或 iCloud metadata；
- 0.8.1 在 feasibility、recovery、原子替换、rollback 与真实回读 gate 通过后，
  以明确 local-only 的 bookmark/folder CRUD contract 开放受保护的直接 plist 修改；
  它不声称支持 iCloud 同步。

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

### 第一阶段证据：仅私有副本 round trip

synthetic TDD gate 和真实 plist 的 opt-in 自动删除私有副本审计均已通过。真实源文件仅被
读取并保持 byte-for-byte 不变。未知 plist 值、Children 顺序、POSIX mode、owner、group
以及所有源 xattr 的值均被保留；symlink、已存在 destination、重复 UUID、未知节点类型，
以及模拟修改中目标 parent ancestry 以外的任何变化都会 fail closed。

Foundation 对真实 binary plist 的序列化语义稳定，但不保留原始字节：本次源文件为
914,933 bytes，输出为 914,917 bytes。因此后续 mutation gate 必须比较所有未触碰 subtree
的类型化 canonical SHA-256；一旦有意修改一个节点，whole-file byte equality 就不是有效
安全条件。

当前 macOS execution carrier 会向重写文件附加 `com.apple.provenance`，并可能针对每个文件实例
重新生成其值。因此 gate 要求该属性继续存在，但不跨 source、recovery 与 swap candidate 比较它的
digest；其他所有源 xattr 值仍必须准确一致，任何其他新增 xattr 都会 fail closed。

### 第二阶段证据：quiescence 与 recovery

safety gate 在读取前同时检查 Safari app 运行状态和持有准确 plist 的 `lsof` process。间隔
500 ms 的两次 snapshot 必须在 device、inode、size、纳秒 mtime、mode、owner、group、
完整 SHA-256 和全部 xattr-value hash 上一致。随后在 mode 0700 目录写入准确 recovery copy
与不含内容的 JSON manifest，两份文件都是 0600；backup 创建后还必须再次检查 process，
并取得完全相同的第三次 source snapshot。任一步失败都会删除不完整 artifact。

opt-in 真实审计在 Safari 已退出时通过：没有 process 持有 plist，recovery 与 manifest 权限
正确、源文件不变，临时 recovery 目录已删除。TDD 还发现 memory-mapped read 会让程序自身继续
持有 plist，从而触发 gate 自我阻止；因此 gate 改用有界非映射读取。该结果不构成 mutation
授权：未来有人值守的 replacement flow 必须在写入前立即重新运行完整 gate。

### 第三阶段准备：私有副本原子 mutation

真实写入前 writer 只接受绑定 safety snapshot 且 recovery manifest 未被修改的 mutation
plan。它创建同目录 candidate、flush 数据、恢复每一项 source xattr 原值，并验证 mode、owner、
group、SHA-256 和 destination-only provenance policy。replacement 紧邻之前会再次检查 Safari、
打开句柄和完整 source snapshot。

replacement 使用 Darwin `renameatx_np` 的 `RENAME_SWAP`；在新 plist、旧 plist、recovery、
parser 回读以及可选 caller verification 全部通过前，准确旧文件始终保留在 candidate path。
任何验证失败都会 swap-back，并用 recovery 再验证恢复后的 source。stale gate 或被篡改的
manifest 会在 replacement 前被拒绝。

0.8.3 第一次真实尝试正是在 recovery 校验边界暴露了 provenance 的文件实例行为。隐私安全诊断只
记录失败字段，安全门没有放宽任何其他 xattr；针对性回归测试和随后真实 create 均已通过上述特例。

该流程已通过 synthetic apply/stale/rollback/tamper 测试和真实 Safari schema 的自动删除
副本审计。私有副本中只向唯一内建 `BookmarksBar` 新增一个 bookmark，206 个未触碰 subtree
的 canonical hash 不变，真实 plist 未变化。Safari UI 是否接受、iCloud 是否同步仍未证明，
必须通过另行授权的一次性 live fixture 验证。

live 入口默认禁用，只有提供准确确认短语 `CREATE SAFARI 0.8.1 FIXTURE` 才会执行。它会在
唯一内建 `BookmarksBar` 下创建一个名为 `macos-data 0.8.1 plist feasibility fixture` 的
bookmark。原始 fixture UUID 和 URL 只保存于 recovery 同目录的 mode 0600 receipt，供之后
精确清理。成功后必须通过 Safari UI 和 parser 回读验证，禁止自动重试。

### 第四阶段结果：本机 local-only 成功，iCloud sync 失败

准确确认短语仅执行了一次，对应 session
`3f6c5b6f-aa0c-4a21-98e8-fe66c578a781`。原子替换只新增一个 fixture，并把写入前
plist、manifest 和 receipt 作为 mode 0600 私有 recovery 完整保留。Safari UI 能显示
fixture，公开 CLI 也只返回一个匹配。

Reading List 从 89 条变为 0 是用户另行手动删除，不是 fixture mutation 造成，因此不计入
本 gate 的安全结论。普通 bookmark/folder payload 从 116 变为 117，准确对应新增 fixture，
没有普通旧书签丢失。

但同一 iCloud Safari 账户的另一台设备没有出现 fixture。因此结论需要拆分：受保护的直接
`Bookmarks.plist` 替换已证明本机 local-only 可行，但它不会生成 Safari 私有 sync transaction，
不得宣称支持 iCloud。

Apache-2.0 许可的
[`chikingsley/safari-bookmarks-mcp`](https://github.com/chikingsley/safari-bookmarks-mcp)
也证明了本机 add/edit/move/remove/folder 操作可以通过 typed tree 解码 plist 后回写完成。值得借鉴的是：
UUID 或 path 定位、保留未知字段、拒绝 move cycle、MCP 默认 dry-run、带时间戳 backup、同目录 temporary
file、atomic replacement 与 mode 保留。这些能补强 local CRUD contract 和测试矩阵，但不改变同步结论。

其当前实现不要求 Safari 退出，不检测 open handle、稳定 pre-write hash 或 Safari file lock，也不完整保留
owner/group/ACL/xattr，不执行 file/directory fsync、写后 read-back rollback，更不会生成 `Sync.Changes`。
长驻 MCP service 只在启动时加载一次 plist，后续 apply 可能覆盖 Safari 并发修改。测试全部基于 fixture，
没有真实 Safari 或第二设备 iCloud gate，仓库 Issues 也被禁用。macos-data 对这些本机文件风险已有更严格
gate，因此没有复制其代码；只把 operation vocabulary 与负向测试案例作为候选参考。

本机存在私有 `SafariBookmarksSyncAgent`，但 Apple 没有发布让外部 plist 编辑提交给该 agent
的受支持 CLI 或公开 Framework API。restart/kickstart 最多重启 process，不能可靠补造缺失的
change transaction，因此 CLI 不得把它当作同步按钮。

公开源码调查发现了一条本质不同、但仍不受支持的路线：仍在维护的
[`jerrykrinock/BkmkMgrs`](https://github.com/jerrykrinock/BkmkMgrs) 会加载 Safari 私有
Framework，通过 `WebBookmarkGroup` 保存，再调用
`BookmarksController.requestSyncClientTriggerSyncForBookmarkGroup`。当前 SafariCore 私有
header dump 还包含 `forceBookmarkSync` 和 `userDidUpdateBookmarkDatabase`，但 GitHub 精确
代码搜索没有找到可运行的独立 `forceBookmarkSync` CLI；本机 XPC probe 也因缺少 Apple 私有
entitlement 被拒绝。BkmkMgrs 自己记录的替换同步 agent 诊断实验同样失败。因此这些证据只支持
建立独立 private-framework feasibility gate，不代表公开稳定 contract；在没有明确兼容许可证时
也不得直接复制该仓库代码。

Apple 公开的是 Safari-owned bookmark import/export；同步故障排查则包括切换 iCloud 中的
Safari 开关和重启 browser/device，后者是用户恢复动作，不是每次写入后可调用的 API。
参考 Apple 的 [Safari 同步故障排查](https://support.apple.com/en-euro/111761) 与
[Safari 数据传输格式](https://developer.apple.com/documentation/safariservices/importing-data-exported-from-safari)。

跨设备 fallback 应生成只包含目标项的最小 Netscape Bookmark HTML，让 Safari 通过自己的 UI
import，再做 duplicate 检查和第二设备回读。import 是独立操作，不能证明此前直接写入节点会被
自动接管。在该 gate 通过前，direct write 必须返回 `syncStatus=local_only` 和明确 `nextAction`。
Apple 的 [Safari import 指南](https://support.apple.com/en-gb/guide/safari/ibrw1015/mac)
明确说明导入书签会追加在现有书签之后，因此 duplicate prevention 是强制条件。

## 跨设备写入的备选路线

Safari AppleScript 只公开 Reading List 新增，没有 bookmark 的 list/create/update/delete。
Shortcuts 可以继续调查已有 Safari action，但它增加一个用户管理层，目前不能证明通用
bookmark CRUD。Safari WebExtension 必须在实际 Safari host 中 feature-detect；仅看到
WebKit 源码不算 Safari 已支持。最后才考虑不使用坐标的语义化 Accessibility。

在进入这些 fallback 前，可以先做 research-only private-framework probe：动态检查
`BookmarksController` 和同步 selector 是否存在，能力探测阶段不得修改数据。
macOS 27 Beta 5 临时只读 runtime probe 已成功加载 Safari 与 SafariCore，并确认
`BookmarksController`、`WebBookmarkGroup`、`BookmarksUndoController`、
`defaultBookmarksFileURL`、`requestSyncClientTriggerSyncForBookmarkGroup:` 及其
`skipRequestIfNoChanges:` 变体真实存在。该 probe 没有实例化 bookmark store、调用同步 selector
或读写任何 bookmark 数据。

在收到准确授权短语 `TRIGGER SAFARI PRIVATE SYNC PROBE` 后，一次有人值守实验使用已验证默认
bookmark path 的 scoped initializer 构造 controller、加载 group，并且只调用一次
`skipRequestIfNoChanges:NO` 变体。第一次普通 `init` 构造在 selector 之前因没有 loadable group
而停止，因此同步尝试计数为 0；修正后的 scoped initializer 先通过独立 preflight，之后才执行唯一
一次真实调用。launchd agent 保持健康并由 IPC 激活，没有观察到 entitlement rejection，但有界
unified-log 时间窗也没有 forced-sync 完成证据。调用前后 plist 的 device、inode、size、mtime、
mode 与 SHA-256 完全不变。因此最初只能标记为 `request_invoked_remote_pending`，不能称为同步确认，
并且没有重试。随后第二设备回读确认 fixture 仍未同步。隐私受限的只读审计又确认：fixture 在 bookmark
tree 中存在一次，但整个 `Sync.Changes` 队列为 0。该 probe 的最终结果是
`request_invoked_no_queued_change`：单独调用 selector 不会把 direct-plist mutation 接管进 Safari 的
同步 journal。

BkmkMgrs 的实现有实质差异：先修改 `WebBookmarkGroup`，调用私有 `save`，持有 Safari file lock 时
修复 orphan change record，释放 lock，最后才调用单参数 sync-request selector。代码中所谓更激进的
双参数变体实际上被编译禁用。历史注释记录过 Mac 到 iPad 最终传播成功，也记录过长时间延迟和 iCloud
冲突；这只能证明旧版完整 pipeline 曾经能够同步，不能证明 selector 单独调用就足够。仓库 2026 年
2 月的 Safari test 只验证本机 export/import round trip。macOS 27 Beta 的提交仅为 Xcode build bug
提高 deployment target，没有提供 macOS 27 跨设备同步 gate；仓库目前也没有相关 Issue。

只有另行明确授权的一次性 fixture 才能进入 framework-owned create/save/request-sync 与第二设备验证。selector
缺失、Framework 漂移、签名/加载失败、结果未知或第二设备无回读都必须 fail closed；禁止重启或
修改同步 daemon。

这次另行授权的 macOS 27 Beta 5 fixture 已完成完整有人值守 gate。触碰真实文件前，隔离副本已证明
create/save/唯一 matching `Add`/remove/save 可实现零残留、零同步请求，同时真实 plist hash 不变。
随后在 `0700` 私有 session 目录中保留 `0600` plist、manifest 和 receipt。真实私有 Framework
操作创建了恰好一条 bookmark，`WebBookmarkGroup.save()` 返回 `2`，磁盘回读确认恰好一条 matching
`Sync.Changes` `Add`，最后只调用一次单参数 sync selector，但第二设备仍未出现 fixture。因此最终同步
结论为 `framework_add_queued_remote_not_observed`：本机存在 `Sync.Changes` `Add` 也不能证明跨设备同步。
随后已按持久化 UUID 重新解析并删除 fixture、save，并在本机验证零匹配；cleanup sync 只请求一次，
没有重试或重启 daemon。后续同步研究移到 0.8.8；原 0.8.2 安全引擎与 0.8.3 CRUD 里程碑
合并进入 0.8.1。

后续 probe 还必须遵循一个 ABI know-how：`save()` 之后原始 `WebBookmarkLeaf` 对象可能已经 stale。
cleanup 必须从持久化结果取得 opaque UUID，用 `bookmarkForUUID:` 重新解析当前对象，再 remove、save
并从磁盘证明零残留。私有 `removeBookmarks:` 的返回 ABI 本身不能作为成功依据。
