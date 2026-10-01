---
name: autojourney
license: Apache-2.0
description: Generate images and videos, describe images, and save the results to this machine on AI platforms through the Autojourney browser extension; also installs and sets up Autojourney. Use when the user wants to generate images or videos, describe an image, or batch-create on Doubao (豆包), ChatGPT, Gemini, Flow, Midjourney, Jimeng (即梦), Dreamina, Grok, Kling (可灵), Hailuo (海螺), Vidu, Runway, Higgsfield, Ideogram, Qwen (千问) or Lovart — e.g. "draw a picture with Doubao", "make four images with Midjourney", "make a video with Kling", "describe this image", "save them to the desktop" — or asks to install / set up Autojourney, or mentions Autojourney / aj_send / aj_wait.
metadata:
  owner: autojourney
  version: "1"
  lang: en
---

# Autojourney

Autojourney drives the Autojourney extension in the user's browser to generate images and videos and describe images on Doubao, ChatGPT, Gemini, Midjourney, Jimeng, Kling and other platforms. Jobs really run on those platforms and use the user's own account credits.

Reply in the language the user speaks. Keep technical details (commands, paths) to yourself; tell the user only what they need to do.

Below, `autojourney` means the local program. It isn't on PATH, so run it by its full path: `~/.autojourney/bin/autojourney` on macOS, `%USERPROFILE%\.autojourney\bin\autojourney.cmd` on Windows (in PowerShell: `& "$env:USERPROFILE\.autojourney\bin\autojourney.cmd"`).

## Where to go

| Situation | Read |
|---|---|
| First time using it, the local program isn't installed, or no page is connected | `references/setup.md` |
| Sending jobs, waiting for results, saving to this machine | `references/usage.md` |
| Something fails | `references/troubleshooting.md` |
| Any of the files above is missing | Run `autojourney guide`: it prints the same usage guide |

## Rules

- Jobs cost the user's credits on the platform. When you're not sure what the user wants, ask before sending.
- Everything works from the command line: `autojourney <subcommand>`. If `aj_*` tools are available, use them instead; they are the same thing.
- Connect Autojourney as tools only to the client you are running in (`references/setup.md` step 2; supported: Claude Code, Claude Desktop, Codex, Cursor, VS Code, Antigravity); connect any other client only when the user names it. If you are not one of those six and the user asks, give them the config printed by `autojourney add mcp --print-config` to set up themselves.

## Staying up to date

The first time you use this skill in a new conversation, run `autojourney --version`. If the `skill_version` it prints is greater than `metadata.version` at the top of this file, update this skill folder, then reread this file: run the installer copy next to the local program (`~/.autojourney/bin/install.sh` with bash on macOS; on Windows always `%USERPROFILE%\.autojourney\bin\install.ps1` with PowerShell, adding `-ExecutionPolicy Bypass` if needed, and never `install.sh` even if Git Bash or WSL is there) with the argument `--skill-only`, and the environment variable `AJ_SKILL_DIR` set to the full path of this skill folder.

This only rewrites the skill folder (and registers it, so it's kept up to date automatically afterwards); it doesn't touch the program.
