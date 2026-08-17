#!/usr/bin/env bash
# dev-start.sh — Linux/macOS 启动脚本（dev-start.ps1 的 bash 等价实现）
#
# 用法：
#   ./scripts/dev-start.sh [--profile 名称] [--skip-install] [--build-only]
#
# 脚本会完成：
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

if ! command -v node >/dev/null 2>&1; then
  echo "错误：未找到 node，请先安装 Node.js >= 22" >&2
  exit 1
fi

if ! command -v pnpm >/dev/null 2>&1; then
  echo "错误：未找到 pnpm，请先执行: sudo corepack enable" >&2
  exit 1
fi

if [[ ! -f "$DSH_BIN" ]]; then
  echo "错误：未找到 DSH CLI: $DSH_BIN" >&2
  echo "请先安装 DSH CLI 到 profiles 目录（脚本不会自动安装）：" >&2
  echo "  mkdir -p \"\$DSH_HOME/profiles\" && cd \"\$DSH_HOME/profiles\"" >&2
  echo "  echo '{\"name\":\"profiles\",\"private\":true,\"dependencies\":{\"@deepseek-ai/dsh\":\"0.1.0-rc.6\"}}' > package.json" >&2
  echo "  pnpm install" >&2
  exit 1
fi

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
