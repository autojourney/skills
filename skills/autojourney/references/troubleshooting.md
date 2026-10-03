# When something goes wrong

Below, `autojourney` means the local program. It isn't on PATH, so run it by its full path: `~/.autojourney/bin/autojourney` on macOS, `%USERPROFILE%\.autojourney\bin\autojourney.cmd` on Windows (in PowerShell: `& "$env:USERPROFILE\.autojourney\bin\autojourney.cmd"`).

Start with `autojourney status`. Every check that fails comes with a `message` saying what to do next: do it, or pass it on to the user as it is.

| Failing check | What it means | What to do |
|---|---|---|
| The local program `autojourney` not found | The local program isn't installed | Rerun the installer (below) |
| `daemon` / `port` | The local background service can't start, or its port is taken | Follow the `message`; if it's about the port, the user needs to close the program using it |
| `extension` | No platform page is connected | Three things to check with the user: the page is open and signed in; the extension's account is Pro; **Agent mode** is on in the extension settings (off by default). You can also open a page with `open --platform <id> --wait-sec 60` |
| `sandbox` | Your client runs commands in a sandbox that can't reach the local service | Don't keep retrying; follow the `message` (usually: allow running outside the sandbox, or restart the client and use the `aj_*` tools) |
| `version` | The extension on some page is too old | Ask the user to update that extension and reload the page |
| `update` | An automatic update failed and was rolled back | Follow the `message`; things keep working on the current version |
| `install` | The local install is incomplete | Rerun the installer (below) |
| The local service isn't staying up (the `sandbox` check says so, or `daemon.pid` changes on every command) | Your client tears down the process tree when a command ends | Connect as tools instead, so the client keeps the server process alive: one of the seven clients runs `autojourney add mcp --client <id>`; any other client runs `autojourney add mcp --print-config` and gives the user the config to add in the client's MCP settings, then restarts the client. Until then: in one command, run `status`, wait 15 seconds, then send |
| The user can't find Autojourney in the client's skill list | The skill folder isn't in a folder your client reads | Move the whole `autojourney` folder into your client's own skills folder, then re-register it: run the installer copy next to the local program (`~/.autojourney/bin/install.sh` on macOS, `%USERPROFILE%\.autojourney\bin\install.ps1` on Windows) with `--skill-only` and `AJ_SKILL_DIR` set to the new location |

**Rerun the installer**: run the installer for this machine's system from this skill folder's `scripts/` (`install.sh` with bash on macOS; on Windows always `install.ps1` with PowerShell, adding `-ExecutionPolicy Bypass` if needed, and never `install.sh` even if Git Bash or WSL is there), with the environment variable `AJ_SKILL_DIR` set to the full path of this skill folder. The same applies when a command returns `reinstall_required` or `upgrade_required`. No client restart is needed afterwards.

Errors from sending jobs (`no_target`, `pro_required`, `needs_human`, `rate_limited` and so on) are covered in "7. On errors, do what `message` says" in `references/usage.md`.
