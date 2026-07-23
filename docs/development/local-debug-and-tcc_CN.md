# 本机 Debug 与 Contacts / Mail 授权

## 工具链

macOS 26 项目应使用完整 Xcode，而不是可能版本不匹配的
`/Library/Developer/CommandLineTools`：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

如果 SwiftPM 因用户目录权限无法写入缓存，使用项目内缓存。仓库脚本
`scripts/build_debug_app.sh` 已自动配置这些变量。

## 构建 Debug app

Contacts 的 TCC 授权不能可靠地授予裸 `.build/debug/macos-data`。本机开发时
应构建带 bundle identifier 和 `NSContactsUsageDescription` 的 app：

```bash
bash scripts/build_debug_app.sh
```

脚本生成：

```text
.build/debug/macos-data.app
```

脚本会在 ad-hoc 签名之前清理 app bundle 的 extended attributes；项目位于
iCloud/同步目录时，否则 `codesign` 可能报
`resource fork, Finder information, or similar detritus not allowed`。
签名使用仓库中的 `scripts/macos-data.entitlements`，并显式保留 Mail Automation
所需的 `com.apple.security.automation.apple-events=true`。可用下列命令验证最终 app，
不要只检查 entitlement 源文件：

```bash
codesign --verify --deep --strict .build/debug/macos-data.app
codesign -d --entitlements - .build/debug/macos-data.app
```

第一次使用时启动权限请求：

```bash
open -W .build/debug/macos-data.app --args contacts permission
```

然后在“系统设置 → 隐私与安全性 → 通讯录”中确认
`macos-data.app` 已打开。若系统没有显示该 app，重新运行构建脚本后再启动。

## 读取验证

`open` 不会把 app 的 stdout 转发回当前 Terminal。需要读取 JSON 时，使用
支持 `--output` 的 export 命令：

```bash
open -W .build/debug/macos-data.app --args \
  contacts export --format json --output /tmp/macos-data-contacts.json
```

确认读取成功后应删除临时快照；联系人 JSON 可能包含个人敏感信息。

不要用裸 Debug 二进制验证授权：

```text
.build/debug/macos-data contacts count --format json
```

它可能与已授权的 `macos-data.app` 被 macOS TCC 视为不同身份，并返回
`Access Denied` 或 permission-not-granted。真实 Contacts 写入仍须遵循
`rules_CN.md` 的 dry-run、显式 apply 和确认短语要求。

## 回归测试

```bash
bash scripts/build_debug_app.sh
swift test
```

`swift test` 只验证纯逻辑和 Contacts adapter 单元测试，不代替真实 TCC
授权或真实 Contacts CRUD 验证。

Mail release gate 还会检查 Info.plist、entitlement plist、签名完整性，以及签名后
Automation entitlement 的实际值；任一项漂移都会立即失败。

Mail 0.2 的非 UI 本机 release gate：

```bash
bash scripts/run_mail_release_gate.sh
```

需要人工在场、允许一次可见 reveal 时才增加 `--with-automation`。Mail.app 忙于同步时
3 秒 Apple Event budget 可能返回 `MAIL_APP_TIMEOUT`；这是 fail-closed 结果，脚本不会
自动重试。

## Mail Automation

Debug app 已包含 `NSAppleEventsUsageDescription`。先通过 UI 启动 Mail.app，再用同一个
已签名 bundle 发起一次显式 reveal，以触发 Automation 授权：

```bash
bash scripts/build_debug_app.sh
open -W .build/debug/macos-data.app --args mail reveal --id <opaque-id> --format json
```

`reveal` 会在 Mail.app 中可见地定位消息；确认该行为可接受后再授权。普通
`mail get --content text` fallback 不会为了读取而自动启动 Mail.app。

Codex 或其他 agent host 的 shell 可能不在当前 loginwindow GUI bootstrap namespace：
这时直接运行 doctor 会把已打开的 Mail 误报为 `target_not_running`。使用登录用户会话
执行 smoke，而不是降低运行态检查：

```bash
bash scripts/run_mail_automation_smoke.sh --gui-session
```

脚本只输出 capability/backend 状态，不输出主题、地址或正文。可选的
`--with-text-fallback` 会在最多 200 条 metadata 中寻找一条 `metadata_only` 消息并
显式读取一次正文；只有确认可以读取一封真实邮件时才使用。
