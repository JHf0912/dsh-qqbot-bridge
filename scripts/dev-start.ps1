param(
  [string]$Profile = 'qqbot-safe-dev',
  [switch]$SkipInstall,
  [switch]$BuildOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$dshBin = Join-Path $dshHome 'profiles\node_modules\@deepseek-ai\dsh\lib\bin.js'

# ── 解析 pnpm 调用方式：优先 pnpm，其次 corepack pnpm（Node 自带）──
$script:useCorepackPnpm = $false
if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
  if (Get-Command corepack -ErrorAction SilentlyContinue) {
    $script:useCorepackPnpm = $true
  } else {
    throw '未找到 pnpm 和 corepack，请先执行: corepack enable 或用 npm install -g pnpm'
  }
}

function Invoke-Pnpm {
  param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
  if ($script:useCorepackPnpm) {
    & corepack pnpm @Arguments
  } else {
    & pnpm @Arguments
  }
  if ($LASTEXITCODE -ne 0) {
    throw "pnpm $($Arguments -join ' ') 失败（exit $LASTEXITCODE）"
  }
}

if (-not (Test-Path -LiteralPath $dshBin)) {
  throw "未找到 DSH CLI: $dshBin"
}

# ── API Key 检查：进程环境或 $dshHome/.env 中缺失时交互式输入并落盘 ──
if (-not $env:DEEPSEEK_API_KEY) {
  $envFile = Join-Path $dshHome '.env'
  $existing = $null
  if (Test-Path -LiteralPath $envFile) {
    $line = Get-Content -LiteralPath $envFile |
      Where-Object { $_ -match '^DEEPSEEK_API_KEY=' } |
      Select-Object -First 1
    if ($line) {
      $existing = (($line -replace '^DEEPSEEK_API_KEY=', '') -replace '"', '')
    }
  }
  if ($existing) {
    Write-Host "已检测到 $envFile 中的 DEEPSEEK_API_KEY"
    $env:DEEPSEEK_API_KEY = $existing
  } else {
    Write-Host '未检测到 DEEPSEEK_API_KEY，请在下方粘贴你的 DeepSeek API Key（将写入 $dshHome\.env）：'
    $key = Read-Host 'DEEPSEEK_API_KEY'
    if ([string]::IsNullOrWhiteSpace($key)) { throw '未输入 API Key，无法继续' }
    New-Item -ItemType Directory -Force $dshHome | Out-Null
    Add-Content -LiteralPath $envFile "DEEPSEEK_API_KEY=`"$key`""
    $env:DEEPSEEK_API_KEY = $key
    Write-Host "已写入 $envFile（本次运行已生效）"
  }
} else {
  Write-Host '已检测到环境变量 DEEPSEEK_API_KEY'
}

Push-Location $projectRoot
try {
  if (-not $SkipInstall) {
    Invoke-Pnpm install --frozen-lockfile
  }
  Invoke-Pnpm build

  if ($BuildOnly) { exit 0 }

  & node $dshBin plugin --profile $Profile add "file:$projectRoot"
  if ($LASTEXITCODE -ne 0) { throw '安装本地插件失败' }

  $profileRoot = Join-Path $dshHome "profiles\$Profile"
  if (-not (Test-Path -LiteralPath $profileRoot)) {
    throw "profile 目录不存在: $profileRoot（请检查 dsh plugin add 输出）"
  }
  Push-Location $profileRoot
  try {
    Invoke-Pnpm link $projectRoot
  } finally {
    Pop-Location
  }

  Write-Host "启动 DSH profile: $Profile"
  & node $dshBin --profile $Profile
} finally {
  Pop-Location
}