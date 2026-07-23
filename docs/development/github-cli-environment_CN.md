# GitHub CLI 运行环境 Know-how

## 目的

用于诊断 `gh` 在 Codex、Terminal 或其他非交互式 shell 中无法使用的情况。
本流程只做环境和认证检查，不会自动登录，也不会把 token 写入仓库。

## 诊断顺序

```bash
command -v gh
gh --version
gh auth status -h github.com
gh api user --jq .login
```

### 1. 找不到 `gh`

Codex 使用的非交互式 zsh 不一定读取 `~/.zprofile`。Apple Silicon Homebrew
通常位于 `/opt/homebrew/bin`，可以在 `~/.zshenv` 中加入：

```zsh
if [ -d /opt/homebrew/bin ]; then
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
fi
```

修改后必须重新启动终端或 Codex 进程，再确认：

```text
/opt/homebrew/bin/gh
```

### 2. 找得到但网络或认证失败

`gh auth status` 或 `gh api user` 失败时，不要立即重新登录。先区分：

- 当前沙箱或进程是否允许访问 `api.github.com`
- 当前进程是否能读取 macOS Keychain 中的 `gh` 凭据
- Terminal、Ghostty 与 Codex 是否使用了不同的权限环境

应在获准联网的环境中重复上述只读检查。只有联网环境仍明确报告 token
无效时，才执行：

```bash
gh auth login
```

不要把 GitHub token 写入 Markdown、`.zshenv`、仓库文件或诊断日志。

## macos-data 发布检查中的使用方式

```bash
bash scripts/check_public_release_prerequisites.sh
```

该脚本只报告 GitHub CLI 状态，不打印 token，不执行登录，也不创建 Release。
网络失败应记录为“无法验证远程状态”，不能直接判断 token 已失效。

## 本机验证记录

2026-07-23 在联网且允许读取 Keychain 的环境中验证通过：

- `gh`：`/opt/homebrew/bin/gh`
- 版本：`2.93.0`
- `gh auth status -h github.com`：已登录 `xxvk`
- `gh api user --jq .login`：`xxvk`

该记录只说明当次环境状态，不构成 token 或远程发布永久有效的保证。
