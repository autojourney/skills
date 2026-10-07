# Autojourney：用浏览器插件在 AI 平台上生图、生视频

## 这是什么

用户的浏览器里装着 Autojourney 系列插件。**它一平台一个名字**——豆包上叫 AutoBao、ChatGPT 上叫 AutoGPT、Gemini 上叫 AutoBanana、即梦上叫 DreamDance，别的平台以此类推。要让用户去点插件时，说他屏幕上那个名字，别说「Autojourney 插件」。你调用 `aj_*` 工具，本机的 autojourney 后台服务把任务转给插件，插件在用户已登录的平台页面上替用户提交、等结果，再把产物链接（和下载到本机的文件路径）交回给你。

支持的平台：豆包（doubao）、ChatGPT（chatgpt）、Gemini、Flow、AI Studio（gemini）、Midjourney（midjourney、discord）、即梦（jimeng）、Dreamina（dreamina）、Grok（grok）、可灵（kling、klingintl）、海螺（hailuo、hailuointl）、Vidu、Runway、Higgsfield、Ideogram、千问（qwen、qianwen）、Lovart、Dola 等。平台 id 以 `aj_targets` 返回的为准，`aj_send` 也接受「豆包」「即梦」「mj」这类别名。

**插件比这份说明新时**：`aj_targets` 里出现了这里没列的平台，直接用它的 id 派任务就行（能干什么看那条的 `capabilities`）。

**任务真的会在平台上跑、会扣用户在该平台的额度。** 用户没让你批量生成时，不要自作主张一次派很多条。

## 两种调用方式

- **有 `aj_*` 工具就用工具**。这是常态：参数有定义，照着填就行。
- **没有 `aj_*` 工具、但你能执行命令**（Autojourney 刚装好、客户端还没重启；或客户端不支持 MCP）：在终端跑 `autojourney <子命令>`（`autojourney` 指本机程序，它不在 PATH 里，执行时写完整路径：macOS 是 `~/.autojourney/bin/autojourney`，Windows 是 `%USERPROFILE%\.autojourney\bin\autojourney.cmd`（在 PowerShell 里写 `& "$env:USERPROFILE\.autojourney\bin\autojourney.cmd"`））。对应关系：
  - 子命令 = 工具名去掉 `aj_`，下划线换连字符：`aj_send` → `send`，`aj_focus_tab` → `focus-tab`
  - 参数同名，`snake_case` 改 `--kebab-case`：`save_dir` → `--save-dir`，`wait_sec` → `--wait-sec`
  - 列表用逗号分隔：`--job-ids a,b`；布尔参数是开关：`--wait-download`
  - `refs` / `tasks` / `params` 给 JSON 字符串；一次派多条把数组写进文件，用 `--tasks-file <路径>`
  - 输出是同一份 JSON，这份说明里所有 `aj_* { … }` 的例子都能这样换写；`autojourney guide` 打印这份说明，`autojourney status` 自检
- **两样都没有**（只能聊天的客户端）：请用户重启客户端，`aj_*` 工具就会出现。
- 命令行返回 `daemon_unreachable` 且 `message` 提到沙箱：你所在的客户端在沙箱里跑命令、连不上本机服务。不要反复试，等重启后用工具。
- **工具一出现就换回工具**。

## 前提（页面接入的三个条件）

一个平台页面要在 `aj_targets` 里出现，三条都得满足：

1. 用户在浏览器里打开了这个平台的页面
2. 装了该平台对应的插件，且插件登录的账号是 Pro 会员
3. 在插件设置里打开了「Agent 模式」

本机服务在你第一次调用时自动拉起。它要是每条命令都是新的（`status` 里 `daemon.pid` 每次不同），见 `references/troubleshooting.md`「本机服务没能常驻」。

**平台没登录也会接入**，但任务会以 `not_logged_in` 失败——所以「页面在线」不等于「能干活」。

`aj_targets` 为空不是错误，按它返回的 `message` 提示用户逐项确认；也可以直接 `aj_open` 帮用户打开页面。

## 用户问怎么用时

以派任务为主，挑几个说，不用全念；最后带一句其他能力。用户说人话就行，不用记命令。

派任务（覆盖各类型）：
- 文生图：「用豆包画一只坐在窗台上的橘猫，水彩风格」
- 图生图：「把这张图改成吉卜力风格，发给即梦」
- 图生视频：「用可灵把这两张图做成首尾帧，生成一段视频，下载到桌面」
- 图生文：「把这个文件夹里的图发给 Gemini，反推出 Midjourney 的提示词」（插件内置模板：midjourney / qwen / doubao / jimeng / chatgpt / sora / gemini / grok，另有 title_zh / title_en / filename_zh / filename_en 起标题、起文件名）
- 图生文后生图：「把这张图反推出提示词，再分别发给 ChatGPT 和 Gemini 生成图片，放一起对比」
- 多平台、保存、命名：「同一句“雨夜的霓虹街头”，豆包、即梦、Grok 各画一张，存到桌面的 neon 文件夹，按平台名命名」

其他能力（一句带过）：打开某个平台的页面、把某个页签切到前台、看任务进度和历史、撤回还没发出去的任务、暂停 / 恢复页面的任务队列、开关插件的「自动下载」和「用下载器下载」。

要存到本机就说存到哪、叫什么名字；不想等结果就说「先发着」。

## 标准流程

1. **`aj_targets`**：看哪些平台页面在线、各自能做什么（`capabilities`）、是否连着桌面下载器（`downloader`）、页面状态（`page_note` 有话就先看，见「页面状态与控制」）
2. **没有需要的平台**：`aj_open`（带 `wait_sec: 60`）打开页面并等它接入；还是没有，就把返回的原因转告用户，不要反复轮询 `aj_targets`
3. **需要时查能力**：带参考素材、要生视频、要图生文时先 `aj_capabilities` 看平台支不支持
4. **`aj_send`** 派任务：派一条就直接写参数、拿 `job_id`；一次派多条把每条的完整参数放进 `tasks` 数组，**一次调用提交整批**——不要一条一条发，更不要发一条等一条，先全部提交再统一等。**要平台看图输出文字**（描述图片、反推提示词、按图写文案）必须带 `type: "describe"`——不带 `type` 就是生图，带着图的生图任务只会生成一张图，不会回文字
5. **等不等结果，按用户的话定**（结果与下载都由本机服务和插件记录，不靠 `aj_wait`，不等也不会丢）：
   - 用户说「先发着」「发了就行」「不用等」「回头再看」：**不调 `aj_wait`**，报一句「已提交 N 条（group=…），要看进度跟我说」就结束，让用户能接着派下一条
   - 用户没说，但一次派了 10 条以上、或者是生视频：发完先回来，报已提交和大概要多久；要等的话用户再说
   - 其余情况：**`aj_wait`** 等结果，`job_ids` 或 `group` 二选一。超时不是错误，看 `pending` 决定要不要再等一次
   - 能跑后台命令的客户端（如 Claude 的后台 Bash）：不想占住对话时把命令行版放到后台——`autojourney wait --group <g>`（要本机文件加 `--wait-download`），跑完再汇报；MCP 工具调用做不到后台
   - 之后用户问进度：`aj_wait` 带 `timeout_sec: 1`（看一眼当前状态，不卡住）或 `aj_history` 带 `group`
6. 把结果交给用户：图片 / 视频链接在 `artifacts[].url`，本机文件在 `artifacts[].path`（要求下载，见下文），图生文的文字在 `texts`

## 必须遵守的规则

### 1. 分批出图：`stage: done` 不等于全部出完

Grok、可灵、海螺、Vidu、Runway、Higgsfield、Lovart、Flow 等平台是**一批一批**出产物的。第一批出来任务就是 `done`，结果里带 `async: true`，后面还可能继续追加。

- 看到 `async: true`，用户要的是「全部」时，带 `settle_sec: 60` 再调一次 `aj_wait`：连续 60 秒没有新产物才算出齐
- 返回后才来的新产物不会丢，之后再 `aj_wait` 或 `aj_history` 能看到

### 2. 同一平台多个页面：先问，不要自己挑

同一平台开了多个页面时，`aj_send` 不带 `target` 会返回 `ambiguous_target` 并列出候选 `tab_id`。这时：

- 用户说清楚了发到哪个页面（或说「每个都发」），就按意思带 `target`（或逐个页面各发一条）
- 没说清楚，就问用户，不要随便挑一个

### 3. 要本机文件：`save_dir` + `wait_download`

- `aj_send` 带 `save_dir`（绝对路径或 `~` 开头）指定保存目录。要求该页面连着桌面下载器（`aj_targets` 的 `downloader: true`）**且下载器不太旧**，否则返回 `unsupported`，照 `message` 转告用户：打开下载器并在插件设置里开启「使用下载器下载」、或升级下载器、或者去掉 `save_dir`
- `aj_wait` 带 `wait_download: true`，会一直等到文件落盘，结果里每个产物的 `path` 是本机绝对路径
- 不带 `save_dir` 也可以 `wait_download`：文件落到浏览器默认下载目录（前提是用户开了插件的「自动下载」）；没开的话 5 秒后返回并说明
- 用户在插件里开了「下载到参考图原位置」时（`aj_targets` 里该页面 `page.settings.download_to_ref_folder: true`），不带 `save_dir`、`refs` 给本机文件的任务会存到第一张参考图所在的文件夹下（再叠插件设置的下载器文件夹、自动文件夹）；实际位置以 `artifacts[].path` 为准。要确定存到哪，还是带 `save_dir`
- 带 `wait_download` 时 `message` 说「按插件的下载设置没有下载」：用户开了「只下前 N 张」这类设置，只下了一部分；要全部产物就带 `save_dir` 重发（带 `save_dir` 的任务一律下载全部产物）
- `download` 字段：`done` 有路径；`failed` 下载失败；`unknown` 已开始下载但拿不到结果（比如下载器中途断开、页面刷新），照 `message` 转告

### 4. 自己定文件名：`save_name`

产物叫什么由你决定，不用迁就插件的命名规则。`save_name` 与 `save_dir` 一起给：

- **扩展名可以不写**：不写就跟真实产物走（图片 `.png`、视频 `.mp4`）。想指定格式就写上，比如 `001.png` 会得到真正的 PNG
- **可以带相对子路径**：`2026-09/001` 会在 `save_dir` 下建好子目录再落进去
- **多产物用 `{n}` 占位**：`001-{n}` 出四张就是 `001-1` 到 `001-4`；`{n2}` / `{n3}` 补零成 `01` / `001`。不写 `{n}` 就按插件的默认规则加后缀
- **只有 `{n}` / `{n2}` / `{n3}` 三个变量**。日期、原图名这些你自己知道，直接写进字符串
- 目标文件已存在时默认直接报错并告诉你是哪个文件：换个名字，或者带 `save_overwrite: true` 覆盖（需要较新的桌面下载器，旧版会回 `unsupported` 并提示升级）
- **最终路径以 `artifacts[].path` 为准**，不要自己拼 `save_dir` + `save_name`

### 5. 一次派多条：`tasks`

多条任务放进 `tasks` 数组，一次调用提交整批。链路本来就是批量的，不用循环调用。

- **每条自包含**：`platform` / `prompt` / `refs` / `save_dir` / `save_name` 各写各的，不会互相继承
- 一次最多 1000 条；批量时不支持 `wait_sec`，提交完用 `aj_wait` 等
- **`ok: true` 只表示至少有一条提交成功了**。没提交成功的逐条列在 `errors` 里，一定要看：`errors[].index` 是你入参数组的下标
- `jobs[].index` 同理，用它把 `job_id` 对回你的哪条输入
- 没给 `group` 的任务会被归进返回的那个 `group`，直接拿去 `aj_wait` 收整批

### 6. 取消只能撤还没发出去的

`aj_cancel` 只能撤**还没发到平台**的任务（还在排队的）。已经发到平台、正在生成的叫不停，会列在 `already_sent` 里：如实告诉用户「追不上，等它自己结束」，不要说成已取消。

### 7. 出错时照 `message` 做

每个返回 `ok: false` 的结果、每个失败任务的 `err_message`，都写好了下一步该做什么，原样转告用户或照做即可。链路不通、用户说「连不上」「没反应」时先调 `aj_status`，把失败项的 `message` 告诉用户。

**一次失败只管那一条。** 报错描述的是那一刻的页面，页面之后可能已经恢复（页面级的失败，`err_message` 末尾可能附有该页面现在的状态）。再派任务前以 `aj_targets` 里的当前状态为准，正常就照常派；不要拿之前的报错当理由不发，也不要为此反复找用户要确认。同一页面连续 3 条报同样的错，才停下来按 `message` 让用户处理。

常见的：

| 情况 | 该怎么做 |
|---|---|
| `no_target` | 平台页面没在线：`aj_open` 打开，或提醒用户检查前提三条。**如果你给了 `target`**，那多半是 tab_id 过期了（页面一刷新就换），重调 `aj_targets` 拿新的 |
| `ambiguous_target` | 见规则 2 |
| `pro_required` | 告诉用户需要该插件的 Pro 会员，`message` 里有插件名 |
| `extension_outdated` | 请用户更新插件后刷新页面 |
| `needs_human` | 页面需要人处理（验证码、登录失效）：`aj_focus_tab` 把页签切到前台，请用户处理；处理好就照常派 |
| `page_changed` | 找不到输入框或按钮，多半是页面临时停在别处：`aj_targets` 看状态，正常就重发；同一页面连续几次再请用户切回创作页或更新插件 |
| `unsupported` | 这个平台不支持这类任务或素材：换平台（`aj_capabilities` 查）。带 `save_dir` / `save_overwrite` 时也可能是下载器没连或太旧，照 `message` 说的做 |
| `rate_limited` | 平台限流：恢复时间看 `aj_targets` 里该页面的状态，到点后照常派；其他平台不受影响 |
| `busy` | 上一次解卡还没做完：等几秒用 `aj_targets` 看页面状态，不要重复调 `aj_control` |
| `reinstall_required` | 本机 Autojourney 安装不完整：执行 `message` 里的安装命令（或请用户在终端粘贴运行），装完不用重启客户端 |
| `aj_send` 成功但带 `message` | 目标页面已暂停或在长时间等待，任务已入队但会晚发：把原因告诉用户，按「页面状态与控制」处理 |

## 页面状态与控制

`aj_targets` 的每个页面带 `page`（页面状态）和 `page_note`（一句话说明，有下一步就照做）。插件较旧的页面没有 `page`，也用不了 `aj_control`。

**队列状态** `page.queue.state`（图生文队列在 `page.describe`，同样三种）：

| 状态 | 含义 | 怎么办 |
|---|---|---|
| `running` | 在跑；`waiting` 说明正在等什么 | 正常，见下面的「在等什么」 |
| `paused` | 已暂停，`pause.reason` 是原因 | 见下表。派来的任务照样入队，但恢复前不会发 |
| `idle` | 没有待发的任务 | 正常，派了任务就会开始发 |

**暂停原因** `pause.reason`：

| 原因 | 含义 | 怎么办 |
|---|---|---|
| `user` | 用户在面板上点了暂停 | 先问用户要不要恢复 |
| `agent` | AI 助手用 `aj_control` 暂停的 | 需要时 `resume` |
| `credits` | 积分 / 额度不足 | 请用户充值，用户说好了再 `resume` |
| `needs_human` | 验证码、登录等要人处理 | `aj_focus_tab` 切过去请用户处理，处理完 `resume` |
| `bots_not_found` | Discord 频道里没找到机器人 | 请用户检查频道，再 `resume` |
| `not_sendable` | 等了很久页面还是发不出去，`pause.sendable.reason` 是原因（`generating` 上一条还在生成、`uploading` 素材还在上传、`disabled` 发送按钮不可用等） | `page.actions` 里有 `unstick` 就可以建议解卡；没有就请用户看看页面卡在哪 |
| `check_failed` | 发送前检查出错，`pause.message` 带错误信息 | 把错误原样转告用户，处理后 `resume` |
| `rate_limit` | 平台限流，`pause.until` 是预计恢复时刻 | 会自己恢复，不用管 |

**在等什么** `waiting.reason`（都会自己往下走，一般不用管）：`interval` 发送间隔、`round_rest` 一轮发满后休息、`schedule` 不在定时发送时段、`queue_full` 平台上同时生成的任务满了、`rate_limit` 限流、`sendable` 在等页面能发送（`last_reason` 是原因，等满 `limit_ms` 还不行会转成 `not_sendable` 暂停）、`captcha` 在等用户完成验证（验证码 / 人机验证，可以 `aj_focus_tab` 提醒）。`until` 是预计时刻，unix 毫秒。

**`aj_control`**：

- **动手前先告诉用户**要做什么、为什么；用户说过「你看着办」才直接做。暂停的是整个页面，用户手动发的任务也会一起停
- `pause`：正在发送的那一条发完才停。页面空闲时暂停不生效，返回的 `state` 仍是 `idle`，`message` 会说明
- `resume`：只恢复已暂停的队列，不跳过发送间隔、休息这些正常等待。暂停原因没解决（比如额度还是不够）的话，下一条会再被暂停
- `unstick`：停止当前生成（能停的平台）并新建对话，让页面接着发下一条；因为发不出去而暂停的会自动恢复。**原来那条已经发到平台的任务会一直停在 `generating`**，如实告诉用户，不要说成失败或已完成。返回 `busy` 说明上一次解卡还在做，等几秒看 `aj_targets`，不要重复调
- `set`：只能改 `use_downloader`（使用下载器下载）和 `auto_download`（自动下载），都是长期设置。带 `save_dir` 的任务因为「使用下载器下载」没开而回 `unsupported` 时，就用 `set use_downloader true`；打开后一两秒下载器才连上，等 `aj_targets` 里该页面的 `downloader` 变成 `true` 再重派

**任务一直没结果**：`aj_wait` 里没完成的任务带 `stage_ms`（在当前阶段待了多久），还没发出的任务所在页面的情况写在 `message` 里。生图一般一两分钟，视频常要十几分钟，因平台而异；明显超出时看 `page_note`，把情况告诉用户，再决定要不要解卡。

## 常见场景

**生一张图**

```json
aj_send { "platform": "doubao", "prompt": "一只橘猫坐在窗台上，水彩风格" }
aj_wait { "job_ids": ["<job_id>"] }
```

没有工具时的命令行写法（其他场景照此换写）：

```bash
autojourney send --platform doubao --prompt "一只橘猫坐在窗台上，水彩风格"
autojourney wait --job-ids <job_id>
```

**生几张图，保存到桌面某个目录**

```json
aj_send { "platform": "doubao", "prompt": "橘猫，水彩", "group": "cats", "save_dir": "~/Desktop/cats" }
aj_send { "platform": "doubao", "prompt": "橘猫，油画", "group": "cats", "save_dir": "~/Desktop/cats" }
aj_wait { "group": "cats", "wait_download": true }
```

**一个文件夹的图批量改风格，结果存回原处**

先读出目录里的文件，再逐张派任务：每张的 `save_name` 用它自己的原文件名派生。

```json
aj_send { "tasks": [
  { "platform": "doubao", "prompt": "改成漫画风", "refs": ["~/pics/cat.jpg"], "save_dir": "~/pics", "save_name": "cat_comic" },
  { "platform": "doubao", "prompt": "改成漫画风", "refs": ["~/pics/dog.jpg"], "save_dir": "~/pics", "save_name": "dog_comic" }
] }
aj_wait { "group": "<返回里的 group>", "wait_download": true }
```

要按序号命名就把 `save_name` 写成 `001`、`002`……；要镜像目录结构就 `save_dir` 给输出根、`save_name` 给相对路径（`a/b/c`）。

命令行里 `tasks` 数组不好塞进参数，写进文件用 `--tasks-file`：

```bash
autojourney send --tasks-file ~/pics/tasks.json
autojourney wait --group <返回里的 group> --wait-download
```

**图生图（参考图）**

```json
aj_send { "platform": "chatgpt", "prompt": "把这张图改成吉卜力风格", "refs": ["~/Pictures/photo.jpg"] }
```

Midjourney 的风格参考 / 角色参考用 `{ "path": "...", "use": "sref" }` / `"cref"`；视频首尾帧用 `"start"` / `"end"`。

**参考图从哪来**

`refs` 只认本机文件路径。文件由本机服务直接读，不经过你，也不经过客户端的沙箱。所以：

- 不要复制、转存、上传，也不要先用终端检查文件。路径填对就行，读不到时 `aj_send` 会回 `ref_not_found` 并说明原因。
- 不要为了处理参考图改用命令行。在沙箱客户端里，终端命令写不了工作区以外的文件，用户点了允许，换一条命令还会再被拦。

按图的来源分三种：

1. **用户给了文件路径**：原样填进去，`~` 开头也可以。
2. **图贴在聊天里，消息里带着路径**：直接用这个路径。比如 ChatGPT 桌面端 / Codex 会把粘贴的图存成临时文件，消息里写成 `<image name=[Image #1] path="/var/folders/…/codex-clipboard-….png">`，把 `path` 填进 `refs`。多张图按 `[Image #1]`、`[Image #2]` 对应，用户说「第二张做风格参考」就按编号找。
3. **图贴在聊天里，看不到路径**：你拿不到这张图的文件，也存不出来。直接请用户给本机路径，并告诉对方怎么复制：macOS 在访达里选中图片按 ⌥⌘C；Windows 按住 Shift 右键图片，选「复制为路径」。不要去下载目录或临时目录里翻找。

用命令行时写法相同，`refs` 给 JSON 字符串：`--refs '["/path/a.png","/path/b.png"]'`。

派发后 30 分钟内页面会来取图，这期间不要删除或移动这些文件。

**生视频**

```json
aj_send { "platform": "kling", "prompt": "海浪拍打礁石，慢镜头", "generate_type": "video" }
aj_wait { "job_ids": ["<job_id>"], "timeout_sec": 900 }
```

视频通常要几分钟，`timeout_sec` 给长一点；到点还没好就再调一次 `aj_wait`。

**分批出图的平台，等全部出完**

```json
aj_send { "platform": "grok", "prompt": "赛博朋克城市夜景" }
aj_wait { "job_ids": ["<job_id>"], "settle_sec": 60 }
```

**图生文（描述一张图）**

```json
aj_send { "platform": "gemini", "type": "describe", "refs": ["~/Pictures/a.png"], "prompt_template": "midjourney" }
```

结果在 `texts` 里。用户要存成文件时，拿到后自己把 `texts` 写进用户指定的位置（图生文不支持 `save_dir`）。`describe_generate` 是先描述再用描述去生成，参数同上再加 `prompt_count`（一张图用前几条描述）。

**「把这个文件夹里的图发给 Gemini，反推出 Midjourney 的提示词」**

```json
aj_send { "tasks": [
  { "platform": "gemini", "type": "describe", "refs": ["~/pics/a.jpg"], "prompt_template": "midjourney" },
  { "platform": "gemini", "type": "describe", "refs": ["~/pics/b.jpg"], "prompt_template": "midjourney" }
] }
aj_wait { "group": "<返回里的 group>" }
```

每张的描述在各自的 `texts` 里；用户要存成文件就按原文件名写成 `a.txt`、`b.txt`。换成 `"prompt_template": "filename_zh"` 就是给图起中文文件名。

**「把这张图反推出提示词，再分别发给 ChatGPT 和 Gemini 生成图片」**

分两步：先图生文拿到描述，再把描述当提示词派到两个平台。`describe_generate` 只会在同一个平台上生成，跨平台要这样拆。

```json
aj_send { "platform": "gemini", "type": "describe", "refs": ["~/Pictures/a.png"] }
aj_wait { "job_ids": ["<job_id>"] }
aj_send { "tasks": [
  { "platform": "chatgpt", "prompt": "<texts 里的一条描述>" },
  { "platform": "gemini", "prompt": "<texts 里的同一条描述>" }
] }
aj_wait { "group": "<返回里的 group>" }
```

`texts` 有好几条时，把它们给用户看、让用户挑一条；用户说随便就用第一条。结果按平台分开交给用户对比。

**「同一句"雨夜的霓虹街头"，豆包、即梦、Grok 各画一张」**

```json
aj_send { "tasks": [
  { "platform": "doubao", "prompt": "雨夜的霓虹街头" },
  { "platform": "jimeng", "prompt": "雨夜的霓虹街头" },
  { "platform": "grok", "prompt": "雨夜的霓虹街头" }
] }
aj_wait { "group": "<返回里的 group>", "settle_sec": 60 }
```

Grok 分批出图，所以带 `settle_sec`。哪个平台的页面没在线，会列在 `errors` 里：`aj_open` 打开后只补发那一条。

**「让 Midjourney 以这张图为风格参考、那张为角色参考，生成剑客海报，按 01、02 编号存到图片文件夹」**

```json
aj_send { "platform": "midjourney", "prompt": "雨中的剑客，电影海报", "refs": [
  { "path": "~/Pictures/style.jpg", "use": "sref" },
  { "path": "~/Pictures/hero.png", "use": "cref" }
], "save_dir": "~/Pictures", "save_name": "剑客-{n2}" }
aj_wait { "job_ids": ["<job_id>"], "wait_download": true }
```

Midjourney 一次出四张，`{n2}` 编成 `剑客-01` 到 `剑客-04`。风格参考可以带 `weight`。

**「用可灵把这两张图做成首尾帧，生成一段视频，下载到桌面」**

```json
aj_send { "platform": "kling", "generate_type": "video", "prompt": "镜头缓缓推进，花瓣飘落", "refs": [
  { "path": "~/Desktop/first.png", "use": "start" },
  { "path": "~/Desktop/last.png", "use": "end" }
], "save_dir": "~/Desktop" }
aj_wait { "job_ids": ["<job_id>"], "timeout_sec": 900, "wait_download": true }
```

**「把这张图描述一下，用前两条描述各生成一张，都加上吉卜力风格」**

```json
aj_send { "platform": "chatgpt", "type": "describe_generate", "refs": ["~/Pictures/a.png"], "prompt_count": 2, "suffix": "，吉卜力风格" }
aj_wait { "job_ids": ["<job_id>"] }
```

`prefix` / `suffix` 只对 `describe_generate` 有效，拼在每条描述的前后。结果里 `texts` 是用到的描述，`artifacts` 是生成的图。

**「刚才那批还没发出去的先撤掉」**

```json
aj_cancel { "group": "<那批的 group>" }
```

`canceled` 是撤下的；`already_sent` 是已经发到平台、追不上的，如实告诉用户这几条还会继续生成。用户想回平台上接着改某张图时，`aj_history` 结果里的 `page_url` 就是那次生成的页面。

**「先发着，不用等」**

```json
aj_send { "tasks": [ … ], "group": "night" }
```

到此为止，不调 `aj_wait`。回复：「已提交 3 条到豆包（group=night），要看进度跟我说一声。」要存本机的话 `save_dir` 已经在任务里，下载由插件自己做，不需要有人在等。

**「看看刚才那批的进度」**

```json
aj_wait { "group": "night", "timeout_sec": 1 }
```

这是看一眼：立刻返回已完成的和 `pending` 的。要文件路径就加 `"wait_download": true`。查更早的用 `aj_history { "group": "night" }`。

**查历史、看用户手动发的任务**

```json
aj_history { "limit": 20 }
aj_history { "scope": "all", "platform": "doubao" }
```

`scope: "all"` 连用户在插件面板里手动发的也一起查（只含在线页面这次打开以来的）。用户手动发的 `job_id` 以 `local:` 开头，也能传给 `aj_wait` 等它、传给 `aj_cancel` 撤它。

## 不要做的事

- 不要反复轮询 `aj_targets` 等页面上线：用 `aj_open` 的 `wait_sec`
- 不要在提示词里自己加平台参数（如 `--ar 16:9`）除非用户明确要求；提示词原样发给平台
- 不要把 `aj_wait` 超时当成失败：看 `pending`，需要就再等
- 不要替用户决定发到多个页面中的哪一个
- 不要把 `already_sent` 说成「已取消」
- 不要没告诉用户就 `aj_control` 暂停、解卡或改设置（用户已让你自行处理的除外）
- 不要把解卡后停在 `generating` 的那条说成失败或已完成
- 不要因为之前某条失败就不再派任务：先看页面现在的状态
- 不要为了参考图复制、转存、上传文件，或改用终端命令
