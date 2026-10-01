# First-time setup

Do these in order, finishing each step before the next.

Below, `autojourney` means the local program. It isn't on PATH, so run it by its full path: `~/.autojourney/bin/autojourney` on macOS, `%USERPROFILE%\.autojourney\bin\autojourney.cmd` on Windows (in PowerShell: `& "$env:USERPROFILE\.autojourney\bin\autojourney.cmd"`).

1. **Check the install**: run `autojourney --version`. If it doesn't print a version, install the local program first: run the installer for this machine's system from this skill folder's `scripts/` (`install.sh` with bash on macOS; on Windows always `install.ps1` with PowerShell, adding `-ExecutionPolicy Bypass` if needed, and never `install.sh` even if Git Bash or WSL is there), with the environment variable `AJ_SKILL_DIR` set to the full path of this skill folder.
   It installs the Autojourney program and its guide into `.autojourney/` in the user's home folder and registers this skill folder so it's kept up to date. If this machine has neither Node nor Bun, it also downloads a private runtime (a 25–40MB download, 60–90MB on disk), so the user doesn't need to install Node. It doesn't change PATH or touch any client's settings. When it succeeds, tell the user just "the program is installed"; don't list the runtime, file paths or other details. If it fails, tell the user the last few lines of its output.
2. **Connect the client you are running in**: if you are Claude Code, Claude Desktop, Codex, Cursor, VS Code or Antigravity, run `autojourney add mcp --client <id>` (`<id>` is claude-code / claude-desktop / codex / cursor / vscode / antigravity respectively), then tell the user just "connected to <client>; takes effect after a restart"; don't explain backups, config file locations or other details. The command line keeps working before the restart, so don't wait for it. Running it again when already connected is harmless.
   If you are not one of those six, don't connect anything. If the user asks how to use Autojourney as tools, run `autojourney add mcp --print-config` and give the user the printed config snippet to put into their client's MCP settings. Connect any other client only when the user names it, with `--client`.
3. **Self-check**: run `autojourney status`.
4. **The browser side is up to the user** (you can't do it; tell the user in your own words):
   - Install the Autojourney extension for each platform they want to use, and sign in with a **Pro** account. The extension has a different name on each platform: AutoBao on Doubao, AutoGPT on ChatGPT, AutoBanana on Gemini, DreamDance on Jimeng, and mostly AutoSail elsewhere.
   - Turn on **Agent mode** in the extension settings (it's off by default).
   - Open the platform pages they want to use and sign in; the pages connect automatically.
5. **Confirm the connection**: when the user says they're done, run `autojourney status` again. If the `extension` check passes, the pages are connected; if not, go through the reasons in its `message` with the user one by one (`references/troubleshooting.md`).
6. **Tell the user they can start**: they can just say what they want in their own words, for example (pick two or three to mention, no need to read them all):
   - "Draw an orange cat sitting on a windowsill with Doubao, watercolor style, and save it to a cats folder on my desktop"
   - "Turn this image into Ghibli style on Jimeng"
   - "Use these two images as the first and last frames for a Kling video, and download it to my desktop"
   - "Send the images in this folder to Gemini and reverse-engineer Midjourney prompts"
   - "Reverse-engineer a prompt from this image, then generate images with it on ChatGPT and on Gemini so I can compare them"
   - "Draw 'a neon street on a rainy night' on Doubao, Jimeng and Grok, one each, save them to a neon folder on my desktop named by platform"
   - "How do I use Autojourney?"

   Add one line: it can also open a platform's page, switch tabs, check job progress and history, withdraw jobs that haven't been sent yet, pause / resume a page's job queue, and switch the extension's Auto Download and Use Downloader on or off; to not wait for results, just say "just send it".
