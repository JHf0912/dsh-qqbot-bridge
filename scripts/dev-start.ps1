param(
  [string]$Profile = 'qqbot-safe-dev',
  [switch]$SkipInstall,
  [switch]$BuildOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$dshBin = Join-Path $dshHome 'profiles\node_modules\@deepseek-ai\dsh\lib\bin.js'

if (-not (Test-Path -LiteralPath $dshBin)) {
  throw "未找到 DSH CLI: $dshBin"
}
if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
  throw '未找到 pnpm，请先执行: corepack enable'
}

Push-Location $projectRoot
try {
  if (-not $SkipInstall) {
    & pnpm install --frozen-lockfile
    if ($LASTEXITCODE -ne 0) { throw '依赖安装失败' }
  }
  & pnpm build
  if ($LASTEXITCODE -ne 0) { throw '构建失败' }

  if ($BuildOnly) { exit 0 }

  & node $dshBin plugin --profile $Profile add "file:$projectRoot"
  if ($LASTEXITCODE -ne 0) { throw '安装本地插件失败' }

  $profileRoot = Join-Path $dshHome "profiles\$Profile"
  if (-not (Test-Path -LiteralPath $profileRoot)) {
    throw "profile 目录不存在: $profileRoot（请检查 dsh plugin add 输出）"
  }
  Push-Location $profileRoot
  try {
    & pnpm link $projectRoot
    if ($LASTEXITCODE -ne 0) { throw '链接插件失败' }
  } finally {
    Pop-Location
  }

  Write-Host "启动 DSH profile: $Profile"
  & node $dshBin --profile $Profile
} finally {
  Pop-Location
}
