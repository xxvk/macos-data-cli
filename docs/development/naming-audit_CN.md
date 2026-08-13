# CLI 命名与兼容性审计

状态：已于 2026-08-14 完成第二轮候选、近似名称和常见 package registry 审计。
项目所有者已明确否决 `xvk-data`，并决定整个 0.x 阶段继续以 `macos-data` 作为唯一
canonical command；命名复审延后为 1.0.0 release gate。决策见
[ADR 0001](adr/0001-cli-name-until-1.0_CN.md)。

## 已确定的过渡约束

- 整个 0.x 阶段继续使用 `macos-data` 作为唯一 canonical command。
- 0.x 不增加新命令别名，也不启动弃用流程。
- 正式发布 1.0.0 前重新审视命名；复审不等于预先决定改名。
- CLI 改名不得静默修改稳定的 `x-macos-data://external-id/` 数据 contract；identifier
  scheme 如需调整，必须另立设计、迁移命令和兼容期。
- 对平台的说明采用“a native data CLI for macOS”一类兼容性表达，不把 Apple 商标作为
  项目自身身份。

## Apple 命名边界

Apple 当前商标列表把 `Mac` 和 `macOS` 都列为 Apple 注册商标。Apple 第三方使用指引允许
在满足条件时以引用方式说明兼容性；对于产品名中的 `Mac`，指引只给出了有限例外，要求它与
非通用、非地理描述的词组合，并且不得暗示 Apple 背书。

对本项目的影响：

- 全小写并不会自动让 `macos-data` 变成商标中性名称。
- `mac-data` 不一定更安全；`data` 是通用描述词，未必满足上述有限例外。
- Homebrew 收录只能作为生态观察，不能证明获得商标许可。
- 最终公开名称最好同时避开 `Mac` 和 `macOS`，只在兼容性描述中使用这些词。

主要资料：

- [Apple Trademark List](https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html)
- [Guidelines for Using Apple Trademarks and Copyrights](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html)

本文是工程命名审计，不构成法律意见。

## Homebrew 命名空间快照

2026-07-23 更新后的 Homebrew 索引包含：

| 前缀 | Formula | Cask |
| --- | ---: | ---: |
| `mac*` | 15 | 59 |
| `macos*` | 3 | 0 |

三个 `macos*` Formula 是 `macos-term-size`、`macos-trash` 和 `macosvpn`。许多 `mac*`
结果实际指 MAC address、Monkey's Audio、`Mach` 或 `macro`，不能把原始前缀数量直接当作
Apple 品牌命名先例。

## 首轮候选清单

精确同名检查覆盖当前 Homebrew Formula/Cask 索引、公开 GitHub repository 名称以及本机
可执行命令空间；尚未覆盖注册商标、域名、所有 package registry 或近似混淆名称。

| 候选命令 | Homebrew 精确同名 | GitHub 精确同名仓库 | 本机命令 | 初步判断 |
| --- | --- | ---: | --- | --- |
| `xvk-data` | 可用 | 0 | 可用 | 精确同名可用性最好，但与维护者 namespace 绑定 |
| `native-data` | 可用 | 1 | 可用 | 含义清楚，但较通用且 GitHub 已有同名 |
| `system-data` | 可用 | 0 | 可用 | 当前可用，但范围宽泛、识别性较弱 |
| `agent-data` | 可用 | 0 | 可用 | 当前可用，但容易被理解为依赖某种 Agent 平台 |
| `data-bridge` | 可用 | 60 | 可用 | 淘汰：占用严重且缺乏识别性 |
| `os-data` | 可用 | 2 | 可用 | 简短但通用，GitHub 已有同名 |

首轮 shortlist 因此是 `xvk-data`、`system-data` 和 `agent-data`，但都尚未批准。最终选择前
还应生成更多不含 Apple 商标、识别性更强的候选；精确同名可用不等于名称适合采用。

## 第二轮 shortlist（2026-08-14）

第二轮加入 `xvk-native`、`native-relay`、`framebridge`、`hostscope` 和 `nativeport`，并检查
Homebrew、GitHub 名称搜索、npm、PyPI 和本机命令空间。crates.io 对自动状态检查返回 403，
因此 Rust crate 名称仍记为未确认；这些检查也不等同于正式商标检索。

| 候选命令 | 结果 | 判断 |
| --- | --- | --- |
| `xvk-data` | Homebrew/GitHub/npm/PyPI/本机均未发现完全同名 | **已否决**：项目所有者不接受维护者 namespace 作为产品名称 |
| `xvk-native` | 同上 | 备选；`native` 容易被理解为编程实现，而不是系统数据 |
| `native-relay` | 无完全同名，但 GitHub/Web 上有大量 React Native、网络 relay 近似结果 | 淘汰：搜索噪声大，容易被误解为网络中继 |
| `framebridge` | GitHub 有多个完全同名项目 | 淘汰 |
| `hostscope` | GitHub 有完全同名项目 | 淘汰 |
| `nativeport` | GitHub 有大小写不同的完全同名项目 | 淘汰 |

`xvk-data` 不再进入后续 shortlist。后续候选仍应由副标题表达平台能力，例如
“a native data CLI for macOS”，而不是重新把 `Mac` 或 `macOS` 放回产品名。Apple 商标列表
页面标注其内容更新至 2026-07-14，本次复核仍将 `Mac` 和 `macOS` 列为 Apple 商标，并仍
要求兼容性词汇不构成第三方产品名的一部分。

## 1.0.0 复审时可复用的迁移实现

在名称获得批准后：

1. 安装一个获批准的 canonical 命令，并把 `macos-data` 作为指向同一签名二进制的兼容
   symlink 保留一个明确兼容周期；不要维护两份可能漂移的 CLI 实现。
2. 两种调用方式必须共享同一入口并返回逐字节一致的 JSON、stdout/stderr 和退出码；help
   统一显示 canonical 名称，同时明确列出兼容别名。
3. 改名不得同时静默改变 app bundle identifier、TCC 身份、诊断目录、reserved URL label 或
   `x-macos-data://external-id/`。这些是持久化身份或数据 contract，不是普通展示名称。
4. Homebrew Cask 可先保留旧 token，并同时安装 `xvk-data` 与 `macos-data`；Cask/repository
   token 的公开迁移另做一步，避免命令、TCC 和发布渠道同时变化。
5. 先写 alias contract tests，再修改构建和安装脚本；测试必须覆盖 `--version`、`--help`、
   成功 JSON、失败 JSON 和退出码。

该迁移结构只在 1.0.0 复审或新的 ADR 明确批准名称后执行；不得再默认采用 `xvk-data`。

## 剩余可用性审计

- [x] 检查 Homebrew Formula 和 Cask 精确同名。
- [x] 检查公开 GitHub repository 精确同名。
- [x] 检查当前本机可执行命令空间。
- [x] 生成更多不含 Apple 商标且具有识别性的候选。
- [x] 检查 GitHub 和 Homebrew 近似名称，而不只检查精确同名。
- [ ] 检查相关商标数据库；如果项目超出兴趣型开源工具阶段，再获得正式法律意见。
- [ ] 对最终 shortlist 检查 repository、Homebrew Cask、常见 package registry 和实用域名；
  repository、Cask、npm、PyPI 已检查，crates.io 和域名仍未确认。
- [ ] 由人和 Agent 验证发音、拼写、搜索性和命令输入体验。
- [x] 通过 ADR 记录 0.x canonical command：继续使用 `macos-data`，1.0.0 前复审。
- [ ] 在公开改名前设计并测试别名安装、help/version、shell completion、弃用提示和回滚。
