<#
  初始化设置：把「文件目录 / 站点信息 / 页面偏好」写进 settings.json 并持久化保存，
  之后再跑 init.ps1 会以现有配置作为默认值（不会丢设置）。

  用法：
    powershell -ExecutionPolicy Bypass -File init.ps1
    powershell -ExecutionPolicy Bypass -File init.ps1 -AcceptDefaults   # 全部取默认值，不交互
#>
param([switch]$AcceptDefaults)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$utf8 = New-Object System.Text.UTF8Encoding($false)
$settingsPath = Join-Path $here 'settings.json'

# ---- 默认值 ----
$cfg = [ordered]@{
    listen         = '80'
    serverName     = 'pan.example.com'
    root           = '/srv/files'
    themePath      = '/var/www/opendir'
    themeUrl       = '/_opendir'
    jsonPrefix     = '/_raw'
    jsonArg        = 'raw'
    refreshSeconds = 120
    showHidden     = $true
    brand          = '文件站'
    rootLabel      = '根目录'
    apiBase        = ''
}

# ---- 已初始化过 → 用现有 settings.json 当默认值（设置持久化）----
if (Test-Path $settingsPath) {
    $old = (Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8) | ConvertFrom-Json
    if ($old.server) {
        foreach ($key in @('listen', 'serverName', 'root', 'themePath', 'themeUrl', 'jsonPrefix', 'jsonArg')) {
            $value = $old.server.$key
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) { $cfg[$key] = [string]$value }
        }
    }
    if ($old.ui) {
        if ($null -ne $old.ui.refreshMs) { $cfg.refreshSeconds = [int]([int]$old.ui.refreshMs / 1000) }
        if ($null -ne $old.ui.showHidden) { $cfg.showHidden = [bool]$old.ui.showHidden }
        if (-not [string]::IsNullOrWhiteSpace([string]$old.ui.brand)) { $cfg.brand = [string]$old.ui.brand }
        if (-not [string]::IsNullOrWhiteSpace([string]$old.ui.rootLabel)) { $cfg.rootLabel = [string]$old.ui.rootLabel }
        if ($null -ne $old.ui.apiBase) { $cfg.apiBase = [string]$old.ui.apiBase }
    }
    Write-Host '检测到已有 settings.json，本次以现有配置作为默认值（直接回车即可保留）。' -ForegroundColor Cyan
}

function Ask([string]$label, [string]$current) {
    if ($AcceptDefaults) { return $current }
    $answerText = Read-Host ($label + ' [' + $current + ']')
    if ([string]::IsNullOrWhiteSpace($answerText)) { return $current }
    return $answerText.Trim()
}

function AskInt([string]$label, [int]$current, [int]$min, [int]$max) {
    while ($true) {
        $raw = Ask $label ([string]$current)
        $num = 0
        if ([int]::TryParse($raw, [ref]$num) -and $num -ge $min -and $num -le $max) { return $num }
        Write-Host ('  需要 ' + $min + ' ~ ' + $max + ' 之间的整数') -ForegroundColor Yellow
        if ($AcceptDefaults) { return $current }
    }
}

function AskBool([string]$label, [bool]$current) {
    $def = 'N'
    if ($current) { $def = 'Y' }
    if ($AcceptDefaults) { return $current }
    $raw = Read-Host ($label + ' [Y/N，默认 ' + $def + ']')
    if ([string]::IsNullOrWhiteSpace($raw)) { return $current }
    return (@('y', 'yes', '1', '是', 'true') -contains $raw.Trim().ToLower())
}

# 统一成 nginx 能吃的路径：反斜杠换正斜杠、去尾斜杠、检查是否绝对路径
# （nginx 里 D:\Downloads 会被当成转义序列，必须写 D:/Downloads）
function To-PosixPath([string]$value, [string]$fallback, [string]$label) {
    $v = '' + $value
    if ([string]::IsNullOrWhiteSpace($v)) { $v = $fallback }
    $v = $v.Replace('\', '/')
    if (-not $v.StartsWith('//')) {
        while ($v.Contains('//')) { $v = $v.Replace('//', '/') }
    }
    $v = $v.TrimEnd('/')
    if ($v -eq '') { $v = '/' }
    $isAbs = $v.StartsWith('/') -or ($v -match '^[A-Za-z]:/')
    if (-not $isAbs) {
        Write-Host ('  ⚠ ' + $label + ' 不是绝对路径（' + $v + '）：nginx 的 root/alias 需要绝对路径，Windows 请写成 D:/目录') -ForegroundColor Yellow
    }
    return $v
}

Write-Host ''
Write-Host '== OpenDir 初始化 ==' -ForegroundColor Cyan
Write-Host '（方括号里是默认值，直接回车表示保留）'
Write-Host ''
Write-Host '-- 文件目录 --' -ForegroundColor Cyan
$cfg.root = To-PosixPath (Ask '文件根目录（服务器上真实目录）' $cfg.root) '/srv/files' '文件根目录'
$cfg.themePath = To-PosixPath (Ask '主题安装目录（放 index.html，建议在文件根目录之外）' $cfg.themePath) '/var/www/opendir' '主题安装目录'
$cfg.themeUrl = Ask '主题 URL 前缀' $cfg.themeUrl
Write-Host ''
Write-Host '-- 站点 --' -ForegroundColor Cyan
$cfg.serverName = Ask '站点域名（server_name）' $cfg.serverName
$cfg.listen = Ask '监听端口（listen）' $cfg.listen
$cfg.jsonPrefix = Ask '目录 JSON 的内部 URL 前缀' $cfg.jsonPrefix
$cfg.jsonArg = Ask '目录 JSON 的查询参数名（如 raw 表示 ?raw=1）' $cfg.jsonArg
Write-Host ''
Write-Host '-- 页面 --' -ForegroundColor Cyan
$cfg.brand = Ask '站点标题' $cfg.brand
$cfg.rootLabel = Ask '面包屑根节点文案' $cfg.rootLabel
$cfg.refreshSeconds = AskInt '自动刷新间隔（秒，0 = 关闭）' $cfg.refreshSeconds 0 3600
$cfg.showHidden = AskBool '默认显示 . 开头的隐藏文件' $cfg.showHidden
$cfg.apiBase = Ask '独立 JSON 端点（方案 B，留空表示同站）' $cfg.apiBase
Write-Host ''

$refreshMs = $cfg.refreshSeconds * 1000
if ($refreshMs -lt 0) { $refreshMs = 0 }

$settings = [ordered]@{
    version = 1
    server  = [ordered]@{
        listen     = $cfg.listen
        serverName = $cfg.serverName
        root       = $cfg.root.TrimEnd('/')
        themePath  = $cfg.themePath.TrimEnd('/')
        themeUrl   = $cfg.themeUrl
        jsonPrefix = $cfg.jsonPrefix
        jsonArg    = $cfg.jsonArg
    }
    ui      = [ordered]@{
        refreshMs  = $refreshMs
        showHidden = $cfg.showHidden
        brand      = $cfg.brand
        rootLabel  = $cfg.rootLabel
        apiBase    = $cfg.apiBase
    }
    build   = [ordered]@{
        emitNginxConf = $true
        emitPreview   = $true
    }
}

$json = ($settings | ConvertTo-Json -Depth 8) + [Environment]::NewLine
if (Test-Path $settingsPath) {
    $backup = Join-Path $here ('settings-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    Copy-Item -LiteralPath $settingsPath -Destination $backup -Force
    Write-Host ('已备份原配置：' + (Split-Path -Leaf $backup)) -ForegroundColor DarkGray
}
[IO.File]::WriteAllText($settingsPath, $json, $utf8)
Write-Host '已写入 settings.json：' -ForegroundColor Green
Write-Host ($json.TrimEnd())
Write-Host ''

$doBuild = $true
if (-not $AcceptDefaults) {
    $answer = Read-Host '现在构建吗？[Y/n]'
    if (-not [string]::IsNullOrWhiteSpace($answer) -and $answer.Trim().ToLower() -eq 'n') { $doBuild = $false }
}

if ($doBuild) {
    & (Join-Path $here 'build.ps1')
} else {
    Write-Host '稍后可以运行： powershell -ExecutionPolicy Bypass -File build.ps1' -ForegroundColor Cyan
}
