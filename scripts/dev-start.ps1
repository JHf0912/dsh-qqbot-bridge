param(
  [string]$Profile = 'qqbot-safe-dev',
  [switch]$SkipInstall,
  [switch]$BuildOnly,
  [switch]$SetupOnly
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

# ── 确保 pnpm 在 PATH 上：dsh 内部直接 spawn "pnpm"，不会走 corepack 兜底 ──
# 没有 pnpm 命令时创建一个指向 corepack pnpm 的用户级垫片并加入 PATH
function Ensure-PnpmShim {
  if (Get-Command pnpm -ErrorAction SilentlyContinue) { return }
  $shimDir = Join-Path $env:USERPROFILE '.local-bin'
  $shim = Join-Path $shimDir 'pnpm.cmd'
  if (-not (Test-Path -LiteralPath $shim)) {
    New-Item -ItemType Directory -Force $shimDir | Out-Null
    Set-Content -LiteralPath $shim -Encoding ascii "@echo off`r`ncorepack pnpm %*"
  }
  $env:PATH = "$shimDir;$env:PATH"
  if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
    throw '无法创建 pnpm。请执行: corepack enable 或用 npm install -g pnpm'
  }
}

Ensure-PnpmShim

# 检查 DSH CLI：缺失时自动装到 $dshHome\profiles
# （pnpm 11 默认拦截 build script，必须带 allowBuilds 的 workspace 文件，
#   否则 koffi/node-pty/esbuild 等原生依赖安装直接报 ERR_PNPM_IGNORED_BUILDS）
function Ensure-DshCli {
  if (Test-Path -LiteralPath $dshBin) { return }
  Write-Host "未找到 DSH CLI，自动安装 @deepseek-ai/dsh 到 $dshHome\profiles ..."
  $profilesDir = Join-Path $dshHome 'profiles'
  New-Item -ItemType Directory -Force $profilesDir | Out-Null
  $pkgJson = Join-Path $profilesDir 'package.json'
  if (-not (Test-Path -LiteralPath $pkgJson)) {
    Set-Content -LiteralPath $pkgJson -Encoding ascii '{"name":"profiles","private":true,"dependencies":{"@deepseek-ai/dsh":"0.1.0-rc.6"}}'
  }
  $wsYaml = Join-Path $profilesDir 'pnpm-workspace.yaml'
  if (-not (Test-Path -LiteralPath $wsYaml)) {
    Set-Content -LiteralPath $wsYaml -Encoding ascii @'
allowBuilds:
  '@deepseek-ai/dsh-subprocess-local': true
  '@google/genai': true
  koffi: true
  node-pty: true
  protobufjs: true
'@
  }
  Push-Location $profilesDir
  try { Invoke-Pnpm install } finally { Pop-Location }
  if (-not (Test-Path -LiteralPath $dshBin)) {
    throw "DSH CLI 安装失败，请手动检查 $profilesDir 下的 pnpm install 输出"
  }
  Write-Host "DSH CLI 已安装: $dshBin"
}

Ensure-DshCli

# 检查/校验 QQ 机器人凭据：缺失时引导录入，存在时调用 QQ 平台接口预校验，
# 避免 DSH 启动后才因 invalid appid or secret 失败
function Ensure-QqCreds {
  $envFile = Join-Path $dshHome '.env'
  $appId = $null
  $secret = $null
  if (Test-Path -LiteralPath $envFile) {
    $content = Get-Content -LiteralPath $envFile
    if ($line = $content | Where-Object { $_ -match '^QQBOT_APPID=' } | Select-Object -First 1) {
      $appId = (($line -replace '^QQBOT_APPID=', '') -replace '"', '').Trim()
    }
    if ($line = $content | Where-Object { $_ -match '^QQBOT_SECRET=' } | Select-Object -First 1) {
      $secret = (($line -replace '^QQBOT_SECRET=', '') -replace '"', '').Trim()
    }
  }

  if (-not $appId -or -not $secret) {
    Write-Host '未检测到 QQ 机器人凭据（QQBOT_APPID / QQBOT_SECRET）。'
    Write-Host '第一次启动 DSH 时会显示腾讯官方二维码，扫码后自动写入凭据。'
    Write-Host '  1) 手动粘贴 AppID / AppSecret'
    Write-Host '  2) 先启动一次扫码绑定（扫码后需 Ctrl+C 停止并重新运行本脚本）'
    Write-Host '  3) 跳过'
    switch (Read-Host '选择 [1/2/3]') {
      '1' {
        $appId = Read-Host 'AppID'
        $secret = Read-Host 'AppSecret'
        New-Item -ItemType Directory -Force $dshHome | Out-Null
        Add-Content -LiteralPath $envFile "QQBOT_APPID=`"$appId`""
        Add-Content -LiteralPath $envFile "QQBOT_SECRET=`"$secret`""
      }
      default { return }  # 2、3 都直接进入启动
    }
  }

  Write-Host "校验 QQ 凭据（AppID $appId）..."
  try {
    $body = @{ appId = $appId; clientSecret = $secret } | ConvertTo-Json
    $resp = Invoke-RestMethod -Uri 'https://bots.qq.com/app/getAppAccessToken' -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 15
  } catch {
    Write-Host '警告：无法连接 QQ 平台校验凭据（网络问题），继续启动。'
    return
  }
  if ($resp.access_token) {
    Write-Host 'QQ 凭据有效'
  } else {
    Write-Host "❌ QQ 凭据无效（code: $($resp.code)）。请到 q.qq.com 打开 AppID $appId，" -ForegroundColor Red
    Write-Host '   在「开发设置」查看并粘贴当前的 AppSecret 后重试。'
    throw 'QQ 凭据校验失败'
  }
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

  if ($SetupOnly) {
    Write-Host '所有前置准备已完成（未启动 DSH）。'
    Write-Host "启动请运行: $PSCommandPath --profile $Profile"
    exit 0
  }

  Ensure-QqCreds

  Write-Host "启动 DSH profile: $Profile"
  & node $dshBin --profile $Profile
} finally {
  Pop-Location
}