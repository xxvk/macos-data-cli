# ADR 0001：1.0.0 前保持 `macos-data`

- 状态：已接受
- 日期：2026-08-14
- 决策者：项目所有者

## 背景

项目已经审计 Apple 命名指引、Homebrew 命名空间和多组中性候选。`xvk-data` 已被明确
否决，其他候选也没有形成优于当前名称的明确选择。Calendar 0.3 的发布不应同时引入品牌、
命令、Homebrew 和 Agent 调用迁移。

## 决策

- `macos-data` 在 0.3.0 以及后续整个 0.x 阶段继续作为唯一 canonical command。
- 0.x 不增加新 CLI 别名，也不启动弃用流程。
- CLI 与项目命名在正式发布 1.0.0 前重新审视，作为 1.0.0 release gate，而不是预先承诺改名。
- 本决策不改变 repository、Homebrew token、app bundle identifier、TCC 身份、诊断目录、
  URL label `macos-data-cli` 或 `x-macos-data://external-id/` 数据 contract。
- 如 1.0.0 前出现明确法律意见、平台政策或不可接受的命名冲突，可以通过新的 ADR 提前复审。

## 结果

0.3.0 只处理 Calendar adapter 和发布质量，不承担命名迁移风险。既有 Agent、脚本和用户
不需要修改命令。未来 1.0.0 复审必须重新检查商标、registry、Homebrew、域名、迁移周期、
别名 contract tests 和回滚方案。
