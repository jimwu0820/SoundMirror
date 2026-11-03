# Setup-Scrcpy.ps1
# 下载并解压 scrcpy for Windows 到本目录，使 SoundMirror 可以直接运行。
# 用法：右键本文件 -> 使用 PowerShell 运行；或在终端执行 .\Setup-Scrcpy.ps1

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

$version = 'v5.0.1'
$name    = "scrcpy-win64-$version"
$dest    = Join-Path $PSScriptRoot 'scrcpy'
$target  = Join-Path $dest $name
$exe     = Join-Path $target 'scrcpy.exe'

if (Test-Path $exe) {
    Write-Host "scrcpy 已就绪：$target" -ForegroundColor Green
    Write-Host "无需重复下载。"
    exit 0
}

$base    = "https://github.com/Genymobile/scrcpy/releases/download/$version"
$mirrors = @(
    "https://ghfast.top/$base",
    "https://gh-proxy.com/$base",
    $base
)

New-Item -ItemType Directory -Force -Path $dest | Out-Null
$zip = Join-Path $env:TEMP "$name.zip"

Write-Host "目标版本：$name"
Write-Host "下载中，约 40 MB，请稍候..."

$downloaded = $false
foreach ($m in $mirrors) {
    try {
        Write-Host "  尝试 $m"
        Invoke-WebRequest -Uri "$m/$name.zip" -OutFile $zip -UseBasicParsing -TimeoutSec 300
        $downloaded = $true
        break
    } catch {
        Write-Host "  该镜像失败，换下一个" -ForegroundColor DarkYellow
    }
}

if (-not $downloaded) {
    Write-Host ""
    Write-Host "所有下载镜像都失败。请手动下载后解压：" -ForegroundColor Red
    Write-Host "  $base/$name.zip"
    Write-Host "  解压到：$dest"
    exit 1
}

# 与官方 SHA256SUMS.txt 比对，确认文件完整
try {
    $sums = (Invoke-WebRequest -Uri "$base/SHA256SUMS.txt" -UseBasicParsing -TimeoutSec 60).Content
    $line = ($sums -split "`n" | Where-Object { $_ -match [regex]::Escape($name) }) -join ''
    if ($line) {
        $expect = ($line.Trim() -split '\s+')[0]
        $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash
        if ($expect -and ($actual -ne $expect)) {
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
            throw "哈希不匹配，文件可能不完整：期望 $expect，实际 $actual"
        }
        Write-Host "  哈希校验通过" -ForegroundColor Green
    }
} catch {
    Write-Host "  跳过哈希校验：$($_.Exception.Message)" -ForegroundColor DarkYellow
}

Write-Host "解压中..."
Expand-Archive -Path $zip -DestinationPath $dest -Force
Remove-Item $zip -Force -ErrorAction SilentlyContinue

if (Test-Path $exe) {
    Write-Host ""
    Write-Host "完成。现在可以双击 SoundMirror.bat 或 SoundMirror.exe 启动。" -ForegroundColor Green
} else {
    Write-Host "解压后未找到 scrcpy.exe，请检查目录：$dest" -ForegroundColor Red
    exit 1
}
