#!/usr/bin/env bash
# installer v1
#
# Autojourney 安装脚本（macOS）。用法：
#   curl -fsSL https://cdn.autojourney.ai/agent/install.sh | bash
#
# 做的事：识别平台 → 读这次要装的版本 → 不是同版本的安装器就换成同版本的再跑 → 拿锁 →
# 探测 node / bun，都没有就从 npm 下私有 Bun → 下本体并校验 → 原子替换 → 清隔离属性 →
# 交接给程序（init）：使用说明、安装器副本、shim、登记技能文件夹、（设了 AJ_CLIENTS 才）接入客户端、结尾说明。
# 幂等：重跑即更新；每步失败都不留残骸，已装的旧版本原样保留。
#
# 环境变量：
#   DOWNLOAD_BASE         产物地址前缀，默认 https://cdn.autojourney.ai/agent（镜像 / 内网 / 冒烟用）
#   AJ_VERSION            固定装某一版（回滚、复现问题）
#   AJ_RUNTIME_REGISTRY   覆盖 npm 源列表，逗号分隔
#   AJ_RUNTIME=private    不探测系统 node / bun，直接用私有运行时
#   AJ_NO_LINK=1          只放程序、不登记客户端（插件 bootstrap 与 shim 用，用户正常安装不带）
#   AJ_INSTALL_QUIET=1    装完只报一行，不列「接下来要用户做的几步」（shim 在某次调用中途补运行时用）
#   AJ_HOME               安装目录，默认 ~/.autojourney
#   AJ_LANG=en|zh         输出与文案的语言；不设就用已装的设置，首次安装按系统语言
#   AJ_CLIENTS=auto | a,b | all  顺带往客户端写 MCP 配置与技能：auto = 只接正在执行本脚本的那个。
#                         不设 = 不碰任何客户端（技能打头的装法：技能由 agent 先装好，本脚本只装程序，2026-09-29 实验）
#   AJ_CALLER=<id>|terminal|none  指定调用方，不去认（测试用）
#   AJ_INSTALLER_NO_HANDOFF=1  不换成同版本的安装器（开发时改了本地的安装器、直接对线上 CDN 跑时用）
# 参数：
#   --skill-only          只按本机已装的版本与语言更新 AJ_SKILL_DIR 这个技能文件夹（并登记），不动程序（技能自检用）
#
#   AJ_SKILL_DIR=<文件夹>  agent 把技能放在了哪：登记它，程序与使用说明更新后 daemon 同步它；
#                         首次安装时语言也取它的 SKILL.md 里标的 metadata.lang
#
# 所有输出走 stderr：shim 在 MCP 会话里调它时 stdout 是协议通道，不能被污染。
set -euo pipefail

SKILL_ONLY=''
for a in "$@"; do
  case $a in --skill-only) SKILL_ONLY=1 ;; esac
done

BASE=${DOWNLOAD_BASE:-https://cdn.autojourney.ai/agent}
BASE=${BASE%/} # 与 install.ps1、程序的 init 同样去掉尾斜杠，免得拼出 //latest.json
AJ_HOME=${AJ_HOME:-$HOME/.autojourney}
BIN=$AJ_HOME/bin
# 自己这个文件：管道运行（curl … | bash）时为空，手里没有文件
SELF=''
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then SELF=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}"); fi

say() { printf '%s\n' "$*" >&2; }
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
die() {
  say "✗ $*"
  exit 1
}

# 技能包里标的语言（SKILL.md frontmatter 的 metadata.lang）：用户要中文版时 agent 已把中文文件换成了 SKILL.md
skill_lang() {
  [ -n "${AJ_SKILL_DIR:-}" ] && [ -f "$AJ_SKILL_DIR/SKILL.md" ] || return 0
  awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit } /^  lang: (zh|en)[[:space:]]*$/ { print $2; exit }' "$AJ_SKILL_DIR/SKILL.md"
}

# 语言：AJ_LANG > 已装的 config.json 里的 lang（已装过的保留原设置）> 技能包标的语言 > 系统语言。
# 与程序的 currentLang 同一个顺序；定下来后既决定这里的输出，也作为 init --lang 写进 config.json
detect_lang() {
  case "${AJ_LANG:-}" in en | zh) printf '%s' "$AJ_LANG"; return ;; esac
  cfg=$AJ_HOME/config.json
  if [ -f "$cfg" ]; then
    if grep -q '"lang"[[:space:]]*:[[:space:]]*"en"' "$cfg"; then printf en; return; fi
    if grep -q '"lang"[[:space:]]*:[[:space:]]*"zh"' "$cfg"; then printf zh; return; fi
  fi
  sl=$(skill_lang)
  case "$sl" in en | zh) printf '%s' "$sl"; return ;; esac
  # 系统语言：macOS 读界面语言（AppleLanguages 第一项），不看 LANG——agent 的 shell 里 LANG 常是 en_US，
  # 豆包里装就被判成了英文（2026-09-29 实测）；读不到（沙箱拦了 defaults）才退回 LANG
  first=$(defaults read -g AppleLanguages 2>/dev/null | sed -n 2p | tr -d ' ",')
  case "$first" in
    zh*) printf zh; return ;;
    ?*) printf en; return ;;
  esac
  case "${LC_ALL:-${LANG:-}}" in en* | EN*) printf en ;; *) printf zh ;; esac
}
LANGOPT=$(detect_lang)
# m "中文" "English"：按语言取一句
m() { if [ "$LANGOPT" = en ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

# 技能文件夹：不对就只提示、不登记，不让安装失败（程序照样能用）
SKILL_DIR_OK=''
if [ -n "${AJ_SKILL_DIR:-}" ]; then
  if [ -f "$AJ_SKILL_DIR/SKILL.md" ]; then
    SKILL_DIR_OK=1
  else
    say "$(m "· AJ_SKILL_DIR（${AJ_SKILL_DIR}）里没有 SKILL.md，不登记这个技能文件夹" "· AJ_SKILL_DIR (${AJ_SKILL_DIR}) has no SKILL.md, so the skill folder won't be registered")"
  fi
fi

# ── 1. 平台 ──────────────────────────────────────────────────────────────────
os=$(uname -s)
# Windows 上的 bash（Git Bash / MSYS / Cygwin，或 WSL）：程序要装进 Windows 本身、给 Windows 原生的客户端用，这里装不了，指给同目录的 install.ps1
on_windows=''
case $os in
  MINGW* | MSYS* | CYGWIN*) on_windows=1 ;;
  Linux) if grep -qi microsoft /proc/version 2>/dev/null; then on_windows=1; fi ;;
esac
if [ -n "$on_windows" ]; then
  die "$(m "这是 Windows（当前在 $os 的 bash 里）：请改用 PowerShell 运行 install.ps1（技能文件夹 scripts/ 下有一份；或下载 https://cdn.autojourney.ai/agent/install.ps1），需要时带 -ExecutionPolicy Bypass，不要用 bash 跑 install.sh" "This is Windows (running in a $os bash): run install.ps1 with PowerShell instead (it's in the skill folder's scripts/, or download https://cdn.autojourney.ai/agent/install.ps1), adding -ExecutionPolicy Bypass if needed; don't run install.sh with bash")"
fi
[ "$os" = Darwin ] || die "$(m "这个安装脚本用于 macOS，当前系统是 $os" "This install script is for macOS; this system is $os")"
arch=$(uname -m)
# Rosetta 下的终端 uname 说 x86_64，实际是 Apple Silicon
if [ "$arch" = x86_64 ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; then arch=arm64; fi
case $arch in
  arm64) plat=darwin-arm64 ;;
  # Intel Mac 不分 AVX2：Bun 要求的 macOS 版本只装得上 2017 年以后的机型，都支持 AVX2（2026-09-30 去掉 baseline）
  x86_64) plat=darwin-x64 ;;
  *) die "$(m "不支持的架构：$arch" "Unsupported architecture: $arch")" ;;
esac

# ── 1b. 只更新技能文件夹（--skill-only）：程序已装好，交给它按本机的版本与语言重写这个文件夹 ────────
if [ -n "$SKILL_ONLY" ]; then
  # 要对齐的是本机已装的程序：本机有安装器副本（与程序同版本）且不是自己，就交给它
  if [ -z "${AJ_INSTALLER_HANDOFF:-}" ] && [ -z "${AJ_INSTALLER_NO_HANDOFF:-}" ] && [ -f "$BIN/install.sh" ] && ! { [ -n "$SELF" ] && [ "$(sha256 "$SELF")" = "$(sha256 "$BIN/install.sh")" ]; }; then
    say "$(m "· 换用本机已装版本的安装器 $BIN/install.sh" "· Switching to the installer of the installed version, $BIN/install.sh")"
    AJ_INSTALLER_HANDOFF=1 bash "$BIN/install.sh" "$@" < /dev/null
    exit $?
  fi
  [ -x "$BIN/autojourney" ] || die "$(m "本机还没装 Autojourney 程序，先去掉 --skill-only 完整安装一次" "The Autojourney program isn't installed on this machine yet; run the full install once, without --skill-only")"
  [ -n "$SKILL_DIR_OK" ] || die "$(m "--skill-only 要用 AJ_SKILL_DIR 指明技能文件夹（里面要有 SKILL.md）" "--skill-only needs AJ_SKILL_DIR pointing to the skill folder (with a SKILL.md in it)")"
  out=$("$BIN/autojourney" skill-sync --skill-dir "$AJ_SKILL_DIR" < /dev/null 2>&1) || die "$(m "更新技能文件夹失败" "Updating the skill folder failed"): $(printf '%s' "$out" | tail -3)"
  say "$(m "✓ 技能文件夹已按本机的版本更新：$AJ_SKILL_DIR" "✓ The skill folder now matches this machine's version: $AJ_SKILL_DIR")"
  exit 0
fi

# ── 2. 这次要装的版本：latest.json 与 v<V>/checksums.txt（只读，不拿锁：可能马上转交给同版本的安装器）──
TMP=$(mktemp -d)
LOCK=''
cleanup() {
  rm -rf "$TMP" 2>/dev/null || true
  [ -n "$LOCK" ] || return 0
  rm -rf "$LOCK" "$BIN"/*.tmp "$BIN/runtime"/*.tmp "$BIN/runtime/.bun.tgz" "$AJ_HOME/guide"/*.tmp 2>/dev/null || true
}
trap cleanup EXIT

fetch() { curl -fsSL --connect-timeout 10 --retry 2 --retry-delay 1 -o "$2" "$1"; }

fetch "$BASE/latest.json" "$TMP/latest.json" || die "$(m "下载 $BASE/latest.json 失败。检查网络；国内或内网用户可设 DOWNLOAD_BASE 指向镜像" "Downloading $BASE/latest.json failed. Check the network; on restricted networks set DOWNLOAD_BASE to a mirror")"
# latest.json 由 scripts/latest.ts 生成，一键一行；用 awk 取值，这台机器可能还没有任何运行时
jget() { awk -v k="\"$1\":" '$1==k {gsub(/^"|",?$/,"",$2); print $2; exit}' "$TMP/latest.json"; }
# 顶层键（缩进两格）专用：version 只认顶层的，嵌套对象里（min_extension_version 之类）同名的键不算
jtop() { awk -v k="\"$1\":" '/^  "/ && $1==k {gsub(/^"|",?$/,"",$2); print $2; exit}' "$TMP/latest.json"; }
jpkg() { awk -v p="\"$1\":" -v f="\"$2\":" '$1==p {in1=1; next} in1 && $1==f {gsub(/^"|",?$/,"",$2); print $2; exit} in1 && /^ *}/ {exit}' "$TMP/latest.json"; }
jregs() { awk '$1=="\"registries\":" {r=1; next} r && /\]/ {exit} r {gsub(/^ *"|",?$/,""); print}' "$TMP/latest.json"; }

if [ -n "${AJ_VERSION:-}" ]; then
  VERSION=$AJ_VERSION
  SCRIPT_PATH=v$VERSION/autojourney.mjs
else
  VERSION=$(jtop version)
  SCRIPT_PATH=$(jget script)
fi
[ -n "$VERSION" ] && [ -n "$SCRIPT_PATH" ] || die "$(m "$BASE/latest.json 内容不对（没有 version / files.script）" "$BASE/latest.json is malformed (no version / files.script)")"
fetch "$BASE/v$VERSION/checksums.txt" "$TMP/checksums.txt" || die "$(m "下载 $BASE/v$VERSION/checksums.txt 失败（这个版本可能不存在）" "Downloading $BASE/v$VERSION/checksums.txt failed (this version may not exist)")"

# ── 3. 换成同版本的安装器再跑：真正干活的安装器永远和它装的程序同一次发布，交接给程序的参数不用管新旧兼容 ──
# 自己就是 V 版（sha256 对得上）就往下；不是（旧副本、或 AJ_VERSION 固定了别的版本）、或者是管道运行（手里没有文件）
# 就下 v<V>/install.sh 交给它，参数与环境变量原样带过去、退出码原样返回；带着 AJ_INSTALLER_HANDOFF 的不再转交（防循环）。
# 下不到、校验不过、清单里没有（太老的版本）就用自己继续装
if [ -z "${AJ_INSTALLER_HANDOFF:-}" ] && [ -z "${AJ_INSTALLER_NO_HANDOFF:-}" ]; then
  iwant=$(awk '$2 == "install.sh" { print $1; exit }' "$TMP/checksums.txt")
  if [ -n "$iwant" ] && ! { [ -n "$SELF" ] && [ "$(sha256 "$SELF")" = "$iwant" ]; }; then
    if fetch "$BASE/v$VERSION/install.sh" "$TMP/install-v.sh" && [ "$(sha256 "$TMP/install-v.sh")" = "$iwant" ]; then
      say "$(m "· 换用与 Autojourney $VERSION 同版本的安装器" "· Switching to the installer that ships with Autojourney $VERSION")"
      # 子进程跑、父进程等它：退出时还能清掉临时目录；stdin 给 /dev/null，免得读到管道里剩下的脚本
      AJ_INSTALLER_HANDOFF=1 bash "$TMP/install-v.sh" "$@" < /dev/null
      exit $?
    fi
    say "$(m "· 没能换成同版本的安装器，继续用当前这份" "· Couldn't switch to the matching installer; continuing with this one")"
  fi
fi

# ── 4. 安装锁 ────────────────────────────────────────────────────────────────
mkdir -p "$BIN"
if ! mkdir "$AJ_HOME/install.lock" 2>/dev/null; then
  if [ -n "$(find "$AJ_HOME/install.lock" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
    rm -rf "$AJ_HOME/install.lock"
    mkdir "$AJ_HOME/install.lock" || die "$(m "拿不到安装锁 $AJ_HOME/install.lock" "Can't get the install lock $AJ_HOME/install.lock")"
  else
    die "$(m "另一个安装正在进行（$AJ_HOME/install.lock）。稍等再试；确定没有在跑的话只删掉 install.lock 这一个文件夹，不要删 $AJ_HOME" "Another install is in progress ($AJ_HOME/install.lock). Try again shortly; if you are sure none is running, delete only the install.lock folder, not $AJ_HOME")"
  fi
fi
LOCK=$AJ_HOME/install.lock

# ── 5. 运行时：node ≥ 20 或 bun ≥ 1.4；都没有就下私有 Bun（规则与 shim 一致） ──
node_ok() {
  v=$("$1" --version 2>/dev/null) || return 1
  v=${v#v}
  maj=${v%%.*}
  case $maj in '' | *[!0-9]*) return 1 ;; esac
  [ "$maj" -ge 20 ]
}
bun_ok() {
  v=$("$1" --version 2>/dev/null) || return 1
  maj=${v%%.*}
  rest=${v#*.}
  min=${rest%%.*}
  case $maj in '' | *[!0-9]*) return 1 ;; esac
  case $min in '' | *[!0-9]*) return 1 ;; esac
  [ "$maj" -gt 1 ] && return 0
  [ "$maj" -eq 1 ] && [ "$min" -ge 4 ]
}

download_bun() {
  BUNV=$(jget bun)
  NAME=$(jpkg "$plat" name)
  INTEG=$(jpkg "$plat" integrity)
  [ -n "$BUNV" ] && [ -n "$NAME" ] && [ -n "$INTEG" ] || die "$(m "latest.json 里没有 $plat 的运行时信息" "latest.json has no runtime info for $plat")"
  pkg=${NAME#@oven/}
  if [ -n "${AJ_RUNTIME_REGISTRY:-}" ]; then
    regs=$(printf '%s' "$AJ_RUNTIME_REGISTRY" | tr ',' '\n')
  elif [ "$LANGOPT" = en ]; then
    # latest.json 的源是国内优先；英文用户多半在国外，npmmirror 挪到最后（与 daemon 的 orderRegistries 同一规则）
    regs=$( (jregs | grep -v 'npmmirror\.com'; jregs | grep 'npmmirror\.com') || true)
  else
    regs=$(jregs)
  fi
  [ -n "$regs" ] || die "$(m "latest.json 里没有 npm 源列表" "latest.json has no npm registry list")"
  mkdir -p "$BIN/runtime"
  tgz=$BIN/runtime/.bun.tgz
  got_one=''
  for r in $regs; do
    url="$r/$NAME/-/$pkg-$BUNV.tgz"
    say "$(m "· 下载运行时 Bun ${BUNV}（${plat}，25–40MB，只此一次）：$url" "· Downloading the Bun ${BUNV} runtime (${plat}, 25–40MB, only once): $url")"
    if curl -fL --connect-timeout 10 --retry 1 -# -o "$tgz" "$url" 2>&2; then
      got_one=1
      break
    fi
    say "$(m "  这个源不通，换下一个" "  This registry is unreachable, trying the next one")"
  done
  [ -n "$got_one" ] || die "$(m "所有 npm 源都下不到运行时。检查网络，或设 AJ_RUNTIME_REGISTRY 指向能访问的 npm 镜像" "No npm registry could provide the runtime. Check the network, or set AJ_RUNTIME_REGISTRY to a reachable npm mirror")"
  got="sha512-$(openssl dgst -sha512 -binary "$tgz" | base64)"
  if [ "$got" != "$INTEG" ]; then
    rm -f "$tgz"
    die "$(m "运行时校验失败（sha512 与 latest.json 不一致），已删除下载的文件。请重试；反复出现请换一个 npm 源" "Runtime verification failed (sha512 doesn't match latest.json); the download was deleted. Retry; if it keeps happening, use another npm registry")"
  fi
  tar -xzf "$tgz" -C "$TMP" package/bin/bun || die "$(m "解包运行时失败" "Unpacking the runtime failed")"
  mv "$TMP/package/bin/bun" "$BIN/runtime/bun.tmp"
  chmod +x "$BIN/runtime/bun.tmp"
  xattr -d com.apple.quarantine "$BIN/runtime/bun.tmp" 2>/dev/null || true
  bun_ok "$BIN/runtime/bun.tmp" || die "$(m "下载的运行时跑不起来" "The downloaded runtime doesn't run") ($("$BIN/runtime/bun.tmp" --version 2>&1 | head -1))"
  mv -f "$BIN/runtime/bun.tmp" "$BIN/runtime/bun"
  rm -f "$tgz"
}

RUNTIME=''
if [ "${AJ_RUNTIME:-}" != private ]; then
  n=$(command -v node 2>/dev/null || true)
  if [ -n "$n" ] && node_ok "$n"; then
    RUNTIME=$n
  else
    b=$(command -v bun 2>/dev/null || true)
    if [ -n "$b" ] && bun_ok "$b"; then
      RUNTIME=$b
    fi
  fi
fi
if [ -z "$RUNTIME" ]; then
  if [ -x "$BIN/runtime/bun" ] && bun_ok "$BIN/runtime/bun"; then
    say "$(m "· 用已有的私有运行时 $BIN/runtime/bun" "· Using the existing private runtime $BIN/runtime/bun")"
  else
    if [ "${AJ_RUNTIME:-}" = private ]; then
      say "$(m "· 已按 AJ_RUNTIME=private 使用私有运行时（不看系统里的 node / bun）" "· Using the private runtime as requested by AJ_RUNTIME=private (ignoring any node / bun on the system)")"
    else
      say "$(m "· 没找到 node ≥ 20 或 bun ≥ 1.4，改用私有运行时" "· No node ≥ 20 or bun ≥ 1.4 found, using a private runtime")"
    fi
    download_bun
  fi
  RUNTIME=$BIN/runtime/bun
  export AJ_FORM=private
  # 平台键给 daemon 更新私有运行时用
  printf '%s\n' "$plat" > "$BIN/runtime/platform.txt"
fi

# ── 6. 本体：已装且一致就不重下 ────────────────────────────────────────────────
want=$(awk '$2=="autojourney.mjs" {print $1; exit}' "$TMP/checksums.txt")
[ -n "$want" ] || die "$(m "checksums.txt 里没有 autojourney.mjs 的校验值" "checksums.txt has no checksum for autojourney.mjs")"
if [ -f "$BIN/autojourney.mjs" ] && [ "$(sha256 "$BIN/autojourney.mjs")" = "$want" ]; then
  say "$(m "· Autojourney $VERSION 已是最新，本体不用重下" "· Autojourney $VERSION is already up to date, no need to download it again")"
else
  say "$(m "· 下载 Autojourney $VERSION" "· Downloading Autojourney $VERSION")"
  fetch "$BASE/$SCRIPT_PATH" "$BIN/autojourney.mjs.tmp" || die "$(m "下载 $BASE/$SCRIPT_PATH 失败" "Downloading $BASE/$SCRIPT_PATH failed")"
  got=$(sha256 "$BIN/autojourney.mjs.tmp")
  [ "$got" = "$want" ] || die "$(m "本体校验失败（sha256 与 checksums.txt 不一致），已删除下载的文件；已装的版本没有动。请重试" "Verification failed (sha256 doesn't match checksums.txt); the download was deleted and the installed version is untouched. Retry")"
  mv -f "$BIN/autojourney.mjs.tmp" "$BIN/autojourney.mjs" # 提交点：正在跑的 daemon 持有旧 inode 不受影响
fi
xattr -d com.apple.quarantine "$BIN/autojourney.mjs" 2>/dev/null || true

# ── 7. 交接给程序：使用说明、安装器副本、shim 与语言、登记技能文件夹、（要的话）接入客户端、核对版本、结尾说明 ──
# 逻辑都在程序里（src/installer/finish.ts），这里不重复写；程序与本安装器同一次发布，参数随时可改。
# 程序的输出全走 stderr；它的 stdout 也并到 stderr（shim 在 MCP 会话里调本脚本时 stdout 是协议通道）
export AJ_HOME
INIT_ARGS=(init --lang "$LANGOPT" --base "$BASE")
if [ -n "$SKILL_DIR_OK" ]; then INIT_ARGS+=(--skill-dir "$AJ_SKILL_DIR"); fi
if [ -z "${AJ_NO_LINK:-}" ] && [ -n "${AJ_CLIENTS:-}" ]; then INIT_ARGS+=(--clients "$AJ_CLIENTS"); fi
# 从文件运行就把自己交给程序复制成本机副本；管道运行时手里没有文件，程序按版本目录下载一份
if [ -n "$SELF" ] && sed -n 2p "$SELF" 2>/dev/null | grep -q '^# installer v'; then INIT_ARGS+=(--installer "$SELF"); fi
if [ -n "${AJ_INSTALL_QUIET:-}" ]; then INIT_ARGS+=(--quiet); fi
"$RUNTIME" "$BIN/autojourney.mjs" "${INIT_ARGS[@]}" < /dev/null 1>&2
