# 本机 Debug 与 Contacts 授权

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
