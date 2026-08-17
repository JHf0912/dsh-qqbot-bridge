#!/usr/bin/env bash
# dev-start.sh — Linux/macOS 启动脚本（dev-start.ps1 的 bash 等价实现）
#
# 用法：
#   ./scripts/dev-start.sh [--profile 名称] [--skip-install] [--build-only] [--setup-only]
#
# 脚本会完成：
#   0. 环境检查：缺 pnpm 时自动执行 corepack enable；缺 DSH CLI 时自动安装
#      @deepseek-ai/dsh 到 $DSH_HOME/profiles；缺 DEEPSEEK_API_KEY 时
#      交互式提示输入并写入 $DSH_HOME/.env；启动前校验 QQ 凭据；
#   1. 安装依赖并构建 TypeScript；
#   2. 创建或更新 profile；
#   3. 将 profile 链接到当前源码，后续重新构建即可测试最新代码；
#   4. 最后一步才启动 DSH（--setup-only 只做准备不启动）。
set -euo pipefail

echo "[dev-start] 开始：自动环境检查 → 安装 → 构建 → 最后启动 DSH"

PROFILE="qqbot-safe-dev"
SKIP_INSTALL=0
BUILD_ONLY=0
SETUP_ONLY=0

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
    --setup-only)
      SETUP_ONLY=1
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
# WSL 注意：互操作可能把 Windows 版 node.exe 暴露进 PATH，必须排除，
# 否则后续用 Windows node 跑 Linux 路径会崩溃（桌面弹 Windows 报错框）
NODE_BIN="$(command -v node 2>/dev/null || true)"
if [[ -z "$NODE_BIN" ]]; then
  echo "错误：未找到 node，请先安装 Node.js >= 22（https://nodejs.org）" >&2
  exit 1
fi
if [[ "$NODE_BIN" == /mnt/* ]]; then
  echo "错误：检测到 Windows 版 node（$NODE_BIN），脚本不会使用它。" >&2
  echo "请在 WSL 内安装 Linux 版 node，例如：" >&2
  echo "  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash" >&2
  echo "  source ~/.bashrc && nvm install 22" >&2
  echo "或: sudo apt update && sudo apt install -y nodejs npm" >&2
  exit 1
fi

# 版本提示（不强制）：项目 engines 要求 node >= 22
node_version="$(node -v 2>/dev/null | sed 's/^v//')"
node_major="${node_version%%.*}"
if [[ "$node_major" =~ ^[0-9]+$ ]] && [[ "$node_major" -lt 22 ]]; then
  echo "警告：当前 node 为 v$node_version，项目要求 >= 22，构建或 DSH 运行可能失败。" >&2
  echo "建议: nvm install 22 && nvm alias default 22" >&2
fi

# 检查 pnpm：缺失时用 corepack（Node 自带）生成 shim；
# dsh 内部会直接 spawn "pnpm"，必须保证 pnpm 真实存在于 PATH
ensure_pnpm() {
  local pnpm_bin corepack_bin
  pnpm_bin="$(command -v pnpm 2>/dev/null || true)"
  if [[ -n "$pnpm_bin" && "$pnpm_bin" != /mnt/* ]]; then
    return 0
  fi
  corepack_bin="$(command -v corepack 2>/dev/null || true)"
  if [[ -n "$corepack_bin" && "$corepack_bin" != /mnt/* ]]; then
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

# 检查/校验 QQ 机器人凭据：缺失时引导录入，存在时调用 QQ 平台接口预校验，
# 避免 DSH 启动后才因 invalid appid or secret 失败
ensure_qq_creds() {
  local env_file="$DSH_HOME/.env"
  local appid="" secret=""
  if [[ -f "$env_file" ]]; then
    appid="$(grep -E '^QQBOT_APPID=' "$env_file" | head -n 1 | cut -d= -f2- | tr -d '"')"
    secret="$(grep -E '^QQBOT_SECRET=' "$env_file" | head -n 1 | cut -d= -f2- | tr -d '"')"
  fi

  if [[ -z "$appid" || -z "$secret" ]]; then
    echo "未检测到 QQ 机器人凭据（QQBOT_APPID / QQBOT_SECRET）。"
    echo "第一次启动 DSH 时会显示腾讯官方二维码，扫码后自动写入凭据。"
    echo "也可现在手动配置："
    echo "  1) 手动粘贴 AppID / AppSecret"
    echo "  2) 先启动一次扫码绑定（扫码后需 Ctrl+C 停止并重新运行本脚本）"
    echo "  3) 跳过（留到启动时处理）"
    read -rp "选择 [1/2/3]: " choice
    case "$choice" in
      1)
        read -rp "AppID: " appid
        read -rsp "AppSecret: " secret; echo
        mkdir -p "$DSH_HOME"
        echo "QQBOT_APPID=\"$appid\"" >> "$env_file"
        echo "QQBOT_SECRET=\"$secret\"" >> "$env_file"
        ;;
      *) return 0 ;;  # 2、3 都直接进入启动
    esac
  fi

  echo "校验 QQ 凭据（AppID $appid）..."
  local resp
  if ! resp="$(curl -fsS -m 15 -H 'Content-Type: application/json' \
      -d "{\"appId\":\"$appid\",\"clientSecret\":\"$secret\"}" \
      https://bots.qq.com/app/getAppAccessToken 2>/dev/null)"; then
    echo "警告：无法连接 QQ 平台校验凭据（网络问题），继续启动。" >&2
    return 0
  fi

  if echo "$resp" | grep -q '"access_token"'; then
    echo "QQ 凭据有效 ✅"
  else
    local code
    code="$(echo "$resp" | grep -o '"code":[0-9]*' | head -n 1 | cut -d: -f2)"
    echo "❌ QQ 凭据无效（code=${code:-未知}）。请到 q.qq.com 打开 AppID $appid，" >&2
    echo "   在「开发设置」查看并粘贴当前的 AppSecret 后重试。" >&2
    echo "   更新: sed -i 's/^QQBOT_SECRET=.*/QQBOT_SECRET=\"<新Secret>\"/' $env_file" >&2
    exit 1
  fi
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

if [[ "$SETUP_ONLY" -eq 1 ]]; then
  echo "所有前置准备已完成（未启动 DSH）。"
  echo "启动请运行: $0 --profile $PROFILE"
  exit 0
fi

ensure_qq_creds

echo "启动 DSH profile: $PROFILE"
exec node "$DSH_BIN" --profile "$PROFILE"
