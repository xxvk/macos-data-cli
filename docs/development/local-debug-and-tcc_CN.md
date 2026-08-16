# 本机 Debug 与 Contacts / Mail / Calendar 授权

## 工具链

macOS 26 项目应使用完整 Xcode，而不是可能版本不匹配的
`/Library/Developer/CommandLineTools`：

```bash
export DEVELOPER_DIR="$(xcode-select -p)"
```

如果 SwiftPM 因用户目录权限无法写入缓存，使用项目内缓存。仓库脚本
`scripts/build_debug_app.sh` 已自动配置这些变量。

## 构建 Debug app

Contacts 的 TCC 授权不能可靠地授予裸 `.build/debug/mpia`。本机开发时
应构建带 bundle identifier 和 `NSContactsUsageDescription` 的 app：

```bash
bash scripts/build_debug_app.sh
```

脚本生成：

```text
.build/debug/mpia.app
```

脚本会在 ad-hoc 签名之前清理 app bundle 的 extended attributes；项目位于
iCloud/同步目录时，否则 `codesign` 可能报
`resource fork, Finder information, or similar detritus not allowed`。
签名使用仓库中的 `scripts/mpia.entitlements`，并显式保留 Mail Automation
所需的 `com.apple.security.automation.apple-events=true`。可用下列命令验证最终 app，
不要只检查 entitlement 源文件：

```bash
codesign --verify --deep --strict .build/debug/mpia.app
codesign -d --entitlements - .build/debug/mpia.app
```

Photos 还必须保留
`com.apple.security.personal-information.photos-library`。不要在 agent sandbox 中直接运行
PhotoKit 命令后据此判断 app 权限：TCC 可能将 Codex/ChatGPT 识别为 responsible process。
真实 gate 使用稳定路径 app 和 LaunchServices：

```bash
MPIA_APP="$HOME/Applications/mpia-debug.app" \
  bash scripts/run_photos_read_smoke.sh
```

`open -n -W -o <temporary-file> --stderr <temporary-file> <app> --args ...`
可以保持 app 的独立 TCC 身份并捕获 JSON；smoke 只打印聚合数量。ad-hoc 重建改变 code hash，
因此替换 app 后需要重签名，必要时只重置 `com.xvk.mpia.cli` 的 Photos 条目。

第一次使用时启动权限请求：

```bash
open -W .build/debug/mpia.app --args OPTIONS /contacts/permission
```

然后在“系统设置 → 隐私与安全性 → 通讯录”中确认
`mpia.app` 已打开。若系统没有显示该 app，重新运行构建脚本后再启动。

## 读取验证

`open` 不会把 app 的 stdout 转发回当前 Terminal。需要读取 JSON 时，使用
支持 `output` 参数的 export route：

```bash
open -W .build/debug/mpia.app --args \
  POST /contacts/export --params '{"output":"/tmp/mpia-contacts.json"}'
```

确认读取成功后应删除临时快照；联系人 JSON 可能包含个人敏感信息。

不要用裸 Debug 二进制验证授权：

```bash
mpia GET "/agent/manifest"
```

0.9.3 可执行 route 请从 manifest 获取；完整示例见 `docs/usage_CN.md`。

它可能与已授权的 `mpia.app` 被 macOS TCC 视为不同身份，并返回
`Access Denied` 或 permission-not-granted。真实 Contacts 写入仍须遵循
`rules_CN.md` 的 dry-run、显式 apply 和确认短语要求。

## 回归测试

```bash
bash scripts/build_debug_app.sh
bash scripts/run_swift_tests.sh
```

`scripts/run_swift_tests.sh` 只验证纯逻辑和 adapter 单元测试，不代替真实 TCC
授权或真实 Contacts CRUD 验证。

Xcode 27 在 iCloud/File Provider 工作区中可能给新生成的 `.xctest` bundle 附加
`com.apple.FinderInfo`，随后被 codesign 以 `resource fork, Finder information, or similar
detritus not allowed` 拒绝。标准脚本把 SwiftPM test scratch 放到本机临时目录，从流程上避免该问题；
不修改源码，也不要求清空整个 `.build`。

2026-08-14 已验证：active developer directory 为
`/Applications/Xcode-27.0.0-Beta.5.app/Contents/Developer`，Xcode build
`27A5237l`、Swift 6.4、macOS SDK 27.0；222 个 tests、Release build 与签名 debug app
均通过。构建脚本默认跟随 `xcode-select -p`，仍可通过显式 `DEVELOPER_DIR` 覆盖。

Mail release gate 还会检查 Info.plist、entitlement plist、签名完整性，以及签名后
Automation entitlement 的实际值；任一项漂移都会立即失败。

Mail 0.2 的非 UI 本机 release gate：

```bash
bash scripts/run_mail_release_gate.sh
```

需要人工在场、允许一次可见 reveal 时才增加 `--with-automation`。Mail.app 忙于同步时
3 秒 Apple Event budget 可能返回 `MAIL_APP_TIMEOUT`；这是 fail-closed 结果，脚本不会
自动重试。

只验证未知 schema/FDA 路径的有限 Mail.app metadata backend 时，运行：

```bash
bash scripts/run_mail_app_metadata_smoke.sh
```

脚本在登录用户 GUI session 中强制选择 fallback，仅打印账号、顶层 mailbox 和 message
聚合数量；完整 JSON 只写入自动删除的私有临时目录。它不会读取正文或执行 reveal。

## Mail Automation

Debug app 已包含 `NSAppleEventsUsageDescription`。先通过 UI 启动 Mail.app，再用同一个
已签名 bundle 发起一次显式 reveal，以触发 Automation 授权：

```bash
bash scripts/build_debug_app.sh
open -W .build/debug/mpia.app --args POST /mail/reveal \
  --params '{"id":"<opaque-id>"}'
```

`reveal` 会在 Mail.app 中可见地定位消息；确认该行为可接受后再授权。普通
`GET /mail/get` 使用 `"content":"text"` 参数时，fallback 不会为了读取而自动启动 Mail.app。

Codex 或其他 agent host 的 shell 可能不在当前 loginwindow GUI bootstrap namespace：
这时直接运行 doctor 会把已打开的 Mail 误报为 `target_not_running`。使用登录用户会话
执行 smoke，而不是降低运行态检查：

```bash
bash scripts/run_mail_automation_smoke.sh --gui-session
```

脚本只输出 capability/backend 状态，不输出主题、地址或正文。可选的
`--with-text-fallback` 会在最多 200 条 metadata 中寻找一条 `metadata_only` 消息并
显式读取一次正文；只有确认可以读取一封真实邮件时才使用。

## Calendar full access

Debug app 的两个 Info.plist 都必须包含 `NSCalendarsFullAccessUsageDescription`。重新签名
后，用 app bundle 内的 executable 请求 full access：

```bash
mpia GET "/agent/manifest"
```

0.9.3 可执行 route 请从 manifest 获取；完整示例见 `docs/usage_CN.md`。

返回 `fullAccess` 后，使用隐私安全 smoke；不要直接打印真实事件 JSON：

```bash
bash scripts/run_calendar_read_smoke.sh
bash scripts/run_calendar_dry_run_smoke.sh
```

第一个脚本只输出 source、calendar 和分页事件数量；第二个脚本验证 create/edit/delete
preview，不调用 EventKit save/remove。重新替换 ad-hoc 签名 app 后，macOS 可能重新评估
TCC 身份；应再次检查 permission，不要通过复制数据库或绕过 TCC 解决。
