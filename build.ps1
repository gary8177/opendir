<#
  OpenDir 构建脚本（PowerShell 版，不需要 Node）
    读 settings.json → 生成 dist/theme.html、dist/index.html、dist/nginx.conf、dist/preview.html
  用法：
    powershell -ExecutionPolicy Bypass -File build.ps1
#>
param()

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script:warnings = @()

function Read-Text([string]$file) {
    return (Get-Content -LiteralPath (Join-Path $here $file) -Raw -Encoding UTF8)
}

function Write-Text([string]$file, [string]$text) {
    $full = Join-Path $here $file
    $parent = Split-Path -Parent $full
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    [IO.File]::WriteAllText($full, $text, $utf8)
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
        $script:warnings += ($label + ' 不是绝对路径（' + $v + '）：nginx 的 root/alias 需要绝对路径，Windows 请写成 D:/目录')
    }
    return $v
}

function Normalize-Prefix([string]$value, [string]$fallback) {
    $v = '' + $value
    $v = $v -replace '^/+', ''
    $v = $v -replace '/+$', ''
    if ([string]::IsNullOrWhiteSpace($v)) { return $fallback }
    return '/' + $v
}

$settingsName = 'settings.json'
if (-not [string]::IsNullOrWhiteSpace($env:OPENDIR_SETTINGS)) { $settingsName = $env:OPENDIR_SETTINGS }
$settingsPath = Join-Path $here $settingsName
if (-not (Test-Path $settingsPath)) {
    Write-Host '读不到 settings.json，请先运行初始化：' -ForegroundColor Yellow
    Write-Host '  powershell -ExecutionPolicy Bypass -File init.ps1'
    exit 1
}

$settings = Read-Text $settingsName | ConvertFrom-Json
$version = (Read-Text 'VERSION').Trim()
$tpl = Read-Text 'src/index.html'
$css = Read-Text 'src/style.css'
$js = Read-Text 'src/app.js'
$demo = Read-Text 'src/demo-catalog.json'
$nginxTpl = Read-Text 'nginx.conf.tpl'

$srv = $settings.server
$ui = $settings.ui

$root = To-PosixPath $srv.root '/srv/files' 'server.root'
$themePath = To-PosixPath $srv.themePath '/var/www/opendir' 'server.themePath'
$themeUrl = Normalize-Prefix $srv.themeUrl '_opendir'
$jsonPrefix = Normalize-Prefix $srv.jsonPrefix '_raw'
$jsonArg = '' + $srv.jsonArg
if ([string]::IsNullOrWhiteSpace($jsonArg)) { $jsonArg = 'raw' }
$listen = '' + $srv.listen
if ([string]::IsNullOrWhiteSpace($listen)) { $listen = '80' }
$serverName = '' + $srv.serverName
if ([string]::IsNullOrWhiteSpace($serverName)) { $serverName = '_' }

$refreshMs = [int]$ui.refreshMs
if ($refreshMs -lt 0) { $refreshMs = 0 }
$showHidden = $true
if ($ui.showHidden -eq $false) { $showHidden = $false }
$brand = '' + $ui.brand
if ([string]::IsNullOrWhiteSpace($brand)) { $brand = 'OpenDir' }
$rootLabel = '' + $ui.rootLabel
if ([string]::IsNullOrWhiteSpace($rootLabel)) { $rootLabel = '根目录' }

$injected = [ordered]@{
    version = $version
    refreshMs = $refreshMs
    jsonArg = $jsonArg
    apiBase = ('' + $ui.apiBase)
    showHidden = $showHidden
    brand = $brand
    rootLabel = $rootLabel
}
$configScript = 'window.OPENDIR_CONFIG = ' + ($injected | ConvertTo-Json -Compress -Depth 5) + ';'

function Expand-Assets([string]$text) {
    $out = $text.Replace('/*{{STYLE}}*/', $css)
    $out = $out.Replace('/*{{CONFIG}}*/', $configScript)
    $out = $out.Replace('/*{{SCRIPT}}*/', $js)
    return $out
}

# 部署版：去掉演示数据那行 script；<title> 用字面替换（避开正则里的 $ 含义）
$theme = (Expand-Assets $tpl).Replace('<script>/*{{DEMO}}*/</script>', '')
$theme = $theme.Replace('<title>文件列表</title>', ('<title>' + $brand + '</title>'))

# 预览版：内联演示数据
$preview = (Expand-Assets $tpl).Replace('/*{{DEMO}}*/', ('window.__DEMO_CATALOG__ = ' + $demo.Trim() + ';'))

# Docker 版：配置改成外部 config.js（容器启动时按环境变量生成）
$dockerHtml = $tpl.Replace('<script>/*{{CONFIG}}*/</script>', '<script src="__OPENDIR_CONFIG_JS__"></script>')
$dockerHtml = $dockerHtml.Replace('/*{{STYLE}}*/', $css)
$dockerHtml = $dockerHtml.Replace('/*{{SCRIPT}}*/', $js)
$dockerHtml = $dockerHtml.Replace('<script>/*{{DEMO}}*/</script>', '')
$dockerHtml = $dockerHtml.Replace('<title>文件列表</title>', ('<title>' + $brand + '</title>'))

$nginxConf = $nginxTpl.Replace('{{VERSION}}', $version)
$nginxConf = $nginxConf.Replace('{{LISTEN}}', $listen)
$nginxConf = $nginxConf.Replace('{{SERVER_NAME}}', $serverName)
$nginxConf = $nginxConf.Replace('{{ROOT}}', $root)
$nginxConf = $nginxConf.Replace('{{THEME_PATH}}', $themePath)
$nginxConf = $nginxConf.Replace('{{THEME_URL}}', $themeUrl)
$nginxConf = $nginxConf.Replace('{{JSON_PREFIX}}', $jsonPrefix)
$nginxConf = $nginxConf.Replace('{{JSON_ARG}}', $jsonArg)

Write-Text 'dist/theme.html' $theme
Copy-Item -LiteralPath (Join-Path $here 'dist/theme.html') -Destination (Join-Path $here 'dist/index.html') -Force

$emitNginx = $true
if ($settings.build.emitNginxConf -eq $false) { $emitNginx = $false }
$emitPreview = $true
if ($settings.build.emitPreview -eq $false) { $emitPreview = $false }

if ($emitNginx) {
    Write-Text 'dist/nginx.conf' $nginxConf
    # 便携 nginx 存在的话顺带同步一份（opendir.conf 自动同步）
    $portableConf = Join-Path $here 'tools/nginx/conf/opendir.conf'
    if (Test-Path $portableConf) {
        Copy-Item -LiteralPath (Join-Path $here 'dist/nginx.conf') -Destination $portableConf -Force
        Write-Host '已同步 → tools/nginx/conf/opendir.conf'
    }
}
if ($emitPreview) { Write-Text 'dist/preview.html' $preview }

$emitDocker = $true
if ($settings.build.emitDocker -eq $false) { $emitDocker = $false }
if ($emitDocker) {
    Write-Text 'dist/docker/index.html' $dockerHtml
    Write-Text 'dist/docker/config.js' $configScript
}

function Size-Kb([string]$file) {
    $len = (Get-Item (Join-Path $here $file)).Length
    return [string]::Format('{0:N1} KiB', ($len / 1KB))
}

foreach ($w in $script:warnings) {
    Write-Host ('⚠ ' + $w) -ForegroundColor Yellow
}

Write-Host ('OpenDir v' + $version)
Write-Host ('  root      ' + $root)
Write-Host ('  theme     ' + $themePath + '/index.html   (URL ' + $themeUrl + '/)')
Write-Host ('  json      ' + $jsonPrefix + '/   ?' + $jsonArg + '=1')
if ($refreshMs -gt 0) {
    Write-Host ('  refresh   ' + [string]([int]($refreshMs / 1000)) + ' 秒')
} else {
    Write-Host '  refresh   关闭'
}
Write-Host ('dist/theme.html   ' + (Size-Kb 'dist/theme.html'))
Write-Host ('dist/index.html   ' + (Size-Kb 'dist/index.html'))
if ($emitNginx) { Write-Host ('dist/nginx.conf   ' + (Size-Kb 'dist/nginx.conf')) }
if ($emitPreview) { Write-Host ('dist/preview.html ' + (Size-Kb 'dist/preview.html')) }
if ($emitDocker) { Write-Host 'dist/docker/      index.html + config.js' }
