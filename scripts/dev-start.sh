#!/usr/bin/env bash
# dev-start.sh — Linux/macOS 启动脚本（dev-start.ps1 的 bash 等价实现）
#
# 用法：
#   ./scripts/dev-start.sh [--profile 名称] [--skip-install] [--build-only]
#
# 脚本会完成：
#   0. 环境检查：缺 pnpm 时自动执行 corepack enable；缺 DSH CLI 时自动安装
#      @deepseek-ai/dsh 到 $DSH_HOME/profiles；缺 DEEPSEEK_API_KEY 时
#      交互式提示输入并写入 $DSH_HOME/.env；
#   1. 安装依赖并构建 TypeScript；
#   2. 创建或更新 profile；
#   3. 将 profile 链接到当前源码，后续重新构建即可测试最新代码；
#   4. 启动 DSH。
set -euo pipefail

PROFILE="qqbot-safe-dev"
SKIP_INSTALL=0
BUILD_ONLY=0

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

# 检查 node：只做存在性检查，不自动安装（版本须 >= 22，请自行安装）
if ! command -v node >/dev/null 2>&1; then
  echo "错误：未找到 node，请先安装 Node.js >= 22（https://nodejs.org）" >&2
  exit 1
fi

# 检查 pnpm：缺失时用 corepack（Node 自带）生成 shim；
# dsh 内部会直接 spawn "pnpm"，必须保证 pnpm 真实存在于 PATH
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
    # corepack enable 未生效时创建用户级垫片
    local shim_dir="$HOME/.local/bin"
    mkdir -p "$shim_dir"
    cat > "$shim_dir/pnpm" <<'EOF'
#!/usr/bin/env bash
exec corepack pnpm "$@"
EOF
    chmod +x "$shim_dir/pnpm" 2>/dev/null || true
    export PATH="$shim_dir:$PATH"
    hash -r 2>/dev/null || true
    if command -v pnpm >/dev/null 2>&1; then
      echo "已创建 pnpm 垫片: $shim_dir/pnpm"
      return 0
    fi
  fi
  echo "错误：未找到 pnpm。请手动执行: sudo corepack enable 或用 npm install -g pnpm" >&2
  exit 1
}

# 检查 API Key：进程环境或 $DSH_HOME/.env 中缺失时交互式输入并落盘
ensure_api_key() {
  local env_file="$DSH_HOME/.env"
  local existing=""

  if [[ -n "${DEEPSEEK_API_KEY:-}" ]]; then
    echo "已检测到环境变量 DEEPSEEK_API_KEY"
    return 0
  fi

  if [[ -f "$env_file" ]]; then
    existing="$(grep -E '^DEEPSEEK_API_KEY=' "$env_file" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d '"')"
  fi
  if [[ -n "$existing" ]]; then
    echo "已检测到 $env_file 中的 DEEPSEEK_API_KEY"
    export DEEPSEEK_API_KEY="$existing"
    return 0
  fi

  echo "未检测到 DEEPSEEK_API_KEY，请在下方粘贴你的 DeepSeek API Key（将写入 $env_file）："
  read -rp "DEEPSEEK_API_KEY=" key
  if [[ -z "${key:-}" ]]; then
    echo "错误：未输入 API Key，无法继续" >&2
    exit 1
  fi
  mkdir -p "$DSH_HOME"
  echo "DEEPSEEK_API_KEY=\"$key\"" >> "$env_file"
  chmod 600 "$env_file" 2>/dev/null || true
  export DEEPSEEK_API_KEY="$key"
  echo "已写入 $env_file（本次运行已生效）"
}

ensure_pnpm
ensure_dsh
ensure_api_key

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
