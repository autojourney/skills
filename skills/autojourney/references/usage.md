# Autojourney: generate images and videos on AI platforms through a browser extension

## What this is

The user's browser has the Autojourney family of extensions installed. **Each platform has its own extension name**: AutoBao on Doubao, AutoGPT on ChatGPT, AutoBanana on Gemini, DreamDance on Jimeng, and so on. When you ask the user to click the extension, use the name they see on screen, not "the Autojourney extension". You call the `aj_*` tools; the local autojourney background service hands the job to the extension, which submits it on the platform page where the user is already signed in, waits for the result, and gives you back the output links (and, if asked, the paths of the files downloaded to this machine).

Supported platforms: Doubao (doubao), ChatGPT (chatgpt), Gemini, Flow, AI Studio (gemini), Midjourney (midjourney, discord), Jimeng (jimeng), Dreamina (dreamina), Grok (grok), Kling (kling, klingintl), Hailuo (hailuo, hailuointl), Vidu, Runway, Higgsfield, Ideogram, Qwen (qwen, qianwen), Lovart, Dola and more. The platform ids returned by `aj_targets` are authoritative; `aj_send` also accepts aliases such as "doubao", "jimeng" and "mj".

**When the extension is newer than this guide**: if `aj_targets` shows a platform not listed here, just send jobs with its id (see that entry's `capabilities` for what it can do).

**Jobs really run on the platform and use the user's quota there.** Unless the user asked for batch generation, don't send many jobs at once on your own initiative.

## Two ways to call

- **If you have the `aj_*` tools, use them.** This is the normal case: the parameters are defined, just fill them in.
- **No `aj_*` tools, but you can run commands** (Autojourney was just installed and the client hasn't restarted, or the client doesn't support MCP): run `autojourney <subcommand>` (`autojourney` means the local program. It isn't on PATH, so run it by its full path: `~/.autojourney/bin/autojourney` on macOS, `%USERPROFILE%\.autojourney\bin\autojourney.cmd` on Windows (in PowerShell: `& "$env:USERPROFILE\.autojourney\bin\autojourney.cmd"`)) in a terminal. The mapping:
  - subcommand = tool name without `aj_`, underscores become hyphens: `aj_send` → `send`, `aj_focus_tab` → `focus-tab`
  - same parameter names, `snake_case` becomes `--kebab-case`: `save_dir` → `--save-dir`, `wait_sec` → `--wait-sec`
  - lists are comma-separated: `--job-ids a,b`; boolean parameters are switches: `--wait-download`
  - `refs` / `tasks` / `params` take a JSON string; to send many jobs at once, write the array to a file and use `--tasks-file <path>`
  - the output is the same JSON, so every `aj_* { … }` example in this guide can be rewritten this way; `autojourney guide` prints this guide and `autojourney status` runs the self-check
- **Neither is available** (a chat-only client): ask the user to restart the client and the `aj_*` tools will appear.
- If the command line returns `daemon_unreachable` and the `message` mentions a sandbox: your client runs commands in a sandbox that can't reach the local service. Don't keep retrying; use the tools after a restart.
- **Switch back to the tools as soon as they appear.**

## Prerequisites (three conditions for a page to connect)

For a platform page to show up in `aj_targets`, all three must hold:

1. The user has that platform's page open in the browser
2. The extension for that platform is installed, and the account signed in to the extension is a Pro member
3. "Agent mode" is turned on in the extension's settings

The local service starts on your first call. If it's a new one on every command (`daemon.pid` in `status` keeps changing), see "The local service isn't staying up" in `references/troubleshooting.md`.

**A page connects even if the user isn't signed in to the platform**, but its jobs fail with `not_logged_in`. So "page online" doesn't mean "ready to work".

An empty `aj_targets` is not an error. Ask the user to check each item as its `message` says; you can also open the page for them with `aj_open`.

## When the user asks how to use it

Lead with sending jobs: pick a few examples, no need to read them all; end with one line on the other things it can do. The user just says what they want in their own words; no commands to remember.

Sending jobs (one of each kind):
- Text to image: "Draw an orange cat sitting on a windowsill with Doubao, watercolor style"
- Image to image: "Turn this image into Ghibli style on Jimeng"
- Image to video: "Use these two images as the first and last frames for a Kling video, and download it to my desktop"
- Image to text: "Send the images in this folder to Gemini and reverse-engineer Midjourney prompts" (the extension's built-in templates: midjourney / qwen / doubao / jimeng / chatgpt / sora / gemini / grok, plus title_zh / title_en / filename_zh / filename_en for titles and file names)
- Describe, then generate: "Reverse-engineer a prompt from this image, then generate images with it on ChatGPT and on Gemini so I can compare them"
- Several platforms, saving, naming: "Draw 'a neon street on a rainy night' on Doubao, Jimeng and Grok, one each, save them to a neon folder on my desktop named by platform"

Other things it can do (one line): open a platform's page, bring a tab to the front, check job progress and history, withdraw jobs that haven't been sent yet, pause / resume a page's job queue, and switch the extension's "Auto Download" and "Use Downloader" on or off.

To save locally, say where and what to call the files; to not wait for results, say "just send it".

## Standard flow

1. **`aj_targets`**: see which platform pages are online, what each can do (`capabilities`), whether it is connected to the desktop downloader (`downloader`), and the page state (read `page_note` first if it says anything; see "Page state and control")
2. **The platform you need isn't there**: `aj_open` (with `wait_sec: 60`) opens the page and waits for it to connect; if it still isn't there, pass the returned reason on to the user instead of polling `aj_targets` over and over
3. **Check capabilities when needed**: before sending reference files, generating video, or describing images, check with `aj_capabilities` that the platform supports it
4. **`aj_send`** to send jobs: for one job, pass the parameters directly and get a `job_id`; for many, put each job's full parameters in the `tasks` array and **submit the whole batch in one call**: don't send them one at a time, and never send one and wait for it before the next; submit everything first, then wait once. **When the platform should look at images and answer in text** (describe an image, reverse-engineer a prompt, write copy from a picture), you must pass `type: "describe"`; without `type` it's a generation job, and a generation job with reference images only produces an image, never text
5. **Whether to wait depends on what the user said** (results and downloads are recorded by the local service and the extension, not by `aj_wait`; nothing is lost if you don't wait):
   - The user says "just send it", "no need to wait", "I'll check later": **don't call `aj_wait`**; say "submitted N jobs (group=…), ask me for progress whenever" and stop, so the user can send the next job
   - The user didn't say, but it's 10+ jobs at once, or video: come back after sending with "submitted" and a rough duration; wait only if the user asks
   - Otherwise: **`aj_wait`** for results, passing either `job_ids` or `group`. A timeout is not an error; look at `pending` to decide whether to wait again
   - Clients that can run background commands (such as Claude's background Bash): to keep the conversation free, run the command-line form in the background—`autojourney wait --group <g>` (add `--wait-download` for local files)—and report when it finishes; MCP tool calls can't be backgrounded
   - When the user later asks for progress: `aj_wait` with `timeout_sec: 1` (a snapshot, doesn't block) or `aj_history` with `group`
6. Hand the results to the user: image / video links are in `artifacts[].url`, local files in `artifacts[].path` (when downloading was requested, see below), and describe text in `texts`

## Rules you must follow

### 1. Batched output: `stage: done` doesn't mean everything is out

Grok, Kling, Hailuo, Vidu, Runway, Higgsfield, Lovart, Flow and some other platforms produce outputs **in batches**. The job becomes `done` as soon as the first batch arrives, with `async: true` in the result, and more may still be appended.

- When you see `async: true` and the user wants "all of them", call `aj_wait` again with `settle_sec: 60`: it is complete only after 60 seconds with no new output
- Outputs that arrive after the call returns are not lost; a later `aj_wait` or `aj_history` shows them

### 2. Several pages for the same platform: ask, don't pick one yourself

When the same platform has several pages open, `aj_send` without `target` returns `ambiguous_target` with the candidate `tab_id`s. Then:

- If the user said which page to use (or "send to each"), pass `target` accordingly (or send one job per page)
- If not, ask the user; don't pick one at random

### 3. Getting local files: `save_dir` + `wait_download`

- Give `aj_send` a `save_dir` (absolute path or starting with `~`) as the save folder. The page must be connected to the desktop downloader (`downloader: true` in `aj_targets`) **and the downloader must not be too old**; otherwise it returns `unsupported`, and you pass the `message` on to the user: open the downloader and turn on "Use Downloader" in the extension settings, upgrade the downloader, or drop `save_dir`
- Give `aj_wait` `wait_download: true` and it waits until the files are on disk; each output's `path` in the result is an absolute local path
- `wait_download` also works without `save_dir`: files go to the browser's default download folder (provided the user turned on the extension's "Auto Download"); if it's off, the call returns after 5 seconds with an explanation
- When the user has turned on the extension's "Download to reference image folder" (`page.settings.download_to_ref_folder: true` for that page in `aj_targets`), a task without `save_dir` whose `refs` are local files is saved under the folder of its first reference image (plus the extension's downloader folder and auto folder); the actual location is whatever `artifacts[].path` says. To be sure where files go, still give `save_dir`
- With `wait_download`, if `message` says some outputs "were not downloaded because of the extension's download settings": the user has a setting like "only download the first N" on, so only part was downloaded; send the job again with `save_dir` to get all outputs (tasks with `save_dir` always download every output)
- The `download` field: `done` has a path; `failed` means the download failed; `unknown` means the download started but no result came back (for example the downloader disconnected or the page was refreshed); pass on the `message`

### 4. Choosing file names: `save_name`

You decide what the outputs are called; you don't have to follow the extension's naming rules. Give `save_name` together with `save_dir`:

- **The extension is optional**: without one, the real output type is used (images `.png`, videos `.mp4`). To force a format, write it, e.g. `001.png` gives a real PNG
- **Relative subpaths are allowed**: `2026-09/001` creates the subfolder under `save_dir` and saves there
- **Use `{n}` for multiple outputs**: `001-{n}` with four images gives `001-1` to `001-4`; `{n2}` / `{n3}` zero-pad to `01` / `001`. Without `{n}`, the extension's default suffix rule applies
- **Only three variables exist: `{n}` / `{n2}` / `{n3}`.** You already know things like the date or the original file name; write them into the string directly
- If the target file already exists, the default is to fail and tell you which file: pick another name, or pass `save_overwrite: true` to overwrite (needs a recent desktop downloader; older ones return `unsupported` with an upgrade hint)
- **The final path is whatever `artifacts[].path` says**; don't build it yourself from `save_dir` + `save_name`

### 5. Sending many jobs at once: `tasks`

Put multiple jobs in the `tasks` array and submit the whole batch in one call. The pipeline is batch-oriented; there's no need to call in a loop.

- **Each job is self-contained**: `platform` / `prompt` / `refs` / `save_dir` / `save_name` are written per job and are not inherited from each other
- At most 1000 jobs per call; `wait_sec` is not supported for batches, so use `aj_wait` after submitting
- **`ok: true` only means at least one job was submitted.** The ones that failed are listed one by one in `errors`; always check it: `errors[].index` is the index in your input array
- `jobs[].index` works the same way; use it to map each `job_id` back to your input
- Jobs without a `group` are put into the `group` returned in the result; pass that straight to `aj_wait` to collect the whole batch

### 6. Cancel only works for jobs not yet sent

`aj_cancel` can only withdraw jobs that **have not been sent to the platform** yet (still queued). Jobs already sent and generating can't be stopped; they are listed in `already_sent`. Tell the user honestly that "it can't be called back, it will finish on its own"; don't say it was cancelled.

### 7. On errors, do what `message` says

Every result with `ok: false` and every failed job's `err_message` already says what to do next; pass it on to the user or follow it. When the pipeline is broken or the user says "can't connect" or "nothing happens", call `aj_status` first and tell the user the `message` of each failed check.

**A failure only covers that one job.** An error describes the page at that moment, and the page may have recovered since (for page-level failures, the end of `err_message` may include the page's current state). Before sending more, go by the current state in `aj_targets`: if it looks fine, keep sending as usual. Don't use an earlier error as a reason not to send, and don't keep asking the user for confirmation over it. Only when 3 jobs in a row on the same page fail with the same error, stop and ask the user to handle it as the `message` says.

Common ones:

| Case | What to do |
|---|---|
| `no_target` | The platform page isn't online: open it with `aj_open`, or remind the user of the three prerequisites. **If you passed a `target`**, the tab_id has most likely expired (it changes when the page is refreshed); call `aj_targets` again for the new one |
| `ambiguous_target` | See rule 2 |
| `pro_required` | Tell the user this extension needs a Pro membership; the `message` has the extension name |
| `extension_outdated` | Ask the user to update the extension and refresh the page |
| `needs_human` | The page needs a person (captcha, expired sign-in): bring the tab to the front with `aj_focus_tab` and ask the user to handle it; once handled, send as usual |
| `page_changed` | The input box or buttons can't be found, usually because the page is temporarily on another screen: check the state with `aj_targets` and resend if it looks fine; only after several in a row on the same page, ask the user to go back to the creation page or update the extension |
| `unsupported` | This platform doesn't support this kind of job or file: switch platforms (check with `aj_capabilities`). With `save_dir` / `save_overwrite` it can also mean the downloader isn't connected or is too old; do what the `message` says |
| `rate_limited` | The platform is rate limiting: see the recovery time in the page's state from `aj_targets` and send as usual once it has passed; other platforms are not affected |
| `busy` | The previous unstick hasn't finished: wait a few seconds and check the page state with `aj_targets`; don't call `aj_control` again |
| `reinstall_required` | The local Autojourney install is incomplete: run the install command in the `message` (or ask the user to paste it into a terminal); no client restart needed |
| `aj_send` succeeds but has a `message` | The target page is paused or in a long wait; the job is queued but will be sent late. Tell the user why and handle it as in "Page state and control" |

## Page state and control

Every page in `aj_targets` has `page` (the page state) and `page_note` (a one-line summary; follow it if it names a next step). Pages with an older extension have no `page` and can't be used with `aj_control`.

**Queue state** `page.queue.state` (the describe queue is in `page.describe`, with the same three states):

| State | Meaning | What to do |
|---|---|---|
| `running` | Running; `waiting` says what it is waiting for | Normal; see "What it is waiting for" below |
| `paused` | Paused; `pause.reason` is why | See the table below. Jobs you send are still queued but won't go out until it resumes |
| `idle` | Nothing waiting to be sent | Normal; it starts as soon as you send a job |

**Pause reasons** `pause.reason`:

| Reason | Meaning | What to do |
|---|---|---|
| `user` | The user clicked pause in the panel | Ask the user before resuming |
| `agent` | An AI assistant paused it with `aj_control` | `resume` when needed |
| `credits` | Not enough credits / quota | Ask the user to top up; `resume` after they say it's done |
| `needs_human` | A captcha, sign-in or similar needs a person | Switch to it with `aj_focus_tab` and ask the user to handle it; `resume` afterwards |
| `bots_not_found` | No bot found in the Discord channel | Ask the user to check the channel, then `resume` |
| `not_sendable` | The page still couldn't send after a long wait; `pause.sendable.reason` is why (`generating` the previous job is still generating, `uploading` files are still uploading, `disabled` the send button is disabled, and so on) | If `page.actions` includes `unstick`, you can suggest unsticking; otherwise ask the user to look at where the page is stuck |
| `check_failed` | The pre-send check failed; `pause.message` has the error | Pass the error on to the user as is; `resume` after it's fixed |
| `rate_limit` | The platform is rate limiting; `pause.until` is the expected recovery time | It resumes by itself; nothing to do |

**What it is waiting for** `waiting.reason` (all of these move on by themselves; usually nothing to do): `interval` the gap between sends, `round_rest` a rest after a full round, `schedule` outside the scheduled sending window, `queue_full` the platform's concurrent generation slots are full, `rate_limit` rate limiting, `sendable` waiting for the page to be able to send (`last_reason` is why; if it still can't after `limit_ms` it turns into a `not_sendable` pause), `captcha` waiting for the user to complete a verification (captcha / human check; you can remind them with `aj_focus_tab`). `until` is the expected time in unix milliseconds.

**`aj_control`**:

- **Tell the user first** what you are going to do and why; act directly only if the user said "handle it yourself". Pausing affects the whole page, including jobs the user sent by hand
- `pause`: the job currently being sent finishes before it stops. Pausing an idle page has no effect; the returned `state` stays `idle` and the `message` explains
- `resume`: only resumes a paused queue; it doesn't skip normal waits such as the send interval or rests. If the reason for the pause isn't fixed (for example still not enough credits), the next job will be paused again
- `unstick`: stops the current generation (on platforms that allow it) and starts a new chat so the page can send the next job; a queue paused because it couldn't send resumes automatically. **The job already sent to the platform stays at `generating` forever**; tell the user honestly, don't call it failed or done. `busy` means the previous unstick is still in progress; wait a few seconds and check `aj_targets`, don't call again
- `set`: can only change `use_downloader` ("Use Downloader") and `auto_download` ("Auto Download"); both are lasting settings. When a job with `save_dir` returns `unsupported` because "Use Downloader" is off, use `set use_downloader true`; the downloader needs a second or two to connect, so wait until that page's `downloader` in `aj_targets` becomes `true` before sending again

**A job has no result for a long time**: unfinished jobs in `aj_wait` carry `stage_ms` (how long they've been in the current stage), and for jobs not sent yet, the `message` describes the page's situation. Images usually take a minute or two and videos often more than ten minutes, depending on the platform. When it's clearly overdue, look at `page_note`, tell the user what's going on, and then decide whether to unstick.

## Common scenarios

**Generate one image**

```json
aj_send { "platform": "doubao", "prompt": "An orange cat sitting on a windowsill, watercolor" }
aj_wait { "job_ids": ["<job_id>"] }
```

The command-line form when there are no tools (rewrite the other scenarios the same way):

```bash
autojourney send --platform doubao --prompt "An orange cat sitting on a windowsill, watercolor"
autojourney wait --job-ids <job_id>
```

**Generate a few images and save them to a folder on the desktop**

```json
aj_send { "platform": "doubao", "prompt": "Orange cat, watercolor", "group": "cats", "save_dir": "~/Desktop/cats" }
aj_send { "platform": "doubao", "prompt": "Orange cat, oil painting", "group": "cats", "save_dir": "~/Desktop/cats" }
aj_wait { "group": "cats", "wait_download": true }
```

**Restyle every image in a folder and save the results back there**

List the files in the folder first, then send one job per image, deriving each `save_name` from its own original file name.

```json
aj_send { "tasks": [
  { "platform": "doubao", "prompt": "Turn this into a comic style", "refs": ["~/pics/cat.jpg"], "save_dir": "~/pics", "save_name": "cat_comic" },
  { "platform": "doubao", "prompt": "Turn this into a comic style", "refs": ["~/pics/dog.jpg"], "save_dir": "~/pics", "save_name": "dog_comic" }
] }
aj_wait { "group": "<group from the result>", "wait_download": true }
```

To number the files, write `save_name` as `001`, `002`, …; to mirror a folder structure, give the output root as `save_dir` and the relative path as `save_name` (`a/b/c`).

On the command line the `tasks` array doesn't fit well into an argument; write it to a file and use `--tasks-file`:

```bash
autojourney send --tasks-file ~/pics/tasks.json
autojourney wait --group <group from the result> --wait-download
```

**Image to image (reference image)**

```json
aj_send { "platform": "chatgpt", "prompt": "Redraw this in Ghibli style", "refs": ["~/Pictures/photo.jpg"] }
```

For Midjourney style / character references use `{ "path": "...", "use": "sref" }` / `"cref"`; for the first / last frame of a video use `"start"` / `"end"`.

**Where reference images come from**

`refs` only takes local file paths. The local service reads the files directly, not through you and not through the client's sandbox. So:

- Don't copy, re-save or upload them, and don't check the files with terminal commands first. A correct path is enough; if a file can't be read, `aj_send` returns `ref_not_found` with the reason.
- Don't switch to the command line to deal with reference images. In sandboxed clients, terminal commands can't write outside the workspace; even after the user clicks allow, a slightly different command gets blocked again.

Three cases, by where the image comes from:

1. **The user gave a file path**: use it as is; paths starting with `~` work too.
2. **The image is in the chat and the message carries a path**: use that path. For example, the ChatGPT desktop app / Codex saves pasted images as temporary files and the message shows `<image name=[Image #1] path="/var/folders/…/codex-clipboard-….png">`; put that `path` in `refs`. Multiple images map to `[Image #1]`, `[Image #2]`; when the user says "use the second one as the style reference", go by that number.
3. **The image is in the chat but there is no path**: you can't get the file, and you can't save one either. Ask the user for the local path and tell them how to copy it: on macOS select the image in Finder and press ⌥⌘C; on Windows hold Shift, right-click the image and choose "Copy as path". Don't go searching through the downloads or temp folders.

On the command line it works the same way; give `refs` as a JSON string: `--refs '["/path/a.png","/path/b.png"]'`.

The page fetches the images within 30 minutes of sending; don't delete or move the files in the meantime.

**Generate a video**

```json
aj_send { "platform": "kling", "prompt": "Waves crashing on rocks, slow motion", "generate_type": "video" }
aj_wait { "job_ids": ["<job_id>"], "timeout_sec": 900 }
```

Videos usually take several minutes, so give a longer `timeout_sec`; if it's not ready in time, call `aj_wait` again.

**Platforms that output in batches: wait until everything is out**

```json
aj_send { "platform": "grok", "prompt": "Cyberpunk city at night" }
aj_wait { "job_ids": ["<job_id>"], "settle_sec": 60 }
```

**Describe an image (image to text)**

```json
aj_send { "platform": "gemini", "type": "describe", "refs": ["~/Pictures/a.png"], "prompt_template": "midjourney" }
```

The result is in `texts`. When the user wants it in a file, write `texts` to the location the user asked for yourself (describe doesn't support `save_dir`). `describe_generate` describes first and then generates from the description; same parameters plus `prompt_count` (how many of the descriptions to use per image).

**"Send the images in this folder to Gemini and reverse-engineer Midjourney prompts"**

```json
aj_send { "tasks": [
  { "platform": "gemini", "type": "describe", "refs": ["~/pics/a.jpg"], "prompt_template": "midjourney" },
  { "platform": "gemini", "type": "describe", "refs": ["~/pics/b.jpg"], "prompt_template": "midjourney" }
] }
aj_wait { "group": "<the group from the response>" }
```

Each image's description is in its own `texts`; when the user wants files, write them as `a.txt`, `b.txt` after the original names. With `"prompt_template": "filename_zh"` it names the images in Chinese instead.

**"Reverse-engineer a prompt from this image, then generate images with it on ChatGPT and on Gemini"**

Two steps: describe the image first, then send the description as the prompt to both platforms. `describe_generate` only generates on the same platform, so a cross-platform request is split like this.

```json
aj_send { "platform": "gemini", "type": "describe", "refs": ["~/Pictures/a.png"] }
aj_wait { "job_ids": ["<job_id>"] }
aj_send { "tasks": [
  { "platform": "chatgpt", "prompt": "<one description from texts>" },
  { "platform": "gemini", "prompt": "<the same description>" }
] }
aj_wait { "group": "<group from the result>" }
```

If `texts` has several descriptions, show them and let the user pick one; if they don't mind, use the first. Hand the results back grouped by platform so the user can compare.

**"Draw 'a neon street on a rainy night' on Doubao, Jimeng and Grok, one each"**

```json
aj_send { "tasks": [
  { "platform": "doubao", "prompt": "a neon street on a rainy night" },
  { "platform": "jimeng", "prompt": "a neon street on a rainy night" },
  { "platform": "grok", "prompt": "a neon street on a rainy night" }
] }
aj_wait { "group": "<group from the result>", "settle_sec": 60 }
```

Grok delivers in batches, hence `settle_sec`. A platform whose page isn't online shows up in `errors`: open it with `aj_open`, then send just that one again.

**"Have Midjourney make a swordsman poster using this image as the style reference and that one as the character reference, numbered 01, 02 in my Pictures folder"**

```json
aj_send { "platform": "midjourney", "prompt": "a swordsman in the rain, movie poster", "refs": [
  { "path": "~/Pictures/style.jpg", "use": "sref" },
  { "path": "~/Pictures/hero.png", "use": "cref" }
], "save_dir": "~/Pictures", "save_name": "swordsman-{n2}" }
aj_wait { "job_ids": ["<job_id>"], "wait_download": true }
```

Midjourney makes four at a time; `{n2}` numbers them `swordsman-01` to `swordsman-04`. The style reference can take a `weight`.

**"Use these two images as the first and last frames for a Kling video, and download it to my desktop"**

```json
aj_send { "platform": "kling", "generate_type": "video", "prompt": "slow push-in, petals falling", "refs": [
  { "path": "~/Desktop/first.png", "use": "start" },
  { "path": "~/Desktop/last.png", "use": "end" }
], "save_dir": "~/Desktop" }
aj_wait { "job_ids": ["<job_id>"], "timeout_sec": 900, "wait_download": true }
```

**"Describe this image, generate one picture from each of the first two descriptions, and make them Ghibli style"**

```json
aj_send { "platform": "chatgpt", "type": "describe_generate", "refs": ["~/Pictures/a.png"], "prompt_count": 2, "suffix": ", Ghibli style" }
aj_wait { "job_ids": ["<job_id>"] }
```

`prefix` / `suffix` only apply to `describe_generate` and are added before / after each description. In the result, `texts` are the descriptions used and `artifacts` the generated images.

**"Withdraw the ones from that batch that haven't been sent yet"**

```json
aj_cancel { "group": "<that batch's group>" }
```

`canceled` lists the withdrawn ones; `already_sent` lists the ones already on the platform that can't be stopped, so tell the user honestly that those will keep generating. When the user wants to go back to the platform to keep editing an image, `page_url` in the `aj_history` result is the page of that generation.

**"Just send it, don't wait"**

```json
aj_send { "tasks": [ … ], "group": "night" }
```

Stop there; don't call `aj_wait`. Reply: "Submitted 3 jobs to Doubao (group=night); ask me for progress whenever." If local files were requested, `save_dir` is already in the jobs and the extension does the downloading; nobody needs to be waiting.

**"How's that batch doing?"**

```json
aj_wait { "group": "night", "timeout_sec": 1 }
```

A snapshot: returns the finished ones and the `pending` ones right away. Add `"wait_download": true` for file paths. For older batches use `aj_history { "group": "night" }`.

**Check history and jobs the user sent by hand**

```json
aj_history { "limit": 20 }
aj_history { "scope": "all", "platform": "doubao" }
```

`scope: "all"` also includes jobs the user sent from the extension panel (only those since the online page was opened this time). A `job_id` the user sent by hand starts with `local:`; you can pass it to `aj_wait` to wait for it and to `aj_cancel` to withdraw it.

## Don'ts

- Don't poll `aj_targets` repeatedly waiting for a page to come online: use `aj_open` with `wait_sec`
- Don't add platform parameters to the prompt yourself (such as `--ar 16:9`) unless the user explicitly asks; prompts are sent to the platform as is
- Don't treat an `aj_wait` timeout as a failure: look at `pending` and wait again if needed
- Don't decide for the user which of several pages to send to
- Don't describe `already_sent` as "cancelled"
- Don't pause, unstick or change settings with `aj_control` without telling the user (unless they asked you to handle it yourself)
- Don't describe the job left at `generating` after an unstick as failed or done
- Don't stop sending jobs because an earlier one failed: check the page's current state first
- Don't copy, re-save or upload files for reference images, or switch to terminal commands for them
