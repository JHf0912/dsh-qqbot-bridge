#!/usr/bin/env bash
# dev-start.sh — Linux/macOS 启动脚本（dev-start.ps1 的 bash 等价实现）
#
# 用法：
#   ./scripts/dev-start.sh [--profile 名称] [--skip-install] [--build-only]
#
# 脚本会完成：
#   0. 环境检查：node 缺失或低于 22 时自动安装 Node 22 LTS（固定 v22.23.2，
#      不过度追求新版）；缺 pnpm 时自动执行 corepack enable；
#      缺 DSH CLI 时自动安装 @deepseek-ai/dsh 到 $DSH_HOME/profiles；
#   1. 安装依赖并构建 TypeScript；
#   2. 创建或更新 profile；
#   3. 将 profile 链接到当前源码，后续重新构建即可测试最新代码；
#   4. 启动 DSH。
set -euo pipefail

PROFILE="qqbot-safe-dev"
SKIP_INSTALL=0
BUILD_ONLY=0

# Node 22 LTS 固定版本（https://nodejs.org/dist/latest-v22.x/ 的当前补丁版）
NODE_MAJOR="22"
NODE_VERSION="22.23.2"
NODE_URL_BASE="https://nodejs.org/dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-install)
      SKIP_INSTALL=1
      shift
      ;;
    --build-only)
      BUILD_ONLY=1
      shift
      ;;
    --profile | -p)
      PROFILE="$2"
      shift 2
      ;;
    --profile=* | -p=*)
      PROFILE="${1#*=}"
      shift
      ;;
    *)
      echo "错误：未知参数 $1" >&2
      echo "用法：$0 [--profile 名称] [--skip-install] [--build-only]" >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
DSH_BIN="$DSH_HOME/profiles/node_modules/@deepseek-ai/dsh/lib/bin.js"

# ── 环境检查与自动安装 ──

# 检查 DSH CLI：缺失时自动装到 $DSH_HOME/profiles
# （pnpm 11 默认拦截 build script，必须带 allowBuilds 的 workspace 文件，
#   否则 koffi/node-pty/esbuild 等原生依赖安装直接报 ERR_PNPM_IGNORED_BUILDS）
ensure_dsh() {
  if [[ -f "$DSH_BIN" ]]; then
    return 0
  fi

  echo "未找到 DSH CLI，自动安装 @deepseek-ai/dsh 到 $DSH_HOME/profiles ..."
  mkdir -p "$DSH_HOME/profiles"

  local pkg_json="$DSH_HOME/profiles/package.json"
  if [[ ! -f "$pkg_json" ]]; then
    echo '{"name":"profiles","private":true,"dependencies":{"@deepseek-ai/dsh":"0.1.0-rc.6"}}' > "$pkg_json"
  fi

  local ws_yaml="$DSH_HOME/profiles/pnpm-workspace.yaml"
  if [[ ! -f "$ws_yaml" ]]; then
    cat > "$ws_yaml" <<'EOF'
allowBuilds:
  '@deepseek-ai/dsh-subprocess-local': true
  '@google/genai': true
  koffi: true
  node-pty: true
  protobufjs: true
EOF
  fi

  (
    cd "$DSH_HOME/profiles"
    pnpm install
  )

  if [[ ! -f "$DSH_BIN" ]]; then
    echo "错误：DSH CLI 安装失败，请手动检查 $DSH_HOME/profiles 下的 pnpm install 输出" >&2
    exit 1
  fi
  echo "DSH CLI 已安装: $DSH_BIN"
}

# 检查 node：>= 22 直接用；缺失或过旧时下载官方预编译包装到 /usr/local
ensure_node() {
  if command -v node >/dev/null 2>&1; then
    local current major
    current="$(node -v | sed 's/^v//')"
    major="${current%%.*}"
    if [[ "$major" -ge "$NODE_MAJOR" ]]; then
      echo "node v$current 满足要求（>= $NODE_MAJOR）"
      return 0
    fi
    echo "node v$current 过旧（需要 >= $NODE_MAJOR），自动安装 Node v$NODE_VERSION ..."
  else
    echo "未找到 node，自动安装 Node v$NODE_VERSION ..."
  fi

  local os arch
  case "$(uname -s)" in
    Linux) os="linux" ;;
    Darwin) os="darwin" ;;
    *) echo "错误：不支持的系统 $(uname -s)" >&2; exit 1 ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) arch="x64" ;;
    aarch64 | arm64) arch="arm64" ;;
    *) echo "错误：不支持的架构 $(uname -m)" >&2; exit 1 ;;
  esac

  local tarball="node-v${NODE_VERSION}-${os}-${arch}.tar.xz"
  local url="${NODE_URL_BASE}/v${NODE_VERSION}/${tarball}"
  local dest="/usr/local"

  echo "下载 $url"
  if ! curl -fsSL "$url" -o "/tmp/$tarball"; then
    echo "错误：自动下载 Node 失败，请手动安装 Node.js >= 22：" >&2
    echo "  $url" >&2
    echo "  然后解压到 /usr/local 即可。" >&2
    exit 1
  fi

  if [[ -w "$dest" ]]; then
    tar -xJf "/tmp/$tarball" -C "$dest" --strip-components=1
  elif command -v sudo >/dev/null 2>&1; then
    sudo tar -xJf "/tmp/$tarball" -C "$dest" --strip-components=1
  else
    echo "错误：无法写入 $dest（没有 sudo），请手动安装：" >&2
    echo "  sudo tar -xJf /tmp/$tarball -C $dest --strip-components=1" >&2
    exit 1
  fi
  rm -f "/tmp/$tarball"
  hash -r 2>/dev/null || true
  export PATH="/usr/local/bin:$PATH"
  echo "Node v$NODE_VERSION 已安装到 $dest（bin 位于 /usr/local/bin）"
}

# 检查 pnpm：缺失时用 corepack（Node 自带）生成 shim
ensure_pnpm() {
  if command -v pnpm >/dev/null 2>&1; then
    return 0
  fi
  if command -v corepack >/dev/null 2>&1; then
    echo "未找到 pnpm，执行 corepack enable ..."
    corepack enable
    hash -r 2>/dev/null || true
    export PATH="/usr/local/bin:$PATH"
    if command -v pnpm >/dev/null 2>&1; then
      return 0
    fi
  fi
  echo "错误：未找到 pnpm。请手动执行: sudo corepack enable" >&2
  exit 1
}

ensure_node
ensure_pnpm
ensure_dsh

cd "$PROJECT_ROOT"

if [[ "$SKIP_INSTALL" -eq 0 ]]; then
  pnpm install --frozen-lockfile
fi

pnpm build

if [[ "$BUILD_ONLY" -eq 1 ]]; then
  exit 0
fi

node "$DSH_BIN" plugin --profile "$PROFILE" add "file:$PROJECT_ROOT"

PROFILE_ROOT="$DSH_HOME/profiles/$PROFILE"
(
  cd "$PROFILE_ROOT"
  pnpm link "$PROJECT_ROOT"
)

echo "启动 DSH profile: $PROFILE"
exec node "$DSH_BIN" --profile "$PROFILE"
