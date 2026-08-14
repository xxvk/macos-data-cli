# Shortcuts 0.7.1 受管理源码 authoring

## 边界

0.7.1 只管理以 `.cherri` 源码作为 SSOT 的 Shortcut，不接管或修改任意已有
Shortcut，不读取 Shortcuts 私有数据库，也不把 GPL-2.0 的 Cherri 源码复制进
本 MIT 仓库。Cherri 2.3.x 是可选外部 CLI；macos-data 固定使用
`--skip-sign --derive-uuids --no-ansi`，禁止 HubSign 和自定义远程签名服务，最终
只调用系统 `/usr/bin/shortcuts sign`。

## 0.7.1 命令

```text
macos-data shortcuts author validate --source <file.cherri> --format json

macos-data shortcuts author build --source <file.cherri> \
  --output <file.shortcut> \
  [--signing-mode people-who-know-me|anyone] --format json

macos-data shortcuts create --source <file.cherri> [--idempotent] \
  [--dry-run] --format json
macos-data shortcuts create --source <file.cherri> [--idempotent] \
  --apply --confirm "CREATE MANAGED SHORTCUT" --format json

macos-data shortcuts update --id <managed-opaque-id> --source <file.cherri> \
  --expected-source-sha256 <sha256> --strategy replace|retain-old \
  [--dry-run] --format json
macos-data shortcuts update --id <managed-opaque-id> --source <file.cherri> \
  --expected-source-sha256 <sha256> --strategy replace|retain-old \
  --apply --confirm "UPDATE MANAGED SHORTCUT" --format json

macos-data shortcuts managed list --format json
macos-data shortcuts managed forget --id <managed-opaque-id> [--dry-run] --format json
macos-data shortcuts managed forget --id <managed-opaque-id> --apply \
  --confirm "FORGET MANAGED SHORTCUT" --format json
```

源码必须是 UTF-8、最大 256 KiB、只有一个不超过 200 字符的 `#define name`。
仅允许内置 `stdlib` 和 `actions/<category>`；package、相对/绝对 include、`#ref`、
文件嵌入、raw/custom action 和疑似内联 secret 全部 fail closed。生成物最多
10 MiB、2,000 个 action。JSON 只返回 SHA-256、字节数、action count、编译器/
client 版本与签名模式，不返回源码、名称、参数、stderr 或 secret。
编译侧 `actionCount` 不计算终止 `is.workflow.actions.output` 节点；apply 结果另行返回
`observedActionCount`。macOS 27 Beta 5 对可正常运行的 Cherri 导入对象仍报告 `0`，因此公开 count
不能证明动作图。只有 output 的 artifact 因没有可独立观察的动作而被拒绝。

`validate` 只在权限为 `0700` 的临时目录编译并清理；`build` 再调用系统签名器，
输出权限为 `0600` 且拒绝覆盖。两者都不会导入或运行 Shortcut。create/update 同样
默认 preview；只有准确 apply 确认短语才会打开 Shortcuts.app 的可见导入。

私有 registry 已实现并通过权限/脱敏单元测试，只保存 opaque shortcut ID、源码/
编译结果哈希、action count、编译器版本和时间；目录 `0700`、文件 `0600`、原子写入。
create/update 只有在可见导入与 metadata 回读成功后才写 registry；in-flight 或 pending
receipt 都不是自动重试信号。

update 只接受 registry 中的 managed opaque ID，并用当前 source SHA-256 做乐观并发 token。
`replace` 保持可见名称不变，但只有旧公开 count 与 registry 编译 count 一致且新 count 发生变化时
才允许；count 不一致时无法安全证明替换结果，必须 fail closed。
`retain-old` 会将候选包内部名称改为 ` (macos-data <source-hash-prefix>)` 后缀，但 registry
仍记录原始 `.cherri` 的 source hash，而不是临时改名后的编译输入。旧 Shortcut 永远不会先删。
`managed forget` 只清除私有 registry/receipt，不删除 Shortcuts.app 中的对象。

## macOS 27 签名 know-how

手工探针曾用 `cp` 复制 iCloud 工作区源码，连 `com.apple.provenance` 一起复制，
Cherri 生成物继承 xattr 后被 `shortcuts sign` 以格式错误拒绝。adapter 现在只复制
源码字节、不复制文件 metadata；同一 Cherri 2.3.0 生成物已在 macOS 27 Beta 5
签名成功。不要在此路径重新引入保留 xattr 的复制方式。

非导入 gate：

```text
bash scripts/run_shortcuts_authoring_smoke.sh
```

一次性可见生命周期 gate 必须获得当前任务明确授权，并使用准确的外层确认短语：

```text
MACOS_DATA_CLI=.build/debug/macos-data.app/Contents/MacOS/macos-data \
  bash scripts/run_shortcuts_authoring_integration.sh \
  --apply --confirm "SHORTCUTS AUTHORING CRUD TEST"
```

它覆盖 validate、create preview/apply、黑盒运行、`retain-old` 候选 update preview/apply、再次运行、
UI 删除、registry forget 与零残留。脚本等待两次可见 Add 确认和语义化 UI 删除，不使用屏幕坐标。
该 gate 已在 macOS 27 Beta 5 + Cherri 2.3.0 通过：新旧版本均准确返回 sentinel；公开 count 均为
`0`，但黑盒运行证明动作图有效。清理后恢复原有 2 个 Shortcut，fixture 和 registry 均零残留。
本机同名 `replace` 继续 fail closed。真实 gate 后的全量 Swift suite、Release build、CLI contracts、
非导入 authoring smoke 和版本审计均通过后，源码才提升为 `0.7.1`。
