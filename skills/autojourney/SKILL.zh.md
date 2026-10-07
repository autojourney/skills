---
name: autojourney
license: Apache-2.0
description: 用 Autojourney 浏览器插件在 AI 平台上生图、生视频、图生文，并把结果保存到本机；也用于安装、设置 Autojourney。用户想在豆包、ChatGPT、Gemini、Flow、Midjourney、即梦、Dreamina、Grok、可灵、海螺、Vidu、Runway、Higgsfield、Ideogram、千问或 Lovart 上生图、生视频、描述图片或批量创作时使用，例如「用豆包画一张图」「让 Midjourney 生成四张」「用可灵做个视频」「把这张图描述一下」「存到桌面」；用户要安装、设置 Autojourney，或提到 Autojourney / aj_send / aj_wait 时也用。
metadata:
  owner: autojourney
  version: "6"
  lang: zh
---

# Autojourney

通过用户浏览器里的 Autojourney 插件，在豆包、ChatGPT、Gemini、Midjourney、即梦、可灵等平台上生图、生视频、图生文。任务会真的在平台上跑，用的是用户自己账号的额度。

用户说什么语言就用什么语言回复。命令、路径这类细节你自己处理，对用户只说要他做什么。

下文的 `autojourney` 指本机程序，它不在 PATH 里，执行时写完整路径：macOS 是 `~/.autojourney/bin/autojourney`，Windows 是 `%USERPROFILE%\.autojourney\bin\autojourney.cmd`（在 PowerShell 里写 `& "$env:USERPROFILE\.autojourney\bin\autojourney.cmd"`）。

## 按情况去读

| 情况 | 读 |
|---|---|
| 第一次用、找不到本机程序、或者没有页面连上 | `references/setup.md` |
| 派任务、等结果、保存到本机 | `references/usage.md` |
| 出错 | `references/troubleshooting.md` |
| 上面哪份文件不在 | 运行 `autojourney guide`，打印的是同一份用法说明 |

## 规则

- 任务会扣用户在平台上的额度，拿不准用户要什么时先问再派。
- 一次要派多条时，把每条的完整参数放进 `tasks` 数组、**一次提交整批**；不要一条一条发，更不要发一条等一条。先全部提交，再按用户的意思统一等或不等。
- 之前的报错只说明那一条：页面状态正常（`aj_targets`）就照常派，不要一直揪着旧错误不放，也不要为此反复找用户要确认。
- 参考图 `refs` 填本机路径即可，不要复制、转存或上传；聊天里的图用消息里给的路径，没有就请用户提供。
- 所有功能都能用命令行完成：`autojourney <子命令>`。有 `aj_*` 工具时用工具，两者等价。
- 以工具形式接入只做你自己所在的客户端（`references/setup.md` 第 2 步，支持 Claude Code、Claude 桌面端、Codex、Cursor、VS Code、Antigravity、WorkBuddy）；别的客户端用户点名才接。不在这七家里的，用户问起就把 `autojourney add mcp --print-config` 打印的配置给用户自己配。

## 保持最新

每个新对话第一次用本技能时，运行 `autojourney --version`。它输出的 `skill_version` 比本文件开头的 `metadata.version` 大，就更新本技能文件夹，再重新读一遍本文件：运行本机程序旁边的安装器副本（macOS 是 `~/.autojourney/bin/install.sh`，用 bash 运行；Windows 一律是 `%USERPROFILE%\.autojourney\bin\install.ps1`，用 PowerShell 运行，需要时带 `-ExecutionPolicy Bypass`，有 Git Bash 或 WSL 也不要跑 `install.sh`），带参数 `--skill-only`，运行时把环境变量 `AJ_SKILL_DIR` 设为本技能文件夹的完整路径。

它只重写技能文件夹（并登记，以后会自动保持最新），不动程序。
