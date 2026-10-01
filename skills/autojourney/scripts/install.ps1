# Autojourney 安装器（Windows，PowerShell 5.1 起）
# installer v1
#
# 用法（技能文件夹的 scripts\ 里带着它）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 [--skill-only]
#
# 与 install.sh 逐步对应：识别平台 → 读这次要装的版本 → 不是同版本的安装器就换成同版本的再跑 → 拿锁 →
# 探测 node / bun，都没有就从 npm 下私有 Bun → 下本体并校验 → 原子替换 →
# 交接给程序（init）：使用说明、安装器副本、shim、登记技能文件夹、（设了 AJ_CLIENTS 才）接入客户端、结尾说明。
# 幂等：重跑即更新；每步失败都不留残骸，已装的旧版本原样保留。
#
# 环境变量与参数同 install.sh：DOWNLOAD_BASE、AJ_VERSION、AJ_RUNTIME_REGISTRY、AJ_RUNTIME=private、AJ_NO_LINK=1、
# AJ_INSTALL_QUIET=1、AJ_HOME（默认 %USERPROFILE%\.autojourney）、AJ_LANG=en|zh、AJ_CLIENTS=auto|a,b|all、AJ_CALLER、
# AJ_SKILL_DIR=<技能文件夹>、AJ_INSTALLER_NO_HANDOFF=1（不换成同版本的安装器，开发用）；参数 --skill-only。
#
# 所有输出走 stderr：shim 在 MCP 会话里调它时 stdout 是协议通道，不能被污染。
# 不改控制台编码：跟调用方的 PowerShell 用同一个代码页，被它读走的中文才不乱。
# 符号只用 GBK 里有的（× √ ·），中文 Windows 的控制台是 936。
# 外部程序一律经 Invoke-Exe（.NET Process）启动：5.1 里 `2>` 捕获外部程序的 stderr 在 Stop 模式下会被当成异常抛出。

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # 5.1 的进度条让下载慢十几倍
try {
  # 5.1 默认不开 TLS 1.2，连 CDN 与 npm 源会失败
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

$Argv = @($args)
$SkillOnly = $Argv -contains '--skill-only'
# 自己这个文件：iex 运行时为空，手里没有文件
$Self = $PSCommandPath
$Base = if ($env:DOWNLOAD_BASE) { $env:DOWNLOAD_BASE.TrimEnd('/') } else { 'https://cdn.autojourney.ai/agent' }
$AjHome = if ($env:AJ_HOME) { $env:AJ_HOME } else { Join-Path $env:USERPROFILE '.autojourney' }
$Bin = Join-Path $AjHome 'bin'
$Shim = Join-Path $Bin 'autojourney.cmd'
$Utf8 = New-Object Text.UTF8Encoding $false

class AjDie : Exception { AjDie([string]$m) : base($m) {} }

# 被转交来的（AJ_INSTALLER_HANDOFF）按 UTF-8 写 stderr，上一层按 UTF-8 读回再用自己的编码转出；
# 不改控制台代码页，只换这一个写出口
$script:ErrW = $null
if ($env:AJ_INSTALLER_HANDOFF) {
  try { $script:ErrW = New-Object IO.StreamWriter([Console]::OpenStandardError(), $Utf8); $script:ErrW.AutoFlush = $true } catch { $script:ErrW = $null }
}
function Say([string]$s) { if ($script:ErrW) { $script:ErrW.WriteLine($s) } else { [Console]::Error.WriteLine($s) } }
function Die([string]$s) { throw [AjDie]::new($s) }
function M([string]$zh, [string]$en) { if ($script:Lang -eq 'en') { $en } else { $zh } }

# Windows 的命令行参数规则（CommandLineToArgvW）：含空格或引号才加引号，引号前的反斜杠加倍
function Format-Arg([string]$a) {
  if ($a -ne '' -and $a -notmatch '[\s"]') { return $a }
  $sb = New-Object Text.StringBuilder
  [void]$sb.Append('"')
  $bs = 0
  foreach ($c in $a.ToCharArray()) {
    if ($c -eq '\') { $bs++; continue }
    if ($c -eq '"') { [void]$sb.Append('\' * ($bs * 2 + 1)); [void]$sb.Append('"'); $bs = 0; continue }
    if ($bs) { [void]$sb.Append('\' * $bs); $bs = 0 }
    [void]$sb.Append($c)
  }
  [void]$sb.Append('\' * ($bs * 2))
  [void]$sb.Append('"')
  $sb.ToString()
}

# .cmd / .bat 不能直接当可执行文件起：CreateProcess 会隐式套一层 cmd，参数再过一遍 cmd 的解析，路径里的 & ^ 会被当成命令分隔符。
# 显式走 cmd.exe /d /s /c "<整条命令行>"：/s 让 cmd 只剥最外层那对引号，里面每一段都加引号就原样到达
function Set-ExeAndArgs([Diagnostics.ProcessStartInfo]$psi, [string]$exe, [string[]]$argv) {
  if ($exe -match '\.(cmd|bat)$') {
    $psi.FileName = 'cmd.exe'
    $line = (@("`"$exe`"") + @($argv | ForEach-Object { if ($_ -match '"') { Format-Arg $_ } else { "`"$_`"" } })) -join ' '
    $psi.Arguments = "/d /s /c `"$line`""
  } else {
    $psi.FileName = $exe
    $psi.Arguments = (@($argv) | ForEach-Object { Format-Arg $_ }) -join ' '
  }
}

# 启动外部程序：stdin 关掉（shim 里调时 stdin 是 MCP 通道），stdout / stderr 按 UTF-8 收（我们的程序输出 UTF-8）
function Invoke-Exe([string]$exe, [string[]]$argv = @()) {
  $psi = New-Object Diagnostics.ProcessStartInfo
  Set-ExeAndArgs $psi $exe $argv
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $Utf8
  $psi.StandardErrorEncoding = $Utf8
  $p = [Diagnostics.Process]::Start($psi)
  $p.StandardInput.Close()
  $err = $p.StandardError.ReadToEndAsync()
  $out = $p.StandardOutput.ReadToEnd()
  $p.WaitForExit()
  [pscustomobject]@{ Code = $p.ExitCode; Out = $out; Err = $err.Result }
}

# 启动外部程序并实时转出它的输出：stderr 按 UTF-8 逐行读、用 Say 转到自己的 stderr（编码跟调用方一致），
# stdout 也并到 stderr（shim 在 MCP 会话里调本安装器时 stdout 是协议通道）；stdin 关掉；只回退出码。
# 不用 `&` 调：5.1 里 `&` 调外部程序时 stderr 会被包装成错误记录，出错即停的模式下直接抛异常
function Invoke-Live([string]$exe, [string[]]$argv = @(), [hashtable]$envs = @{}) {
  $psi = New-Object Diagnostics.ProcessStartInfo
  Set-ExeAndArgs $psi $exe $argv
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $Utf8
  $psi.StandardErrorEncoding = $Utf8
  # 给子进程的环境变量：设在当前进程上、起完恢复，子进程继承。不用 $psi.EnvironmentVariables：
  # 有的机器上它第一次读是 null（WorkBuddy 2026-10-01 真机，32 / 64 位都复现），一索引就「无法对 Null 数组进行索引」
  $saved = @{}
  foreach ($k in $envs.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, [string]$envs[$k]) }
  try {
    $p = [Diagnostics.Process]::Start($psi)
  } finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
  }
  $p.StandardInput.Close()
  $out = $p.StandardOutput.ReadToEndAsync()
  while ($null -ne ($line = $p.StandardError.ReadLine())) { Say $line }
  $p.WaitForExit()
  foreach ($line in ($out.Result -split "`r?`n")) { if ($line) { Say $line } }
  $p.ExitCode
}

# 换成另一份安装器跑（同版本转交）：用当前这个 PowerShell（5.1 或 7），参数原样带过去，带上 AJ_INSTALLER_HANDOFF 防循环
function Invoke-Installer([string]$file) {
  $ps = (Get-Process -Id $PID).Path
  Invoke-Live $ps (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $file) + $script:Argv) @{ AJ_INSTALLER_HANDOFF = '1' }
}

function Get-ExeVersion([string]$exe) {
  try {
    $r = Invoke-Exe $exe @('--version')
    if ($r.Code -ne 0) { return $null }
    ($r.Out -split "`n")[0].Trim()
  } catch { $null }
}
function Test-Node([string]$exe) {
  $v = Get-ExeVersion $exe
  $v -match '^v?(\d+)\.' -and [int]$Matches[1] -ge 20
}
function Test-Bun([string]$exe) {
  $v = Get-ExeVersion $exe
  if ($v -notmatch '^(\d+)\.(\d+)') { return $false }
  $maj = [int]$Matches[1]; $min = [int]$Matches[2]
  $maj -gt 1 -or ($maj -eq 1 -and $min -ge 4)
}

# 校验值直接用 .NET 算，不用 Get-FileHash：它在 5.1 里是模块里的脚本函数，从 pwsh 7 经 cmd 拉起的 5.1 会继承
# pwsh 的 PSModulePath、加载不到它（CI 的 shim 自愈踩过）
function Get-Sha256([string]$f) {
  $h = [Security.Cryptography.SHA256]::Create()
  $s = [IO.File]::OpenRead($f)
  try { -join ($h.ComputeHash($s) | ForEach-Object { $_.ToString('x2') }) } finally { $s.Dispose() }
}
function Get-Sha512Base64([string]$f) {
  $h = [Security.Cryptography.SHA512]::Create()
  $s = [IO.File]::OpenRead($f)
  try { 'sha512-' + [Convert]::ToBase64String($h.ComputeHash($s)) } finally { $s.Dispose() }
}

function Fetch([string]$url, [string]$out, [int]$timeout = 60) {
  for ($i = 0; $i -lt 3; $i++) {
    try {
      Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -TimeoutSec $timeout
      return $true
    } catch {
      Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 1
    }
  }
  $false
}

# 换上文件：杀毒软件 / 索引服务会短暂锁住刚写的文件，重试几次
function Move-Into([string]$src, [string]$dst) {
  for ($i = 0; ; $i++) {
    try { Move-Item -LiteralPath $src -Destination $dst -Force; return }
    catch { if ($i -ge 5) { throw }; Start-Sleep -Milliseconds 300 }
  }
}
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $Utf8) }

# 技能包里标的语言（SKILL.md frontmatter 的 metadata.lang）
function Get-SkillLang {
  if (-not $env:AJ_SKILL_DIR) { return $null }
  $f = Join-Path $env:AJ_SKILL_DIR 'SKILL.md'
  if (-not (Test-Path -LiteralPath $f)) { return $null }
  $lines = Get-Content -LiteralPath $f -Encoding UTF8
  if ($lines.Count -eq 0 -or $lines[0] -ne '---') { return $null }
  for ($i = 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -eq '---') { break }
    if ($lines[$i] -match '^  lang: (zh|en)\s*$') { return $Matches[1] }
  }
  $null
}

# 语言：AJ_LANG > 已装的 config.json 里的 lang > 技能包标的语言 > 系统界面语言（与 install.sh、程序的 currentLang 同一个顺序）
function Get-InstallLang {
  if ($env:AJ_LANG -eq 'en' -or $env:AJ_LANG -eq 'zh') { return $env:AJ_LANG }
  $cfg = Join-Path $AjHome 'config.json'
  if (Test-Path -LiteralPath $cfg) {
    $t = [IO.File]::ReadAllText($cfg)
    if ($t -match '"lang"\s*:\s*"en"') { return 'en' }
    if ($t -match '"lang"\s*:\s*"zh"') { return 'zh' }
  }
  $sl = Get-SkillLang
  if ($sl) { return $sl }
  try { $ui = (Get-UICulture).Name } catch { $ui = '' }
  if ($ui -like 'zh*') { 'zh' } elseif ($ui) { 'en' } else { 'zh' }
}

# 本机的真实架构：x64 模拟下的进程里 PROCESSOR_ARCHITECTURE 会说 AMD64，读注册表拿系统本身的
function Get-NativeArch {
  try {
    $a = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name PROCESSOR_ARCHITECTURE).PROCESSOR_ARCHITECTURE
    if ($a) { return $a }
  } catch {}
  if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
}
# x64 有没有 AVX2：kernel32!IsProcessorFeaturePresent(PF_AVX2_INSTRUCTIONS_AVAILABLE = 40)；判断不了就当没有（用 baseline 包，只是慢一点）
function Test-Avx2 {
  try {
    if (-not ('AjNative.Cpu' -as [type])) {
      Add-Type -Namespace AjNative -Name Cpu -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool IsProcessorFeaturePresent(uint feature);'
    }
    [AjNative.Cpu]::IsProcessorFeaturePresent(40)
  } catch { $false }
}

function Main {
  $script:Lang = Get-InstallLang

  $skillDirOk = $false
  if ($env:AJ_SKILL_DIR) {
    if (Test-Path -LiteralPath (Join-Path $env:AJ_SKILL_DIR 'SKILL.md')) { $skillDirOk = $true }
    else { Say (M "· AJ_SKILL_DIR（$env:AJ_SKILL_DIR）里没有 SKILL.md，不登记这个技能文件夹" "· AJ_SKILL_DIR ($env:AJ_SKILL_DIR) has no SKILL.md, so the skill folder won't be registered") }
  }

  # ── 1. 平台 ────────────────────────────────────────────────────────────────
  if ([Environment]::OSVersion.Platform -ne 'Win32NT') { Die (M '这个安装脚本用于 Windows；macOS 请用同目录下的 install.sh' 'This install script is for Windows; on macOS use install.sh from the same folder') }
  if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) { Die (M '系统里没有 tar.exe（Windows 10 1803 起自带）。请先更新 Windows 再重试' 'tar.exe is missing (it ships with Windows 10 1803 and later). Update Windows and retry') }
  $arch = Get-NativeArch
  switch ($arch) {
    'ARM64' { $plat = 'windows-arm64' }
    'AMD64' { $plat = if (Test-Avx2) { 'windows-x64' } else { 'windows-x64-baseline' } }
    default { Die (M "不支持的架构：$arch" "Unsupported architecture: $arch") }
  }

  # ── 1b. 只更新技能文件夹（--skill-only）────────────────────────────────────
  if ($SkillOnly) {
    # 要对齐的是本机已装的程序：本机有安装器副本（与程序同版本）且不是自己，就交给它
    $local = Join-Path $Bin 'install.ps1'
    if (-not $env:AJ_INSTALLER_HANDOFF -and -not $env:AJ_INSTALLER_NO_HANDOFF -and (Test-Path -LiteralPath $local) -and -not ($Self -and (Test-Path -LiteralPath $Self) -and (Get-Sha256 $Self) -eq (Get-Sha256 $local))) {
      Say (M "· 换用本机已装版本的安装器 $local" "· Switching to the installer of the installed version, $local")
      $script:ExitCode = Invoke-Installer $local
      return
    }
    if (-not (Test-Path -LiteralPath $Shim)) { Die (M '本机还没装 Autojourney 程序，先去掉 --skill-only 完整安装一次' "The Autojourney program isn't installed on this machine yet; run the full install once, without --skill-only") }
    if (-not $skillDirOk) { Die (M '--skill-only 要用 AJ_SKILL_DIR 指明技能文件夹（里面要有 SKILL.md）' '--skill-only needs AJ_SKILL_DIR pointing to the skill folder (with a SKILL.md in it)') }
    $r = Invoke-Exe $Shim @('skill-sync', '--skill-dir', $env:AJ_SKILL_DIR)
    if ($r.Code -ne 0) { Die ((M '更新技能文件夹失败' 'Updating the skill folder failed') + ': ' + (Get-Tail ($r.Out + $r.Err))) }
    Say (M "√ 技能文件夹已按本机的版本更新：$env:AJ_SKILL_DIR" "√ The skill folder now matches this machine's version: $env:AJ_SKILL_DIR")
    return
  }

  # ── 2. 这次要装的版本：latest.json 与 v<V>/checksums.txt（只读，不拿锁：可能马上转交给同版本的安装器）──
  $script:Tmp = Join-Path ([IO.Path]::GetTempPath()) ('aj-install-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $script:Tmp | Out-Null
  $tmp = $script:Tmp
  if (-not (Fetch "$Base/latest.json" "$tmp\latest.json")) { Die (M "下载 $Base/latest.json 失败。检查网络；国内或内网用户可设 DOWNLOAD_BASE 指向镜像" "Downloading $Base/latest.json failed. Check the network; on restricted networks set DOWNLOAD_BASE to a mirror") }
  $latest = [IO.File]::ReadAllText("$tmp\latest.json") | ConvertFrom-Json
  if ($env:AJ_VERSION) { $version = $env:AJ_VERSION; $scriptPath = "v$version/autojourney.mjs" }
  else { $version = $latest.version; $scriptPath = $latest.files.script }
  if (-not $version -or -not $scriptPath) { Die (M "$Base/latest.json 内容不对（没有 version / files.script）" "$Base/latest.json is malformed (no version / files.script)") }
  if (-not (Fetch "$Base/v$version/checksums.txt" "$tmp\checksums.txt")) { Die (M "下载 $Base/v$version/checksums.txt 失败（这个版本可能不存在）" "Downloading $Base/v$version/checksums.txt failed (this version may not exist)") }
  $sums = Read-Sums "$tmp\checksums.txt"

  # ── 3. 换成同版本的安装器再跑：真正干活的安装器永远和它装的程序同一次发布，交接给程序的参数不用管新旧兼容 ──
  # 自己就是 V 版（sha256 对得上）就往下；不是、或者手里没有文件（iex 运行）就下 v<V>/install.ps1 交给它，
  # 输出实时转出、退出码原样返回；带着 AJ_INSTALLER_HANDOFF 的不再转交（防循环）。下不到、校验不过、清单里没有就用自己继续装
  if (-not $env:AJ_INSTALLER_HANDOFF -and -not $env:AJ_INSTALLER_NO_HANDOFF) {
    $iwant = $sums['install.ps1']
    if ($iwant -and -not ($Self -and (Test-Path -LiteralPath $Self) -and (Get-Sha256 $Self) -eq $iwant)) {
      $next = Join-Path $tmp 'install-v.ps1'
      if ((Fetch "$Base/v$version/install.ps1" $next) -and (Get-Sha256 $next) -eq $iwant) {
        Say (M "· 换用与 Autojourney $version 同版本的安装器" "· Switching to the installer that ships with Autojourney $version")
        $script:ExitCode = Invoke-Installer $next
        return
      }
      Say (M '· 没能换成同版本的安装器，继续用当前这份' "· Couldn't switch to the matching installer; continuing with this one")
    }
  }

  # ── 4. 安装锁 ──────────────────────────────────────────────────────────────
  New-Item -ItemType Directory -Force -Path $Bin | Out-Null
  $script:Lock = Join-Path $AjHome 'install.lock'
  try { New-Item -ItemType Directory -Path $script:Lock | Out-Null }
  catch {
    $age = (Get-Date) - (Get-Item -LiteralPath $script:Lock).CreationTime
    if ($age.TotalMinutes -gt 10) {
      Remove-Item -LiteralPath $script:Lock -Recurse -Force
      New-Item -ItemType Directory -Path $script:Lock | Out-Null
    } else {
      $script:Lock = $null # 不是我们的锁，别删
      Die (M "另一个安装正在进行（$AjHome\install.lock）。稍等再试；确定没有在跑的话删掉这个目录" "Another install is in progress ($AjHome\install.lock). Try again shortly; if you are sure none is running, delete this folder")
    }
  }

  # ── 5. 运行时：node ≥ 20 或 bun ≥ 1.4；都没有就下私有 Bun（规则与 shim 一致）──
  $runtime = $null; $private = $false
  $runtimeDir = Join-Path $Bin 'runtime'
  $privateBun = Join-Path $runtimeDir 'bun.exe'
  if ($env:AJ_RUNTIME -ne 'private') {
    $n = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($n -and (Test-Node $n.Source)) { $runtime = $n.Source }
    else {
      $b = Get-Command bun -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($b -and (Test-Bun $b.Source)) { $runtime = $b.Source }
    }
  }
  if (-not $runtime) {
    if ((Test-Path -LiteralPath $privateBun) -and (Test-Bun $privateBun)) {
      Say (M "· 用已有的私有运行时 $privateBun" "· Using the existing private runtime $privateBun")
    } else {
      if ($env:AJ_RUNTIME -eq 'private') { Say (M '· 已按 AJ_RUNTIME=private 使用私有运行时（不看系统里的 node / bun）' '· Using the private runtime as requested by AJ_RUNTIME=private (ignoring any node / bun on the system)') }
      else { Say (M '· 没找到 node ≥ 20 或 bun ≥ 1.4，改用私有运行时' '· No node ≥ 20 or bun ≥ 1.4 found, using a private runtime') }
      Get-PrivateBun $latest $plat $runtimeDir $privateBun $tmp
    }
    $runtime = $privateBun; $private = $true
    # 平台键给 daemon 更新私有运行时用
    Write-Utf8 (Join-Path $runtimeDir 'platform.txt') "$plat`n"
  }

  # ── 6. 本体：已装且一致就不重下 ─────────────────────────────────────────────────
  $want = $sums['autojourney.mjs']
  if (-not $want) { Die (M 'checksums.txt 里没有 autojourney.mjs 的校验值' 'checksums.txt has no checksum for autojourney.mjs') }
  $mjs = Join-Path $Bin 'autojourney.mjs'
  if ((Test-Path -LiteralPath $mjs) -and (Get-Sha256 $mjs) -eq $want) {
    Say (M "· Autojourney $version 已是最新，本体不用重下" "· Autojourney $version is already up to date, no need to download it again")
  } else {
    Say (M "· 下载 Autojourney $version" "· Downloading Autojourney $version")
    if (-not (Fetch "$Base/$scriptPath" "$mjs.tmp" 120)) { Die (M "下载 $Base/$scriptPath 失败" "Downloading $Base/$scriptPath failed") }
    if ((Get-Sha256 "$mjs.tmp") -ne $want) { Die (M '本体校验失败（sha256 与 checksums.txt 不一致），已删除下载的文件；已装的版本没有动。请重试' "Verification failed (sha256 doesn't match checksums.txt); the download was deleted and the installed version is untouched. Retry") }
    Move-Into "$mjs.tmp" $mjs
  }

  # ── 7. 交接给程序：使用说明、安装器副本、shim 与语言、登记技能文件夹、（要的话）接入客户端、核对版本、结尾说明 ──
  # 逻辑都在程序里（src/installer/finish.ts），这里不重复写；程序与本安装器同一次发布，参数随时可改
  # 环境变量只给子进程，不写进当前会话（交互式 & .\install.ps1 之后手敲的命令会带着 AJ_FORM=private）
  $initEnv = @{ AJ_HOME = $AjHome }
  if ($private) { $initEnv['AJ_FORM'] = 'private' }
  $initArgs = @($mjs, 'init', '--lang', $script:Lang, '--base', $Base)
  if ($skillDirOk) { $initArgs += @('--skill-dir', $env:AJ_SKILL_DIR) }
  if (-not $env:AJ_NO_LINK -and $env:AJ_CLIENTS) { $initArgs += @('--clients', $env:AJ_CLIENTS) }
  # 从文件运行就把自己交给程序复制成本机副本；拿不到自己的路径时程序按版本目录下载一份
  if ($Self -and (Test-Path -LiteralPath $Self) -and (([IO.File]::ReadAllLines($Self))[1] -like '# installer v*')) { $initArgs += @('--installer', $Self) }
  if ($env:AJ_INSTALL_QUIET) { $initArgs += '--quiet' }
  $script:ExitCode = Invoke-Live $runtime $initArgs $initEnv
}

function Get-Tail([string]$text) { (($text -split "`r?`n") | Where-Object { $_ } | Select-Object -Last 3) -join ' ' }

# checksums.txt → 文件名 → sha256
function Read-Sums([string]$f) {
  $h = @{}
  foreach ($line in [IO.File]::ReadAllLines($f)) {
    $p = $line.Trim() -split '\s+'
    if ($p.Count -eq 2) { $h[$p[1]] = $p[0].ToLowerInvariant() }
  }
  $h
}

function Get-PrivateBun($latest, [string]$plat, [string]$runtimeDir, [string]$privateBun, [string]$tmp) {
  $bunv = $latest.runtime.bun
  $pkg = $latest.runtime.packages.$plat
  if (-not $bunv -or -not $pkg -or -not $pkg.name -or -not $pkg.integrity) { Die (M "latest.json 里没有 $plat 的运行时信息" "latest.json has no runtime info for $plat") }
  $name = $pkg.name
  $file = ($name -replace '^@[^/]+/', '') + "-$bunv.tgz"
  if ($env:AJ_RUNTIME_REGISTRY) { $regs = @($env:AJ_RUNTIME_REGISTRY -split ',' | Where-Object { $_ }) }
  else {
    $regs = @($latest.runtime.registries)
    # latest.json 的源是国内优先；英文用户多半在国外，npmmirror 挪到最后（与 install.sh、daemon 同一规则）
    if ($script:Lang -eq 'en') { $regs = @($regs | Where-Object { $_ -notmatch 'npmmirror\.com' }) + @($regs | Where-Object { $_ -match 'npmmirror\.com' }) }
  }
  if ($regs.Count -eq 0) { Die (M 'latest.json 里没有 npm 源列表' 'latest.json has no npm registry list') }
  New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
  $tgz = Join-Path $tmp 'bun.tgz'
  $got = $false
  foreach ($r in $regs) {
    $url = "$($r.TrimEnd('/'))/$name/-/$file"
    Say (M "· 下载运行时 Bun $bunv（$plat，25-40MB，只此一次）：$url" "· Downloading the Bun $bunv runtime ($plat, 25-40MB, only once): $url")
    if (Fetch $url $tgz 600) { $got = $true; break }
    Say (M '  这个源不通，换下一个' '  This registry is unreachable, trying the next one')
  }
  if (-not $got) { Die (M '所有 npm 源都下不到运行时。检查网络，或设 AJ_RUNTIME_REGISTRY 指向能访问的 npm 镜像' 'No npm registry could provide the runtime. Check the network, or set AJ_RUNTIME_REGISTRY to a reachable npm mirror') }
  if ((Get-Sha512Base64 $tgz) -ne $pkg.integrity) { Die (M '运行时校验失败（sha512 与 latest.json 不一致），已删除下载的文件。请重试；反复出现请换一个 npm 源' "Runtime verification failed (sha512 doesn't match latest.json); the download was deleted. Retry; if it keeps happening, use another npm registry") }
  $r = Invoke-Exe 'tar.exe' @('-xzf', $tgz, '-C', $tmp, 'package/bin/bun.exe')
  $unpacked = Join-Path $tmp 'package\bin\bun.exe'
  if ($r.Code -ne 0 -or -not (Test-Path -LiteralPath $unpacked)) { Die ((M '解包运行时失败' 'Unpacking the runtime failed') + ': ' + (Get-Tail $r.Err)) }
  if (-not (Test-Bun $unpacked)) { Die ((M '下载的运行时跑不起来' "The downloaded runtime doesn't run") + " ($(Get-ExeVersion $unpacked))") }
  # 正在运行的 bun.exe 不能覆盖、但能改名：旧的挪成 .old，下次 daemon 启动时删
  if (Test-Path -LiteralPath $privateBun) {
    try { Remove-Item -LiteralPath $privateBun -Force }
    catch {
      Remove-Item -LiteralPath "$privateBun.old" -Force -ErrorAction SilentlyContinue
      Rename-Item -LiteralPath $privateBun -NewName 'bun.exe.old'
    }
  }
  Move-Into $unpacked $privateBun
}

$script:Lang = 'zh'
$script:Lock = $null
$script:Tmp = $null
$script:ExitCode = 0
try {
  Main
} catch [AjDie] {
  Say ('× ' + $_.Exception.Message)
  $script:ExitCode = 1
} catch {
  Say ((M '× 安装器出错：' '× The installer failed: ') + $_.Exception.Message + " ($($_.InvocationInfo.ScriptLineNumber))")
  $script:ExitCode = 1
} finally {
  if ($script:Lock) {
    Remove-Item -LiteralPath $script:Lock -Recurse -Force -ErrorAction SilentlyContinue
    # 只有拿着锁的才清残留的 .tmp：转交出去的那一层没拿锁，别动正在装的那份的文件
    Get-ChildItem -LiteralPath $Bin -Filter '*.tmp' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath (Join-Path $AjHome 'guide') -Filter '*.tmp' -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  }
  if ($script:Tmp) { Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
exit $script:ExitCode
