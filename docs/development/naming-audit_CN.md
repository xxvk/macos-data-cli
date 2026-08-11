# CLI 命名与兼容性审计

状态：已于 2026-07-23 完成首轮候选清单和精确同名检查；尚未批准改名。

## 已确定的过渡约束

- 0.2.x 继续使用 `macos-data`。
- 0.3.x 可以引入不含 Apple 商标的新 canonical command。
- 至少在整个 0.3.x 周期保留并记录 `macos-data` 兼容别名。
- 新旧命令必须返回完全一致的 JSON、stdout/stderr 路由和退出码。
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

## 剩余可用性审计

- [x] 检查 Homebrew Formula 和 Cask 精确同名。
- [x] 检查公开 GitHub repository 精确同名。
- [x] 检查当前本机可执行命令空间。
- [ ] 生成更多不含 Apple 商标且具有识别性的候选。
- [ ] 检查 GitHub 和 Homebrew 近似名称，而不只检查精确同名。
- [ ] 检查相关商标数据库；如果项目超出兴趣型开源工具阶段，再获得正式法律意见。
- [ ] 对最终 shortlist 检查 repository、Homebrew Cask、常见 package registry 和实用域名。
- [ ] 由人和 Agent 验证发音、拼写、搜索性和命令输入体验。
- [ ] 批准一个 canonical name，并通过 ADR 记录决定。
- [ ] 在公开改名前设计并测试别名安装、help/version、shell completion、弃用提示和回滚。

