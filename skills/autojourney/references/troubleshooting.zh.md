# 出错时

下文的 `autojourney` 指本机程序，它不在 PATH 里，执行时写完整路径：macOS 是 `~/.autojourney/bin/autojourney`，Windows 是 `%USERPROFILE%\.autojourney\bin\autojourney.cmd`（在 PowerShell 里写 `& "$env:USERPROFILE\.autojourney\bin\autojourney.cmd"`）。

先运行 `autojourney status`。每个没通过的项都带着 `message`，写好了下一步：照做，或原样转告用户。

| 没通过的项 | 意思 | 怎么做 |
|---|---|---|
| 找不到本机程序 `autojourney` | 本机程序没装 | 重跑安装器（见下） |
| `daemon` / `port` | 本机后台服务起不来，或端口被占 | 照 `message` 做；是端口的问题，就请用户关掉占用它的程序 |
| `extension` | 没有平台页面连上 | 带用户确认三件事：页面开着并已登录；插件登录的账号是 Pro 会员；插件设置里打开了「**Agent 模式**」（默认关闭）。也可以用 `open --platform <id> --wait-sec 60` 帮用户打开页面 |
| `sandbox` | 你所在的客户端在沙箱里跑命令，连不上本机服务 | 不要反复试，照 `message` 做（一般是：允许在沙箱外执行，或重启客户端后改用 `aj_*` 工具） |
| `version` | 某个页面上的插件太旧 | 请用户更新那个插件后刷新页面 |
| `update` | 自动更新失败、已经切回原来的版本 | 照 `message` 做；当前版本照常能用 |
| `install` | 本机安装不完整 | 重跑安装器（见下） |
| 本机服务没能常驻（`sandbox` 项这么说，或 `daemon.pid` 每条命令都不同） | 你所在的客户端在命令结束时回收了进程树 | 改以工具形式接入，服务进程由客户端常驻：六家之一用 `autojourney add mcp --client <id>`，其他客户端用 `autojourney add mcp --print-config` 把配置给用户在客户端的 MCP 设置里添加，然后重启客户端。接入前的临时办法：同一条命令里先 `status`、等 15 秒再派 |
| 用户在客户端的技能列表里找不到 Autojourney | 技能文件夹放的不是你的客户端读取的目录 | 把整个 `autojourney` 文件夹挪到你客户端自己的技能目录，再重新登记：运行本机程序旁边的安装器副本（macOS 是 `~/.autojourney/bin/install.sh`，Windows 是 `%USERPROFILE%\.autojourney\bin\install.ps1`），带参数 `--skill-only`，`AJ_SKILL_DIR` 设为新位置 |

**重跑安装器**：运行本技能文件夹里 `scripts/` 下对应本机系统的安装器（macOS 是 `install.sh`，用 bash 运行；Windows 一律是 `install.ps1`，用 PowerShell 运行，需要时带 `-ExecutionPolicy Bypass`，有 Git Bash 或 WSL 也不要跑 `install.sh`），运行时把环境变量 `AJ_SKILL_DIR` 设为本技能文件夹的完整路径。命令返回 `reinstall_required` 或 `upgrade_required` 时也这样做。装完不用重启客户端。

派任务时的错误（`no_target`、`pro_required`、`needs_human`、`rate_limited` 等）见 `references/usage.md` 的「7. 出错时照 `message` 做」。
