#!/usr/bin/env bash
# installer v1
#
# AutoJourney 安装脚本（macOS）。用法：
#   curl -fsSL https://cdn.autojourney.ai/agent/install.sh | bash
#
# 做的事（docs/m4b.md §1）：识别平台 → 拉 latest.json → 探测 node / bun，都没有就从 npm 下私有 Bun →
# 下本体并校验 → 原子替换 → 清隔离属性 → `autojourney link` 登记客户端 → 核对版本、打印下一步。
# 幂等：重跑即更新；每步失败都不留残骸，已装的旧版本原样保留。
#
# 环境变量：
#   DOWNLOAD_BASE         产物地址前缀，默认 https://cdn.autojourney.ai/agent（镜像 / 内网 / 冒烟用）
#   AJ_VERSION            固定装某一版（回滚、复现问题）
#   AJ_RUNTIME_REGISTRY   覆盖 npm 源列表，逗号分隔
#   AJ_RUNTIME=private    不探测系统 node / bun，直接用私有运行时
#   AJ_NO_LINK=1          只放程序、不登记客户端（插件 bootstrap 与 shim 用，用户正常安装不带）
#   AJ_HOME               安装目录，默认 ~/.autojourney
#
# 所有输出走 stderr：shim 在 MCP 会话里调它时 stdout 是协议通道，不能被污染。
set -euo pipefail

BASE=${DOWNLOAD_BASE:-https://cdn.autojourney.ai/agent}
AJ_HOME=${AJ_HOME:-$HOME/.autojourney}
BIN=$AJ_HOME/bin
INSTALL_CMD='curl -fsSL https://cdn.autojourney.ai/agent/install.sh | bash'

say() { printf '%s\n' "$*" >&2; }
die() {
  say "✗ $*"
  exit 1
}

# ── 1. 平台 ──────────────────────────────────────────────────────────────────
os=$(uname -s)
[ "$os" = Darwin ] || die "目前只支持 macOS（Windows 随后提供），当前系统：$os"
arch=$(uname -m)
# Rosetta 下的终端 uname 说 x86_64，实际是 Apple Silicon
if [ "$arch" = x86_64 ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; then arch=arm64; fi
case $arch in
  arm64) plat=darwin-arm64 ;;
  x86_64)
    if sysctl -n machdep.cpu.leaf7_features 2>/dev/null | grep -q AVX2; then plat=darwin-x64; else plat=darwin-x64-baseline; fi
    ;;
  *) die "不支持的架构：$arch" ;;
esac

# ── 2. 安装锁 ────────────────────────────────────────────────────────────────
mkdir -p "$BIN"
LOCK=$AJ_HOME/install.lock
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
    rm -rf "$LOCK"
    mkdir "$LOCK" || die "拿不到安装锁 $LOCK"
  else
    die "另一个安装正在进行（${LOCK}）。稍等再试；确定没有在跑的话删掉这个目录"
  fi
fi
TMP=$(mktemp -d)
cleanup() {
  rm -rf "$LOCK" "$TMP" "$BIN"/*.tmp "$BIN/runtime"/*.tmp "$BIN/runtime/.bun.tgz" 2>/dev/null || true
}
trap cleanup EXIT

fetch() { curl -fsSL --connect-timeout 10 --retry 2 --retry-delay 1 -o "$2" "$1"; }

# ── 3. latest.json ───────────────────────────────────────────────────────────
fetch "$BASE/latest.json" "$TMP/latest.json" || die "下载 $BASE/latest.json 失败。检查网络；国内或内网用户可设 DOWNLOAD_BASE 指向镜像"
# latest.json 由 scripts/latest.ts 生成，一键一行；用 awk 取值，这台机器可能还没有任何运行时
jget() { awk -v k="\"$1\":" '$1==k {gsub(/^"|",?$/,"",$2); print $2; exit}' "$TMP/latest.json"; }
jpkg() { awk -v p="\"$1\":" -v f="\"$2\":" '$1==p {in1=1; next} in1 && $1==f {gsub(/^"|",?$/,"",$2); print $2; exit} in1 && /^ *}/ {exit}' "$TMP/latest.json"; }
jregs() { awk '$1=="\"registries\":" {r=1; next} r && /\]/ {exit} r {gsub(/^ *"|",?$/,""); print}' "$TMP/latest.json"; }

if [ -n "${AJ_VERSION:-}" ]; then
  VERSION=$AJ_VERSION
  SCRIPT_PATH=v$VERSION/autojourney.mjs
else
  VERSION=$(jget version)
  SCRIPT_PATH=$(jget script)
fi
[ -n "$VERSION" ] && [ -n "$SCRIPT_PATH" ] || die "$BASE/latest.json 内容不对（没有 version / files.script）"

# ── 4. 运行时：node ≥ 20 或 bun ≥ 1.4；都没有就下私有 Bun（规则与 shim 一致） ──
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
  [ -n "$BUNV" ] && [ -n "$NAME" ] && [ -n "$INTEG" ] || die "latest.json 里没有 $plat 的运行时信息"
  pkg=${NAME#@oven/}
  if [ -n "${AJ_RUNTIME_REGISTRY:-}" ]; then regs=$(printf '%s' "$AJ_RUNTIME_REGISTRY" | tr ',' '\n'); else regs=$(jregs); fi
  [ -n "$regs" ] || die "latest.json 里没有 npm 源列表"
  mkdir -p "$BIN/runtime"
  tgz=$BIN/runtime/.bun.tgz
  got_one=''
  for r in $regs; do
    url="$r/$NAME/-/$pkg-$BUNV.tgz"
    say "· 下载运行时 Bun ${BUNV}（${plat}，25–40MB，只此一次）：$url"
    if curl -fL --connect-timeout 10 --retry 1 -# -o "$tgz" "$url" 2>&2; then
      got_one=1
      break
    fi
    say "  这个源不通，换下一个"
  done
  [ -n "$got_one" ] || die "所有 npm 源都下不到运行时。检查网络，或设 AJ_RUNTIME_REGISTRY 指向能访问的 npm 镜像"
  got="sha512-$(openssl dgst -sha512 -binary "$tgz" | base64)"
  if [ "$got" != "$INTEG" ]; then
    rm -f "$tgz"
    die "运行时校验失败（sha512 与 latest.json 不一致），已删除下载的文件。请重试；反复出现请换一个 npm 源"
  fi
  tar -xzf "$tgz" -C "$TMP" package/bin/bun || die "解包运行时失败"
  mv "$TMP/package/bin/bun" "$BIN/runtime/bun.tmp"
  chmod +x "$BIN/runtime/bun.tmp"
  xattr -d com.apple.quarantine "$BIN/runtime/bun.tmp" 2>/dev/null || true
  bun_ok "$BIN/runtime/bun.tmp" || die "下载的运行时跑不起来（$("$BIN/runtime/bun.tmp" --version 2>&1 | head -1)）"
  mv -f "$BIN/runtime/bun.tmp" "$BIN/runtime/bun"
  rm -f "$tgz"
}

RUNTIME=''
KIND=''
if [ "${AJ_RUNTIME:-}" != private ]; then
  n=$(command -v node 2>/dev/null || true)
  if [ -n "$n" ] && node_ok "$n"; then
    RUNTIME=$n
    KIND=node
  else
    b=$(command -v bun 2>/dev/null || true)
    if [ -n "$b" ] && bun_ok "$b"; then
      RUNTIME=$b
      KIND=bun
    fi
  fi
fi
if [ -z "$RUNTIME" ]; then
  if [ -x "$BIN/runtime/bun" ] && bun_ok "$BIN/runtime/bun"; then
    say "· 用已有的私有运行时 $BIN/runtime/bun"
  else
    say "· 没找到 node ≥ 20 或 bun ≥ 1.4，改用私有运行时"
    download_bun
  fi
  RUNTIME=$BIN/runtime/bun
  KIND=bun
  export AJ_FORM=private
fi

# ── 5. 本体：先拿 checksums，已装且一致就不重下 ────────────────────────────────
fetch "$BASE/v$VERSION/checksums.txt" "$TMP/checksums.txt" || die "下载 $BASE/v$VERSION/checksums.txt 失败（这个版本可能不存在）"
want=$(awk '$2=="autojourney.mjs" {print $1; exit}' "$TMP/checksums.txt")
[ -n "$want" ] || die "checksums.txt 里没有 autojourney.mjs 的校验值"
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
if [ -f "$BIN/autojourney.mjs" ] && [ "$(sha256 "$BIN/autojourney.mjs")" = "$want" ]; then
  say "· AutoJourney $VERSION 已是最新，本体不用重下"
else
  say "· 下载 AutoJourney $VERSION"
  fetch "$BASE/$SCRIPT_PATH" "$BIN/autojourney.mjs.tmp" || die "下载 $BASE/$SCRIPT_PATH 失败"
  got=$(sha256 "$BIN/autojourney.mjs.tmp")
  [ "$got" = "$want" ] || die "本体校验失败（sha256 与 checksums.txt 不一致），已删除下载的文件；已装的版本没有动。请重试"
  mv -f "$BIN/autojourney.mjs.tmp" "$BIN/autojourney.mjs" # 提交点：正在跑的 daemon 持有旧 inode 不受影响
fi
xattr -d com.apple.quarantine "$BIN/autojourney.mjs" 2>/dev/null || true

# ── 6. 登记：写 shim 与 runtime.env 的逻辑只在程序里（shim.ts），这里不重复写 ────
export AJ_HOME
if [ -n "${AJ_NO_LINK:-}" ]; then
  "$RUNTIME" "$BIN/autojourney.mjs" link --shim-only < /dev/null > "$TMP/link.json" 2> "$TMP/link.err" || die "写 shim 失败：$(cat "$TMP/link.err" "$TMP/link.json" 2>/dev/null | tail -3)"
else
  "$RUNTIME" "$BIN/autojourney.mjs" link < /dev/null > "$TMP/link.json" 2> "$TMP/link.err" || die "登记客户端失败：$(cat "$TMP/link.err" "$TMP/link.json" 2>/dev/null | tail -3)"
fi

# ── 7. 核对版本，打印下一步 ────────────────────────────────────────────────────
"$BIN/autojourney" --version < /dev/null 2>/dev/null | grep -q "\"version\": \"$VERSION\"" || die "装完了但 $BIN/autojourney --version 对不上 ${VERSION}，请重跑：$INSTALL_CMD"
rt=$("$RUNTIME" --version 2>/dev/null | head -1)
say ""
say "✓ AutoJourney $VERSION 已装到 ${AJ_HOME}（运行时：$KIND $rt${AJ_FORM:+，私有}）"
if [ -z "${AJ_NO_LINK:-}" ]; then
  # 用刚装好的运行时把 link 的 JSON 排成人话；node 与 bun 的 -e 都能跑这段 CommonJS
  "$RUNTIME" -e '
const r = JSON.parse(require("fs").readFileSync(0, "utf8"));
const done = (r.clients || []).filter((c) => c.detected);
if (done.length) console.error("已登记：" + done.map((c) => c.label.split("（")[0]).join("、") + "。" + r.message);
else console.error(r.message + "\n\n" + r.manual);
' < "$TMP/link.json" || true
  say "重启前也能用：让 AI 助手执行 $BIN/autojourney targets"
fi
say "下一步：在浏览器里打开要用的平台页面，在插件设置里打开「Agent 模式」"
