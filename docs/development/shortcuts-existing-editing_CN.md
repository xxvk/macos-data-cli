# Shortcuts 0.7.2 现有对象编辑边界

## 当前已实现切片

0.7.2 当前公开能力包含只读采集/能力分类、语义编辑计划、Accessibility discovery，以及一个受保护的
copy-first mutation：

```text
mpia shortcuts edit inspect --input <local.cherri|local.shortcut> --format json
mpia shortcuts edit plan --input <local.shortcut> --patch <plan.json>|--stdin --format json
mpia shortcuts edit copy --input <local.shortcut> --patch <plan.json>|--stdin \
  --expected-editor-name-sha256 <sha256> --dry-run|--apply \
  [--confirm "EDIT SHORTCUT COPY"] --format json
mpia shortcuts edit ui-inspect --format json
```

inspect、plan、UI inspection 和 edit-copy dry-run 都不会修改对象。plan 只读取 artifact 一次，核对
准确 input hash，并在内存 shadow graph 上执行操作。edit-copy apply 仅允许已证明的 replace-text、末尾
insert-text、有界全 delete 与有界全 move family，且必须先通过准确确认。完整 0.7.2 gate 通过后才提升源码版本。

## 本地采集规则

- 只接受一个本地 `.cherri` 或 `.shortcut` regular file，底层 reader 强制 `isFileURL`。
- 使用 `O_NOFOLLOW` 打开，并通过 `fstat` 再次验证 regular file。
- 拒绝 symlink、目录、空文件、未知扩展名和超过 10 MiB 的输入。
- 不读取 Shortcuts SQLite、CloudKit 或 private framework。
- 本切片不接受 iCloud share link 或任何 URI syntax。Apple 文档说明创建 link 会把副本交给 Apple 验证并
  通过 iCloud 提供链接，接收仍是可见 Get Shortcut 流程。
- 不请求网络、不跟随 redirect、不下载、不读取 clipboard，也不触发 import。红绿测试证明即使远程 URL 的
  path 恰好映射真实本地 fixture，也会在读取前拒绝。未来网络采集必须另设 opt-in command 与 action-time
  隐私确认。

## 脱敏结果

JSON 只允许包含：输入 SHA-256/字节数、artifact/parse 分类、有限 visible/unsupported action count、
boolean 风险与能力 flag、稳定 reason enum。不得包含输入路径、文件名、Shortcut 名称、Cherri 源码、
action identifier、参数、compiler output 或嵌入值。

## 能力状态

- `managed_source_route`：有效且有限的 Cherri 应继续走 0.7.1 managed-source 流程，不把它静默接管为
  任意已有对象。
- `semantic_edit_candidate`：可解析的 unsigned artifact，其 visible action 只使用首批
  text/comment/nothing/output allowlist，且参数均为非敏感 scalar。它只表示未来可以生成 edit plan。
- `manual_migration_required`：opaque/signed 数据、未知 action、异常/无界 graph、magic variable/附件等
  嵌套结构、疑似凭据或 device-bound reference。

只有经过验证且全为 replace-text、graph 已有 Text 的末尾 insert-text，或删除后至少保留一个 action 的
有界全 delete plan，或有界全 move plan，`canApplySemanticEdit` 才为 true。candidate 本身不是 graph proof、
apply 授权或兼容性承诺。

## 只读 edit-plan contract

- 顶层只允许 `expectedInputSHA256` 和 `operations`。
- 支持 1...64 个顺序执行的 `insert_text`、`replace_text`、`delete_action`、`move_action`。
- visible-action index 排除 terminal output，并基于前面操作产生的 shadow graph 计算。
- 每个文本最多 64 KiB；整个 patch 最多 256 KiB。
- `replace_text` 只接受 text action；delete 不得清空 graph；move 必须改变 index，且不能跨越语义状态
  完全相同、因此无法证明排序变化的相邻 action。
- 输出仅含 index、count、input/plan hash 和文本 byte count/SHA-256，不返回文本或 action identifier。
- hash 不一致返回稳定并发冲突；不支持的 artifact 继续要求人工迁移。
- plan 命令自身没有 apply flag、Apple Event、Accessibility event、registry 写入或 artifact 输出。

## 只读 Accessibility discovery

- `ui-inspect` 只检查 trust，不弹授权，也不启动或激活 Shortcuts.app。
- bridge 只有 attribute read；没有 AX action、set-value、点击、输入、坐标、截图或图像匹配接口。
- 超过 2,000 节点或深度 32 立即停止并返回 `unbounded`。
- 候选必须同时具备 semantic editor marker 和 toolbar/group/scroll-area hierarchy；generic role 不足以
  判定，多个候选返回 `ambiguous`。
- 输出只有 status/count。AX label、title、identifier 和 value 只能作为内存中的匹配输入，禁止进入
  JSON 或日志。
- discovery 只是兼容性证据；独立 mutation/recovery fixture 通过前，`canApplySemanticEdit` 始终为 false。

### macOS 27 Beta 5 真实 discovery gate

- disposable Shortcut 只有一个本地 Text action，没有外部副作用。
- 首次运行安全 fail closed，并发现稳定 editor identifier 为 `editor.shortcutname`；先增加红灯兼容性测试，
  才把准确 normalized marker 加入 allowlist。
- 校准后在 2 个窗口、373 个节点中发现唯一有界 candidate；fixture 名、action text、label、title、
  identifier 均未进入 JSON。
- cleanup 选择 library row，并使用语义 Edit > Delete；唯一名称搜索返回 No Results，最终 CLI discovery
  在 1 个窗口、139 个节点中返回 0 editor candidate。

### macOS 27 Beta 5 语义元素校准

- 第二个仅限本地的一次性 fixture 含一个 Text action 和一个 Comment action；只用于只读 element/menu
  检查，没有调用任何编辑操作。
- editor name 是 identifier 准确为 `editor.shortcutname` 的唯一可写 `AXTextField`。action canvas 是外层
  `AXScrollArea`；已校准的 Text/Comment action 都包含直接 title、一个 `Close` 按钮，以及一个内含唯一
  可写 `AXTextArea` 的嵌套 scroll area。
- action library 的搜索结果属于另一个 scroll area，绝不能误判为 action canvas。未知直接 action title、
  value field 缺失或重复、多个 editor candidate、深度或节点上限溢出全部 fail closed。
- 只读 menu 检查得到 File > Duplicate 的 `duplicateShortcut:`、action duplicate 的
  `duplicateAction:`、移动的 `rearrangeItemUp:` / `rearrangeItemDown:`，以及插入 Comment 的
  `insertCommentAction:`。这些 identifier 只是兼容性证据，不构成 mutation 授权。文本框获得焦点时，
  所选 action 的菜单删除项为 disabled，因此它不是已批准的 delete 机制。
- 纯 semantic resolver 只对私有 Shortcut name/action value 取 hash，对外返回 semantic kind 与 element
  path，忽略 action-library decoy，并由 4 个 fail-closed/脱敏测试覆盖。
- cleanup 使用可恢复的 library delete；准确名称搜索为零结果，library 数量恢复到 gate 前，证明 fixture
  零残留。

## 受保护 mutation coordinator 与公开 replace-text 边界

- 准确确认短语是 `EDIT SHORTCUT COPY`，且必须在读取 editor 前校验。
- coordinator 先验证 hash 与 operation 字段，再基于当前 semantic action state 预演完整 plan；预演通过前
  不创建恢复对象，也不修改任何内容。
- 禁止直接修改原对象。recovery candidate 必须具有不同的 hashed identity、完整保留原 semantic graph，
  并继续是唯一有界 editor candidate。
- insert-text、replace-text、delete-action、move-action 按顺序作用于副本模型；每次 bridge operation 后
  都必须精确回读 semantic state。
- bridge error 或 read-back 不一致返回 `outcome_unknown` 和固定 `nextAction`；自动重试恒为 false，原对象保留。
- 结果只含 hash、count、status 与固定指引，不包含 Shortcut 名称、action text、UI label/identifier 或参数值。
- 11 个 synthetic test 已证明 coordinator 规则；另由 disposable macOS 27 Beta 5 gate 提供兼容性证据。

### 公开 `edit copy` contract

- `--patch`/`--stdin` 必须二选一，`--dry-run`/`--apply` 也必须二选一。
- 必须提供准确可见 editor 名称的 SHA-256。hash 输入为无换行 UTF-8 bytes；名称不得进入 JSON 或日志。
- dry-run 验证 private execution plan 后返回脱敏 preview，不构造具体 system AX bridge。
- apply 必须先匹配 `--confirm "EDIT SHORTCUT COPY"`，然后才能构造 bridge。
- 对 apply 而言，每个 operation 都必须是 `replace_text`；或者全部是末尾 `insert_text`，其 index 必须等于当前 action count，
  且 graph 已存在可复制的 Text action；或者全部是删除后至少保留一个 action 的有界 `delete_action`。
  全 move plan 也可 apply。其他 insert 与混合 operation apply 在 mutation 前返回
  `SHORTCUTS_EDIT_CAPABILITY_UNSUPPORTED`。
- 结果状态仅为 `preview`、`readback_confirmed` 或 `outcome_unknown`，且永远禁止自动重试。

### 私有 execution 绑定与 guarded bridge

- strict patch parse 同时产生公开脱敏 plan 和不可 Codable 的内存 execution plan；其 description/debugDescription
  固定脱敏所有 private value。
- 读取 editor 前，coordinator 证明每个 private text 与公开 byte count、SHA-256 完全一致；复制或篡改的
  summary 不能执行。
- plan-bound guarded bridge 不提供通用 click、typing、coordinate、menu 或 AX element 逃生口；session surface
  仅限 inspect、duplicate、insert/replace text、delete、move。
- recovery 必须先执行且只能一次；operation 必须与绑定计划准确同序，altered、out-of-order、extra operation
  均在 session call 前拒绝。
- 任意 session mutation error 会永久 poison bridge；即使调用方忽略 coordinator 的 `outcome_unknown` 指引，
  也不能通过该 bridge 重试同一步。
- 当前由 15 个 edit-plan、11 个 coordinator、8 个 semantic-edit service、5 个 guarded-bridge 测试覆盖；
  semantic resolver 已增至 6 个测试，覆盖视觉顺序与 position fail-closed。

### 具体 copy-first Text mutation gate

- 具体 system AX session 实现通过 `duplicateShortcut:` 执行 File > Duplicate、对 resolver 批准的 Text
  `AXTextArea` 设置 `AXValue`、末尾追加 Text，以及已有 synthetic 覆盖的 resolver-bound Close-button delete。
  追加时只聚焦 resolver 批准的 Text area，调用准确
  `duplicateAction:`，证明 duplicate 出现在 graph 末尾后，只修改该新增 value。中间/无来源 insert、
  delete 只按 resolver 绑定的 Close button，并等待准确缩小后的 graph。move 限定为 resolver 批准的 action 与
  准确 `rearrangeItemUp:`/`rearrangeItemDown:`，且每个相邻步骤后回读完整
  graph。中间/无来源 insert、同索引/相同相邻 action move、混合 operation、通用
  press/set-value、坐标和图像匹配继续不可用。
- driver 只读取准确 toolbar name field，以及 split group 中具有直接 Text/Comment title 的唯一 scroll area，
  不遍历 action library。唯一 main/focused editor 才是当前目标；Duplicate 后原件 editor 会留在后台，不能
  因此误判为歧义。
- AX messaging deadline 为 5 秒。12 个定向 session test 覆盖 copy-first replacement、等待不同副本、
  shortcut 只 duplicate 一次、末尾 action duplicate、准确 resolved Close-button delete、unsupported operation
  existing-copy recovery，以及对已删除副本的不修改回读。
- macOS 27 Beta 5 disposable fixture 已证明：原件 hash 匹配；副本 identity 不同且 graph 相同；Text 新 hash
  精确回读；Comment 不变；返回原件 editor 后确认原件仍是旧 hash。
- 首次真实尝试因遍历完整 action library 而在 duplicate 前阻塞。改为有界 subtree 后，duplicate 成功，但
  原件和副本两个 editor 同时存在，read-back 因歧义正确 fail closed。准确 UI 检查证明 replace 尚未发生；
  专用 recovery 路径随后选择唯一 main/focused existing copy，只完成未发生的 replace，没有再次 duplicate。
- 两个 fixture 仅在再次取得永久删除确认后删除。library 数量从 4 恢复到 2，准确名称搜索为 No Results。
- 另一个经明确授权的 append fixture 已证明：副本从 Text + Comment 变为 Text + Comment + 末尾 Text，原件
  仍准确保持 Text + Comment；已有 value 未变，新增 value 的 SHA-256 准确匹配。
- 取得单独清理确认后，两个 append gate fixture 均通过 Shortcuts UI 删除；library 从 4 恢复为 2，两个
  准确名称搜索均返回 No Results。
- 后续经授权的 delete fixture 已证明：Text + Comment 只在副本中变为 Text，原件保持 hash 等价的
  Text + Comment。首次立即回读命中 Shortcuts 的短暂 stale graph 并 fail closed；只读 existing-copy recovery
  随后确认副本只有一个 Text，且没有再次 duplicate 或 delete。session 现会在按 resolver-bound Close 后等待
  准确缩小的 graph 稳定。
- 两个 delete gate fixture 已从 All Shortcuts 移除；数量从 4 恢复为 2，准确名称搜索为 No Results。
- 第二个 disposable fixture 在单次命令内通过修正后的不中断 gate：copy、按 resolver 绑定删除 Comment、稳定
  回读一个 Text，并验证原件不变。两个对象随后永久删除；library 从 4 恢复为 2，准确名称零残留。
- 经授权的 move fixture 从 Text + Comment 建立副本并准确调用一次 `rearrangeItemUp:`。Shortcuts 只把副本视觉
  顺序改为 Comment + Text，但普通 `AXChildren` 仍保留创建顺序，gate 因而 fail closed。只读 recovery 证明
  `AXChildrenInNavigationOrder` 才是真实视觉顺序；resolver 只在 count 与完整 allowlist action-title 多重集一致时
  采用它，并在 position 可用时按左上角 AX Y 顺序排序。最终 hash-bound 回读确认副本已移动、原件仍为
  Text + Comment，且没有执行第二次 move 或 duplicate。取得单独 action-time 确认后，两个 fixture 均已永久
  删除；All Shortcuts 从 4 恢复为 2，两个准确名称搜索均返回 No Results。
- fixture harness 仍只在 debug build 可达。公开 CLI 已开放经过证明的 copy-first replace-text、末尾 insert 与
  有界全 delete、全 move 路径；fixture recovery 控制和通用 AX operation 均不公开。

## 0.7.2 剩余工作

1. 任意位置 insert 继续禁用，仅开放已证明的末尾子集。
2. commit/tag 前必须通过完整 0.7.2 release gate 与版本一致性审计。
