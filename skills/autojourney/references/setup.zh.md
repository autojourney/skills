# 首次设置

按顺序做，一步做完再做下一步。下文的 `autojourney` 指本机程序，它不在 PATH 里，执行时写完整路径：macOS 是 `~/.autojourney/bin/autojourney`，Windows 是 `%USERPROFILE%\.autojourney\bin\autojourney.cmd`（在 PowerShell 里写 `& "$env:USERPROFILE\.autojourney\bin\autojourney.cmd"`）。

1. **看装好没有**：运行 `autojourney --version`。没输出版本号，先装本机程序：运行本技能文件夹里 `scripts/` 下对应本机系统的安装器（macOS 是 `install.sh`，用 bash 运行；Windows 一律是 `install.ps1`，用 PowerShell 运行，需要时带 `-ExecutionPolicy Bypass`，有 Git Bash 或 WSL 也不要跑 `install.sh`），运行时把环境变量 `AJ_SKILL_DIR` 设为本技能文件夹的完整路径。
   它会把 Autojourney 程序和使用说明装到用户目录下的 `.autojourney/`，并登记本技能文件夹以便自动更新；本机没有 Node 或 Bun 时会另外下载一个私有运行时（下载约 25–40MB，装好约 60–90MB），不需要用户装 Node。它不改 PATH、不改任何客户端的设置。装好了对用户只说一句「程序装好了」，别列运行时、文件路径这些细节；失败时把输出的最后几行原样告诉用户。
2. **接入你所在的客户端**：你是 Claude Code、Claude 桌面端、Codex、Cursor、VS Code、Antigravity 之一，就运行 `autojourney add mcp --client <id>`（`<id>` 对应是 claude-code / claude-desktop / codex / cursor / vscode / antigravity），对用户只说一句「已接入 <客户端名>，重启后生效」，别解释备份、配置文件位置这些细节；重启前用命令行照样能用，后面的步骤不用等。已经接过会原样返回，重复运行没关系。
   不是这六家：不要接。用户问怎么以工具形式使用时，运行 `autojourney add mcp --print-config`，把打印出来的配置片段给用户，让他自己写进客户端的 MCP 设置。别的客户端只在用户点名时才用 `--client` 接。
3. **自检**：运行 `autojourney status`。
4. **浏览器那边要用户自己做**（你做不了，用自己的话告诉用户）：
   - 在浏览器里装好要用的平台对应的 Autojourney 插件，用 **Pro 会员**账号登录。插件在每个平台名字不同：豆包上叫 AutoBao、ChatGPT 上叫 AutoGPT、Gemini 上叫 AutoBanana、即梦上叫 DreamDance，其余多叫 AutoSail。
   - 在插件设置里打开「**Agent 模式**」（默认关闭）。
   - 打开要用的平台页面并登录，页面会自动连上。
5. **确认连上**：用户说做好了，再运行一次 `autojourney status`。`extension` 一项通过就说明页面连上了；没通过就照 `message` 写的原因带用户逐项排查（`references/troubleshooting.md`）。
6. **告诉用户可以开始用了**：直接用自己的话说要做什么就行，比如（挑两三个跟用户说，不用全念）：
   - 「用豆包画一只坐在窗台上的橘猫，水彩风格，存到桌面的 cats 文件夹」
   - 「把这张图改成吉卜力风格，发给即梦」
   - 「用可灵把这两张图做成首尾帧，生成一段视频，下载到桌面」
   - 「把这个文件夹里的图发给 Gemini，反推出 Midjourney 的提示词」
   - 「把这张图反推出提示词，再分别发给 ChatGPT 和 Gemini 生成图片，放在一起给我对比」
   - 「同一句“雨夜的霓虹街头”，豆包、即梦、Grok 各画一张，存到桌面的 neon 文件夹，按平台名命名」
   - 「Autojourney 怎么用？」

   再带一句：还可以打开某个平台的页面、切换页签、看任务进度和历史、撤回还没发出去的任务、暂停 / 恢复页面的任务队列、开关插件的自动下载和用下载器下载；不想等结果就说「先发着」。
