<#
  OpenDir —— Docker 版初始化：交互生成 .env（compose 会自动读取）
    用法：
      .\init-docker.cmd
      powershell -ExecutionPolicy Bypass -File init-docker.ps1
      powershell -ExecutionPolicy Bypass -File init-docker.ps1 -AcceptDefaults

  说明：静态部署用 init.ps1 → settings.json；Docker 部署用本脚本 → .env。
        两者互不影响：镜像里不带 settings.json，所有设置都由环境变量注入。
#>
param([switch]$AcceptDefaults)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$utf8 = New-Object System.Text.UTF8Encoding($false)
$envPath = Join-Path $here '.env'

# ---- 默认值（与 docker-compose.yml 的缺省一致）----
$cfg = [ordered]@{
    HOST_DIR     = './files'
    ROOT         = '/srv/files'
    PORT_HOST    = '8080'
    LISTEN       = '80'
    SERVER_NAME  = '_'
    BRAND        = 'OpenDir'
    ROOT_LABEL   = '根目录'
    REFRESH_MS   = '120000'
    SHOW_HIDDEN  = 'true'
    THEME_URL    = '/_opendir'
    JSON_PREFIX  = '/_raw'
    JSON_ARG     = 'raw'
    API_BASE     = ''
    IMAGE        = 'opendir:1.0.0'
    CONTAINER    = 'opendir'
}

# ---- 已有 .env → 用现值当默认值（设置持久化）----
if (Test-Path $envPath) {
    Write-Host '检测到已有 .env，本次以现有值为默认值（直接回车即保留）。' -ForegroundColor Cyan
    foreach ($line in Get-Content -LiteralPath $envPath -Encoding UTF8) {
        $text = $line.Trim()
        if ($text -eq '' -or $text.StartsWith('#')) { continue }
        $idx = $text.IndexOf('=')
        if ($idx -lt 1) { continue }
        $key = $text.Substring(0, $idx).Trim()
        $value = $text.Substring($idx + 1).Trim()
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        switch ($key) {
            'OPENDIR_HOST_DIR'    { $cfg.HOST_DIR = $value }
            'OPENDIR_ROOT'        { $cfg.ROOT = $value }
            'OPENDIR_PORT_HOST'   { $cfg.PORT_HOST = $value }
            'OPENDIR_LISTEN'      { $cfg.LISTEN = $value }
            'OPENDIR_SERVER_NAME' { $cfg.SERVER_NAME = $value }
            'OPENDIR_BRAND'       { $cfg.BRAND = $value }
            'OPENDIR_ROOT_LABEL'  { $cfg.ROOT_LABEL = $value }
            'OPENDIR_REFRESH_MS'  { $cfg.REFRESH_MS = $value }
            'OPENDIR_SHOW_HIDDEN' { $cfg.SHOW_HIDDEN = $value }
            'OPENDIR_THEME_URL'   { $cfg.THEME_URL = $value }
            'OPENDIR_JSON_PREFIX' { $cfg.JSON_PREFIX = $value }
            'OPENDIR_JSON_ARG'    { $cfg.JSON_ARG = $value }
            'OPENDIR_API_BASE'    { $cfg.API_BASE = $value }
            'OPENDIR_IMAGE'       { $cfg.IMAGE = $value }
            'OPENDIR_CONTAINER'   { $cfg.CONTAINER = $value }
        }
    }
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
        if ([int]::TryParse($raw, [ref]$num) -and $num -ge $min -and $num -le $max) { return [string]$num }
        Write-Host ('  需要 ' + $min + ' ~ ' + $max + ' 之间的整数') -ForegroundColor Yellow
        if ($AcceptDefaults) { return [string]$current }
    }
}

function AskBool([string]$label, [string]$current) {
    $def = 'N'
    if ($current -eq 'true') { $def = 'Y' }
    if ($AcceptDefaults) { return $current }
    $raw = Read-Host ($label + ' [Y/N，默认 ' + $def + ']')
    if ([string]::IsNullOrWhiteSpace($raw)) { return $current }
    if (@('y', 'yes', '1', '是', 'true') -contains $raw.Trim().ToLower()) { return 'true' }
    return 'false'
}

Write-Host ''
Write-Host '== OpenDir Docker 初始化 ==' -ForegroundColor Cyan
Write-Host '（方括号里是默认值，直接回车表示保留）'
Write-Host ''
Write-Host '-- 文件目录 --' -ForegroundColor Cyan
$cfg.HOST_DIR = Ask '宿主机上放文件的目录（可写 D:/目录 这种）' $cfg.HOST_DIR
$cfg.ROOT = Ask '容器内对应路径' $cfg.ROOT
Write-Host ''
Write-Host '-- 端口 --' -ForegroundColor Cyan
$cfg.PORT_HOST = AskInt '宿主机端口' ([int]$cfg.PORT_HOST) 1 65535
$cfg.LISTEN = AskInt '容器内监听端口' ([int]$cfg.LISTEN) 1 65535
Write-Host ''
Write-Host '-- 站点 --' -ForegroundColor Cyan
$cfg.SERVER_NAME = Ask 'server_name（默认 _ 表示匹配所有域名）' $cfg.SERVER_NAME
$cfg.BRAND = Ask '站点标题' $cfg.BRAND
$cfg.ROOT_LABEL = Ask '面包屑根节点文案' $cfg.ROOT_LABEL
$seconds = [int]([int]$cfg.REFRESH_MS / 1000)
$seconds = [int](AskInt '自动刷新间隔（秒，0 = 关闭）' $seconds 0 3600)
$cfg.REFRESH_MS = [string]($seconds * 1000)
$cfg.SHOW_HIDDEN = AskBool '默认显示 . 开头的隐藏文件' $cfg.SHOW_HIDDEN
Write-Host ''
Write-Host '-- 高级（一般直接回车）--' -ForegroundColor Cyan
$cfg.THEME_URL = Ask '页面外壳 URL 前缀' $cfg.THEME_URL
$cfg.JSON_PREFIX = Ask '目录 JSON 内部前缀' $cfg.JSON_PREFIX
$cfg.JSON_ARG = Ask '目录 JSON 查询参数名' $cfg.JSON_ARG
$cfg.API_BASE = Ask '独立 JSON 端点（留空 = 同站）' $cfg.API_BASE
$cfg.IMAGE = Ask '镜像标签' $cfg.IMAGE
$cfg.CONTAINER = Ask '容器名' $cfg.CONTAINER
Write-Host ''

function Quote-Env([string]$value) {
    if ($value -match '[\s#"]') {
        return '"' + $value.Replace('"', '\"') + '"'
    }
    if ($value -eq '') { return '' }
    return $value
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# OpenDir —— Docker 版设置（由 init-docker.ps1 生成，compose 会自动读取）')
$lines.Add('# 宿主机上放文件的目录')
$lines.Add('OPENDIR_HOST_DIR=' + (Quote-Env $cfg.HOST_DIR))
$lines.Add('# 容器内对应路径')
$lines.Add('OPENDIR_ROOT=' + (Quote-Env $cfg.ROOT))
$lines.Add('# 端口：宿主机 : 容器')
$lines.Add('OPENDIR_PORT_HOST=' + $cfg.PORT_HOST)
$lines.Add('OPENDIR_LISTEN=' + $cfg.LISTEN)
$lines.Add('OPENDIR_SERVER_NAME=' + (Quote-Env $cfg.SERVER_NAME))
$lines.Add('# 页面')
$lines.Add('OPENDIR_BRAND=' + (Quote-Env $cfg.BRAND))
$lines.Add('OPENDIR_ROOT_LABEL=' + (Quote-Env $cfg.ROOT_LABEL))
$lines.Add('OPENDIR_REFRESH_MS=' + $cfg.REFRESH_MS)
$lines.Add('OPENDIR_SHOW_HIDDEN=' + $cfg.SHOW_HIDDEN)
$lines.Add('# 内部前缀')
$lines.Add('OPENDIR_THEME_URL=' + (Quote-Env $cfg.THEME_URL))
$lines.Add('OPENDIR_JSON_PREFIX=' + (Quote-Env $cfg.JSON_PREFIX))
$lines.Add('OPENDIR_JSON_ARG=' + (Quote-Env $cfg.JSON_ARG))
$lines.Add('OPENDIR_API_BASE=' + (Quote-Env $cfg.API_BASE))
$lines.Add('# 镜像')
$lines.Add('OPENDIR_IMAGE=' + (Quote-Env $cfg.IMAGE))
$lines.Add('OPENDIR_CONTAINER=' + (Quote-Env $cfg.CONTAINER))

$content = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
if (Test-Path $envPath) {
    $backup = Join-Path $here ('.env-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $envPath -Destination $backup -Force
    Write-Host ('已备份原 .env：' + (Split-Path -Leaf $backup)) -ForegroundColor DarkGray
}
[IO.File]::WriteAllText($envPath, $content, $utf8)
Write-Host '已写入 .env：' -ForegroundColor Green
Write-Host ($content.TrimEnd())
Write-Host ''

if (-not (Test-Path (Join-Path $here 'dist\docker\index.html'))) {
    Write-Host '提示：还没构建过页面，Docker 镜像需要 dist/docker/。先跑一次 .\build.cmd' -ForegroundColor Yellow
    Write-Host ''
}

Write-Host '接下来：' -ForegroundColor Cyan
Write-Host ('  docker compose up -d --build')
Write-Host ('  浏览器打开 http://127.0.0.1:' + $cfg.PORT_HOST + '/')
Write-Host ''

if (-not $AcceptDefaults) {
    $go = Read-Host '现在构建镜像并启动吗？[y/N]'
    if (-not [string]::IsNullOrWhiteSpace($go) -and $go.Trim().ToLower() -eq 'y') {
        Push-Location $here
        try {
            docker compose up -d --build
        } finally {
            Pop-Location
        }
    } else {
        Write-Host '稍后手动执行： docker compose up -d --build' -ForegroundColor DarkGray
    }
}
