Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

try {
    $sig = @'
using System;
using System.Runtime.InteropServices;
public class NativeConsole {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern IntPtr LoadImage(IntPtr hinst, string name, uint type, int cx, int cy, uint fuLoad);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string AppID);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
'@
    Add-Type -TypeDefinition $sig -ErrorAction Stop
    $script:hasNative = $true
} catch { $script:hasNative = $false }

# 任务栏图标的关键：powershell.exe 在系统里注册了固定的 AppUserModelID
# (Microsoft.Windows.PowerShell)，任务栏会优先用那个 ID 对应的图标，从而忽略窗口自己的图标。
# 换成一个独立的 ID 后，任务栏就会回退到使用窗口图标。
if ($script:hasNative) {
    try { [void][NativeConsole]::SetCurrentProcessExplicitAppUserModelID('SoundMirror.App.1') } catch { }
}

$scriptDir = $PSScriptRoot
$scrcpyDir = Join-Path $scriptDir 'scrcpy\scrcpy-win64-v5.0.1'
$adbExe    = Join-Path $scrcpyDir 'adb.exe'
$scrcpyExe = Join-Path $scrcpyDir 'scrcpy.exe'
$logFile   = Join-Path $scriptDir 'scrcpy-log.txt'
$ipFile    = Join-Path $scriptDir 'last-ip.txt'

if (-not (Test-Path $scrcpyExe)) {
    [System.Windows.Forms.MessageBox]::Show("找不到 scrcpy.exe，请确认目录结构完整：`n$scrcpyDir", '错误') | Out-Null
    exit 1
}

$C = @{
    Primary     = '#185FA5'
    PrimaryDeep = '#0C447C'
    Surface     = '#FFFFFF'
    Page        = '#FAFAF8'
    SurfaceDim  = '#F1EFE8'
    Border      = '#D3D1C7'
    BorderDark  = '#B4B2A9'
    TextPrimary = '#2C2C2A'
    TextSecond  = '#5F5E5A'
    TextTert    = '#888780'
    Green       = '#1D9E75'
    Amber       = '#EF9F27'
    Red         = '#E24B4A'
    Gray        = '#888780'
    BlueSoft    = '#E6F1FB'
    ChipBg      = '#E1F5EE'
    ChipFg      = '#0F6E56'
}

function ToColor([string]$hex) { return [System.Drawing.ColorTranslator]::FromHtml($hex) }

$fBase  = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$fSmall = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5)
$fState = New-Object System.Drawing.Font('Microsoft YaHei UI', 12.5)
$fBtn   = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)

$savedIp = ''
if (Test-Path $ipFile) {
    $t = Get-Content -Path $ipFile -Raw -ErrorAction SilentlyContinue
    if ($t) { $t = $t.Trim(); if ($t) { $savedIp = $t } }
}

$script:proc = $null
$script:state = 'idle'
$script:mode = 'wifi'

$form = New-Object System.Windows.Forms.Form
$form.Text = 'SoundMirror'
$form.ClientSize = New-Object System.Drawing.Size(420, 318)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = ToColor $C.Page
$form.Font = $fBase

$icoPath = Join-Path $scriptDir 'app.ico'
if (Test-Path $icoPath) {
    try {
        $form.Icon = New-Object System.Drawing.Icon($icoPath, 32, 32)
    } catch {
        try { $form.Icon = New-Object System.Drawing.Icon($icoPath) } catch { }
    }
}
$form.ShowIcon = $true
$form.ShowInTaskbar = $true

# 再显式把大小图标都塞给窗口句柄，双保险：
# 有些系统上 WinForms 只会设置小图标，任务栏（用大图标）就会退回默认图标
function Set-WindowIcon($hWnd, [string]$path) {
    if (-not $script:hasNative -or $hWnd -eq [IntPtr]::Zero -or -not (Test-Path $path)) { return }
    $IMAGE_ICON = 1
    $LR_LOADFROMFILE = 0x10
    $WM_SETICON = 0x0080
    $ICON_SMALL = 0
    $ICON_BIG = 1
    try {
        foreach ($pair in @(@(16, $ICON_SMALL), @(32, $ICON_BIG), @(48, $ICON_BIG))) {
            $h = [NativeConsole]::LoadImage([IntPtr]::Zero, $path, $IMAGE_ICON, $pair[0], $pair[0], $LR_LOADFROMFILE)
            if ($h -ne [IntPtr]::Zero) {
                [void][NativeConsole]::SendMessage($hWnd, $WM_SETICON, [IntPtr]$pair[1], $h)
            }
        }
    } catch { }
}

function Get-RoundPath([single]$w, [single]$h, [single]$r) {
    $r = [Math]::Max(1, [Math]::Min($r, [Math]::Min($w, $h) / 2))
    $d = $r * 2
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc(0.5, 0.5, $d, $d, 180, 90)
    $p.AddArc($w - $d - 0.5, 0.5, $d, $d, 270, 90)
    $p.AddArc($w - $d - 0.5, $h - $d - 0.5, $d, $d, 0, 90)
    $p.AddArc(0.5, $h - $d - 0.5, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function Add-PillPaint {
    param(
        $Ctrl,
        [int]$Radius = 8,
        [string]$Fill = '#FFFFFF',
        [string]$TextColor = '#2C2C2A',
        [string]$Border = '',
        [string]$Display = '',
        [string]$HoverFill = ''
    )
    $Ctrl.Tag = @{
        Radius = $Radius; Fill = $Fill; HoverFill = $HoverFill
        TextColor = $TextColor; Border = $Border; Text = $Display; Hot = $false
    }
    $Ctrl.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $st = $s.Tag
        $w = [single]$s.Width
        $h = [single]$s.Height
        $path = Get-RoundPath $w $h ([single]$st.Radius)

        $fillHex = $st.Fill
        if ($st.Hot -and $st.HoverFill) { $fillHex = $st.HoverFill }
        $brFill = New-Object System.Drawing.SolidBrush((ToColor $fillHex))
        $g.FillPath($brFill, $path)
        $brFill.Dispose()

        if ($st.Border) {
            $penB = New-Object System.Drawing.Pen((ToColor $st.Border), 1)
            $g.DrawPath($penB, $path)
            $penB.Dispose()
        }

        if ($st.Text) {
            $sf = New-Object System.Drawing.StringFormat
            $sf.Alignment = [System.Drawing.StringAlignment]::Center
            $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
            $sf.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
            $brTx = New-Object System.Drawing.SolidBrush((ToColor $st.TextColor))
            $rect = New-Object System.Drawing.RectangleF(0, 0, $w, $h)
            $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
            $g.DrawString($st.Text, $s.Font, $brTx, $rect, $sf)
            $brTx.Dispose()
            $sf.Dispose()
        }
        $path.Dispose()
    })
    $Ctrl.Add_MouseEnter({ param($s, $e) if ($s.Tag.HoverFill) { $s.Tag.Hot = $true; $s.Invalidate() } })
    $Ctrl.Add_MouseLeave({ param($s, $e) if ($s.Tag.Hot) { $s.Tag.Hot = $false; $s.Invalidate() } })
}

function New-PillButton {
    param(
        [string]$DisplayText, [int]$X, [int]$Y, [int]$W, [int]$H,
        [int]$Radius = 9, [string]$Fill = '#FFFFFF', [string]$TextColor = '#2C2C2A',
        [string]$Border = '', [int]$FontSize = 9, [string]$HoverFill = ''
    )
    $b = New-Object System.Windows.Forms.Button
    $b.Text = ''
    $b.AccessibleName = $DisplayText
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($W, $H)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = $form.BackColor
    $b.FlatAppearance.MouseDownBackColor = $form.BackColor
    $b.FlatAppearance.CheckedBackColor = $form.BackColor
    $b.BackColor = $form.BackColor
    $b.UseVisualStyleBackColor = $false
    $b.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', $FontSize)
    $b.Cursor = 'Hand'
    Add-PillPaint -Ctrl $b -Radius $Radius -Fill $Fill -TextColor $TextColor -Border $Border -Display $DisplayText -HoverFill $HoverFill
    return $b
}

function Set-Pill {
    param($Ctrl, [string]$Display, [string]$Fill, [string]$TextColor, [string]$Border = '')
    if ($Display) { $Ctrl.Tag.Text = $Display; $Ctrl.AccessibleName = $Display }
    if ($Fill) { $Ctrl.Tag.Fill = $Fill }
    if ($TextColor) { $Ctrl.Tag.TextColor = $TextColor }
    $Ctrl.Tag.Border = $Border
    $Ctrl.Invalidate()
}

$srcLabel = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$lblDot = New-Object System.Windows.Forms.Label
$lblDot.Text = [char]0x25CF
$lblDot.Location = New-Object System.Drawing.Point(19, 20)
$lblDot.Size = New-Object System.Drawing.Size(16, 24)
$lblDot.Font = $srcLabel
$lblDot.ForeColor = ToColor $C.Gray
$lblDot.BackColor = [System.Drawing.Color]::Transparent

$lblState = New-Object System.Windows.Forms.Label
$lblState.Text = '未连接'
$lblState.Location = New-Object System.Drawing.Point(38, 16)
$lblState.Size = New-Object System.Drawing.Size(176, 30)
$lblState.Font = $fState
$lblState.ForeColor = ToColor $C.TextPrimary
$lblState.BackColor = [System.Drawing.Color]::Transparent

$chip = New-Object System.Windows.Forms.Panel
$chip.Location = New-Object System.Drawing.Point(220, 21)
$chip.Size = New-Object System.Drawing.Size(56, 22)
$chip.BackColor = $form.BackColor
$chip.Font = $fSmall
Add-PillPaint -Ctrl $chip -Radius 11 -Fill $C.ChipBg -TextColor $C.ChipFg -Border '' -Display 'Wi-Fi'
$chip.Visible = $false

$btnLog = New-PillButton -DisplayText '日志' -X 338 -Y 18 -W 62 -H 27 -Radius 8 -Fill $C.Page -TextColor $C.TextSecond -FontSize 8.5 -HoverFill $C.SurfaceDim

$line = New-Object System.Windows.Forms.Label
$line.Location = New-Object System.Drawing.Point(20, 54)
$line.Size = New-Object System.Drawing.Size(380, 1)
$line.BackColor = ToColor $C.Border

$lblSection = New-Object System.Windows.Forms.Label
$lblSection.Text = '连接方式'
$lblSection.Location = New-Object System.Drawing.Point(20, 64)
$lblSection.Size = New-Object System.Drawing.Size(120, 18)
$lblSection.Font = $fSmall
$lblSection.ForeColor = ToColor $C.TextTert
$lblSection.BackColor = [System.Drawing.Color]::Transparent

$btnWifi = New-PillButton -DisplayText 'Wi-Fi' -X 20 -Y 86 -W 188 -H 34 -Radius 9 -Fill $C.Surface -TextColor $C.TextSecond -Border $C.Border -FontSize 9 -HoverFill $C.SurfaceDim
$btnUsb  = New-PillButton -DisplayText 'USB 数据线' -X 209 -Y 86 -W 188 -H 34 -Radius 9 -Fill $C.Surface -TextColor $C.TextSecond -Border $C.Border -FontSize 9 -HoverFill $C.SurfaceDim

$lblIp = New-Object System.Windows.Forms.Label
$lblIp.Text = '手机 IP'
$lblIp.Location = New-Object System.Drawing.Point(20, 130)
$lblIp.Size = New-Object System.Drawing.Size(220, 18)
$lblIp.Font = $fSmall
$lblIp.ForeColor = ToColor $C.TextTert
$lblIp.BackColor = [System.Drawing.Color]::Transparent

$pnlIp = New-Object System.Windows.Forms.Panel
$pnlIp.Location = New-Object System.Drawing.Point(20, 150)
$pnlIp.Size = New-Object System.Drawing.Size(377, 36)
$pnlIp.BackColor = $form.BackColor
Add-PillPaint -Ctrl $pnlIp -Radius 9 -Fill $C.Surface -TextColor $C.TextPrimary -Border $C.BorderDark -Display ''

$txtIp = New-Object System.Windows.Forms.TextBox
$txtIp.BorderStyle = 'None'
$txtIp.BackColor = ToColor $C.Surface
$txtIp.ForeColor = ToColor $C.TextPrimary
$txtIp.Location = New-Object System.Drawing.Point(12, 9)
$txtIp.Size = New-Object System.Drawing.Size(352, 20)
$txtIp.Text = $savedIp
$txtIp.Font = $fBase
$pnlIp.Controls.Add($txtIp)

$chkVideo = New-Object System.Windows.Forms.CheckBox
$chkVideo.Text = '同时显示手机画面'
$chkVideo.Location = New-Object System.Drawing.Point(20, 196)
$chkVideo.Size = New-Object System.Drawing.Size(186, 24)
$chkVideo.Font = $fBase
$chkVideo.ForeColor = ToColor $C.TextSecond
$chkVideo.BackColor = [System.Drawing.Color]::Transparent

# 手机熄屏但保持渲染：scrcpy 的 --turn-screen-off。
# 注意这和"让手机自然息屏"不是一回事：Android 息屏后合成器停止工作，
# 镜像会黑掉；scrcpy 的做法是关掉物理屏幕、保留渲染，所以画面照常传过来。
$chkScreenOff = New-Object System.Windows.Forms.CheckBox
$chkScreenOff.Text = '投屏时手机熄屏'
$chkScreenOff.Location = New-Object System.Drawing.Point(212, 196)
$chkScreenOff.Size = New-Object System.Drawing.Size(180, 24)
$chkScreenOff.Font = $fBase
$chkScreenOff.ForeColor = ToColor $C.TextSecond
$chkScreenOff.BackColor = [System.Drawing.Color]::Transparent

$btnMain = New-PillButton -DisplayText '开始转发' -X 20 -Y 228 -W 266 -H 42 -Radius 11 -Fill $C.Primary -TextColor '#FFFFFF' -Border '' -FontSize 10

# 运行时息屏：走 scrcpy 窗口的 MOD+o / MOD+Shift+o 快捷键。
# 不能用 adb 的 power 键 —— 那会让设备真正休眠，采集端拿不到新帧，镜像直接黑掉。
# scrcpy 的做法是只关显示面板、保留表面合成，所以画面照常传。
$btnScreen = New-PillButton -DisplayText '手机熄屏' -X 294 -Y 228 -W 103 -H 42 -Radius 11 -Fill $C.Surface -TextColor $C.PrimaryDeep -Border $C.BorderDark -FontSize 9.5 -HoverFill $C.SurfaceDim

$lblError = New-Object System.Windows.Forms.Label
$lblError.Text = ''
$lblError.Location = New-Object System.Drawing.Point(20, 274)
$lblError.Size = New-Object System.Drawing.Size(377, 18)
$lblError.Font = $fSmall
$lblError.ForeColor = ToColor $C.Red
$lblError.BackColor = [System.Drawing.Color]::Transparent
$lblError.Visible = $false

$lblOut = New-Object System.Windows.Forms.Label
$lblOut.Text = '声音输出：Windows 默认播放设备'
$lblOut.Location = New-Object System.Drawing.Point(20, 294)
$lblOut.Size = New-Object System.Drawing.Size(377, 18)
$lblOut.Font = $fSmall
$lblOut.ForeColor = ToColor $C.TextTert
$lblOut.BackColor = [System.Drawing.Color]::Transparent

$form.Controls.AddRange(@($lblDot, $lblState, $chip, $btnLog, $line, $lblSection, $btnWifi, $btnUsb, $lblIp, $pnlIp, $chkVideo, $chkScreenOff, $btnMain, $btnScreen, $lblError, $lblOut))

$logForm = New-Object System.Windows.Forms.Form
$logForm.Text = 'SoundMirror · Log'
$logForm.ClientSize = New-Object System.Drawing.Size(624, 372)
$logForm.StartPosition = 'CenterParent'
$logForm.MinimizeBox = $false
$logForm.MaximizeBox = $true
$logForm.BackColor = $form.BackColor
$logForm.Font = $fBase
$logForm.Owner = $form
if ($form.Icon) { $logForm.Icon = $form.Icon }

$pnlLog = New-Object System.Windows.Forms.Panel
$pnlLog.Location = New-Object System.Drawing.Point(12, 12)
$pnlLog.Size = New-Object System.Drawing.Size(600, 348)
$pnlLog.BackColor = $form.BackColor
Add-PillPaint -Ctrl $pnlLog -Radius 10 -Fill $C.Surface -TextColor $C.TextPrimary -Border $C.Border -Display ''
$logForm.Controls.Add($pnlLog)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.BorderStyle = 'None'
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.WordWrap = $false
$txtLog.BackColor = ToColor $C.Surface
$txtLog.ForeColor = ToColor $C.TextSecond
$txtLog.Location = New-Object System.Drawing.Point(12, 12)
$txtLog.Size = New-Object System.Drawing.Size(574, 324)
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$pnlLog.Controls.Add($txtLog)

$logForm.Add_FormClosing({
    param($s, $e)
    if ($e.CloseReason -eq 'UserClosing') { $e.Cancel = $true; $logForm.Hide() }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 700

function Add-Log([string]$msg) {
    if ($msg) { $txtLog.AppendText($msg + "`r`n") }
}

function Set-UiState([string]$State, [string]$Text) {
    $script:state = $State
    switch ($State) {
        'idle' {
            $lblDot.ForeColor = ToColor $C.Gray
            $lblState.Text = '未连接'
            Set-Pill $btnMain '开始转发' $C.Primary '#FFFFFF' ''
            $btnMain.Enabled = $true
            $chip.Visible = $false
        }
        'connecting' {
            $lblDot.ForeColor = ToColor $C.Amber
            $lblState.Text = '连接中'
            Set-Pill $btnMain '连接中…' $C.PrimaryDeep '#FFFFFF' ''
            $btnMain.Enabled = $false
            $chip.Visible = $false
        }
        'running' {
            $lblDot.ForeColor = ToColor $C.Green
            $lblState.Text = '正在转发'
            Set-Pill $btnMain '停止转发' $C.Red '#FFFFFF' ''
            $btnMain.Enabled = $true
            if ($script:mode -eq 'usb') { $chip.Tag.Text = 'USB' } else { $chip.Tag.Text = 'Wi-Fi' }
            $chip.Invalidate()
            $chip.Visible = $true
        }
        'error' {
            $lblDot.ForeColor = ToColor $C.Red
            $lblState.Text = '未连接'
            Set-Pill $btnMain '开始转发' $C.Primary '#FFFFFF' ''
            $btnMain.Enabled = $true
            $chip.Visible = $false
        }
    }
    if ($Text) { $lblState.Text = $Text }
}

function Set-Mode([string]$Mode) {
    $script:mode = $Mode
    $lblError.Visible = $false
    if ($Mode -eq 'usb') {
        Set-Pill $btnUsb 'USB 数据线' $C.BlueSoft $C.Primary ''
        Set-Pill $btnWifi 'Wi-Fi' $C.Surface $C.TextSecond $C.Border
        $txtIp.Enabled = $false
        $txtIp.BackColor = ToColor $C.SurfaceDim
        $txtIp.ForeColor = ToColor $C.TextTert
        $lblIp.ForeColor = ToColor $C.BorderDark
        $lblIp.Text = '手机 IP（USB 模式无需填写）'
        $pnlIp.Tag.Fill = $C.SurfaceDim
        $pnlIp.Tag.Border = $C.Border
    } else {
        Set-Pill $btnWifi 'Wi-Fi' $C.BlueSoft $C.Primary ''
        Set-Pill $btnUsb 'USB 数据线' $C.Surface $C.TextSecond $C.Border
        $txtIp.Enabled = $true
        $txtIp.BackColor = ToColor $C.Surface
        $txtIp.ForeColor = ToColor $C.TextPrimary
        $lblIp.ForeColor = ToColor $C.TextTert
        $lblIp.Text = '手机 IP'
        $pnlIp.Tag.Fill = $C.Surface
        $pnlIp.Tag.Border = $C.BorderDark
    }
    $pnlIp.Invalidate()
}

function Show-Failure([string]$msg) {
    $lblError.Text = $msg
    $lblError.Visible = $true
    Set-UiState 'error'
}

function Start-Stream {
    if ($script:proc -and -not $script:proc.HasExited) { return }

    $lblError.Visible = $false
    $txtLog.Clear()
    $videoArg = ''
    if (-not $chkVideo.Checked) { $videoArg = '--no-video' }

    $screenArg = ''
    if ($chkScreenOff.Checked) {
        $screenArg = '--turn-screen-off'
        Add-Log '手机屏幕将在连接后关闭，画面仍会继续传输'
    }

    # 键盘：uhid 模式会在手机上注册一块虚拟物理键盘（设备名就叫 scrcpy），
    # 按键走的是手机的输入子系统，文字交给手机自己的输入法去组词 —— 这样中文才能打出来。
    # 对照：sdk 模式只把键码注入焦点输入框，输入法在电脑侧组词，手机拿到的是拼音字母。
    # 前提是手机「外接键盘时显示输入法」已开启（show_ime_with_hard_keyboard=1），
    # 否则输入法不弹出，打拼音就没有候选词。启动时脚本会自动检查并纠正这一项。
    $kbdArg = '--keyboard=uhid'

    Set-UiState 'connecting'
    $form.Refresh()

    $selArg = ''
    if ($script:mode -eq 'usb') {
        Add-Log '模式: USB 数据线'
        $devs = (& $adbExe devices 2>$null | Out-String)
        $usbOk = $false
        foreach ($ln in ($devs -split "`n")) {
            $l = $ln.Trim()
            if ($l -match '^\S+\s+device$' -and $l -notmatch ':') { $usbOk = $true }
        }
        if (-not $usbOk) {
            Add-Log '没有检测到 USB 设备：'
            Add-Log '  1. 数据线插好了（必须是数据线，纯充电线不行）'
            Add-Log '  2. 手机通知栏 USB 模式选了「传输文件」'
            Add-Log '  3. 开发者选项里的「USB 调试」已打开'
            Show-Failure '没有检测到 USB 设备 · 点右上「日志」看排查步骤'
            return
        }
        Add-Log '已检测到 USB 设备'
        $selArg = '-d'
    } else {
        $ip = $txtIp.Text.Trim()
        if (-not $ip) {
            Show-Failure '请先填写手机的局域网 IP'
            return
        }
        Set-Content -Path $ipFile -Value $ip -Encoding ASCII
        $target = "${ip}:5555"
        Add-Log "模式: Wi-Fi   目标: $target"

        $conn = (& $adbExe connect $target 2>$null | Out-String).Trim()
        if ($conn) { Add-Log $conn }
        if ($conn -notmatch 'connected') {
            Add-Log '连接失败，常见原因：'
            Add-Log '  1. 手机 WLAN 里的 IP 与输入框不一致'
            Add-Log '  2. 手机和电脑不在同一网段（路由器开了 AP 隔离）'
            Add-Log '  3. 手机重启过，需要重新插线执行 adb tcpip 5555'
            Show-Failure '连接失败 · 点右上「日志」看排查步骤'
            return
        }
        $selArg = "-s ${target}"
    }

    # uhid 依赖手机在外接键盘时仍然弹出输入法，否则打拼音没有候选词。
    # 这一项在部分机型/输入法上是关的，启动前查一次，不是 1 就顺手打开（无需 root）。
    try {
        if ($script:mode -eq 'usb') { $adbSelArgs = @('-d') } else { $adbSelArgs = @('-s', $target) }
        $imeFlag = (& $adbExe @adbSelArgs shell settings get secure show_ime_with_hard_keyboard 2>$null | Out-String).Trim()
        if ($imeFlag -ne '1') {
            & $adbExe @adbSelArgs shell settings put secure show_ime_with_hard_keyboard 1 2>$null | Out-Null
            Add-Log '已开启手机的「外接键盘时显示输入法」，中文输入需要它'
        }
    } catch {
        Add-Log '提示: 无法读取输入法设置，若打不出中文请到手机 设置→系统和更新→语言和输入法 里'
        Add-Log '      勾选「外接键盘时显示输入法」'
    }

    if (Test-Path $logFile) { Remove-Item $logFile -Force -ErrorAction SilentlyContinue }

    $cmdArgs = "/c scrcpy.exe $selArg $videoArg $screenArg $kbdArg > `"$logFile`" 2>&1"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'cmd.exe'
    $psi.Arguments = $cmdArgs
    $psi.WorkingDirectory = $scrcpyDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    try {
        $script:proc = [System.Diagnostics.Process]::Start($psi)
        Set-UiState 'running'
        # 勾了「投屏时手机熄屏」的话，scrcpy 连上就把面板关了，按钮文案要跟着是「点亮屏幕」
        $script:screenOff = [bool]$chkScreenOff.Checked
        Set-ScreenLabel
        $btnScreen.Invalidate()
        $timer.Start()
    } catch {
        Add-Log ('启动失败: ' + $_.Exception.Message)
        Show-Failure ('启动失败 · ' + $_.Exception.Message)
    }
}

function Stop-Stream {
    if ($script:proc -and -not $script:proc.HasExited) {
        try { $script:proc.Kill() } catch { }
    }
    Get-Process scrcpy -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    if ($script:mode -eq 'wifi') {
        $ip = $txtIp.Text.Trim()
        if ($ip) { & $adbExe disconnect "${ip}:5555" 2>$null | Out-Null }
    }

    $timer.Stop()
    $script:screenOff = $false
    Set-ScreenLabel
    Set-UiState 'idle'
}

$btnMain.Add_Click({
    if ($script:state -eq 'running') { Stop-Stream } else { Start-Stream }
})

# ==== 运行时熄屏 / 点亮 ====
# 两个方向必须用两套机制，是这台机器上一路实测出来的：
#
# 熄屏：发 scrcpy 窗口的 MOD+o（MOD 默认左 Alt）。它只关 SurfaceFlinger 的显示电源，
#       面板黑、合成继续，所以镜像不断。
# 点亮：MOD+Shift+o 能把 SF 的 powerMode 恢复成 On、亮度也是正常值，但**华为那边的背光不会回来**，
#       屏幕依旧全黑 —— SF 的电源开关和 DisplayPowerController 是两套状态。唯一可靠的是走一次
#       真实电源周期（KEYCODE_SLEEP 26 → KEYCODE_WAKEUP 224），由 DPC 把面板和背光一起拉起。
#       代价是中途会短暂落到锁屏，事后用 wm dismiss-keyguard 尽力解掉。
#
# 状态判断读 dumpsys SurfaceFlinger 里物理屏那个 DisplayDevice 的 powerMode；scrcpy 自己会建一个
# virtual 的同名显示，要跳过。dumpsys display 的 mScreenState 无论开关都报 ON，不能用。
#
# 送键走 AppActivate + SendKeys：本机安全策略拦 Add-Type，P/Invoke 那条路会静默失效。

$script:screenOff = $false

# USB 用 -d，Wi-Fi 用 -s ip:5555
function Get-AdbSelArgs {
    if ($script:mode -eq 'usb') { return @('-d') }
    $ip = $txtIp.Text.Trim()
    if ($ip) { return @('-s', "${ip}:5555") }
    return @()
}

# 物理屏的真实电源状态：On / Off，读不到返回空串
function Get-PanelPowerMode {
    try {
        $sel = Get-AdbSelArgs
        $txt = (& $adbExe @sel shell dumpsys SurfaceFlinger 2>$null | Out-String)
        foreach ($m in [regex]::Matches($txt, 'DisplayDevice\{([^}]*)\}\s*powerMode=(\w+)')) {
            if ($m.Groups[1].Value -notmatch 'virtual') { return $m.Groups[2].Value }
        }
    } catch { }
    return ''
}

function Test-IsStreaming {
    return [bool]($script:proc -and -not $script:proc.HasExited)
}

function Get-LogLength {
    try {
        if (Test-Path -LiteralPath $logFile) { return [long](Get-Item -LiteralPath $logFile).Length }
    } catch { }
    return [long]0
}

function Get-LogFrom([long]$pos) {
    try {
        $fs = [System.IO.File]::Open($logFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            [void]$fs.Seek($pos, [System.IO.SeekOrigin]::Begin)
            $sr = New-Object System.IO.StreamReader($fs)
            $txt = $sr.ReadToEnd()
            $sr.Dispose()
            return $txt
        } finally { $fs.Dispose() }
    } catch { }
    return ''
}

function Set-ScreenLabel {
    if ($script:screenOff) {
        Set-Pill -Ctrl $btnScreen -Display '点亮屏幕' -Fill $C.Surface -TextColor $C.PrimaryDeep -Border $C.BorderDark
    } else {
        Set-Pill -Ctrl $btnScreen -Display '手机熄屏' -Fill $C.Surface -TextColor $C.PrimaryDeep -Border $C.BorderDark
    }
}

# 点亮用：两步。先让 scrcpy 把 SurfaceFlinger 的显示电源恢复成 On，
# 再让系统电源状态机真正走一次「关→开」，背光才会跟着回来。
function Invoke-PanelWake {
    # 1) SF 层恢复（这一步本身不会点亮面板）
    [void](Send-ScrcpyScreenKey -Wake:$true)
    Start-Sleep -Milliseconds 450

    # 2) 真实电源周期：睡着就直接唤醒，醒着就先睡再醒（DPC 只有走完这一趟才会重新上背光）
    try {
        $sel = Get-AdbSelArgs
        $w = (& $adbExe @sel shell dumpsys power 2>$null | Out-String)
        if ($w -notmatch 'mWakefulness=Asleep') {
            & $adbExe @sel shell input keyevent 26 2>$null | Out-Null
            Start-Sleep -Milliseconds 250
        }
        & $adbExe @sel shell input keyevent 224 2>$null | Out-Null
        Start-Sleep -Milliseconds 700
        & $adbExe @sel shell wm dismiss-keyguard 2>$null | Out-Null
        return 'ok'
    } catch { return 'adb_error' }
}

# 往镜像窗口送一次 MOD+o / MOD+Shift+o，返回 ok / no_window / no_com / no_focus / no_effect / send_error:xxx
function Send-ScrcpyScreenKey([switch]$Wake) {
    $sp = @(Get-Process scrcpy -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 })
    if ($sp.Count -eq 0) { return 'no_window' }

    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell } catch { return 'no_com' }

    $before = Get-LogLength
    $act = $false
    try { $act = [bool]$shell.AppActivate([int]$sp[0].Id) } catch { }
    if (-not $act) { try { $act = [bool]$shell.AppActivate($sp[0].MainWindowTitle) } catch { } }
    if (-not $act) {
        try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) } catch { }
        return 'no_focus'
    }

    Start-Sleep -Milliseconds 180
    try {
        if ($Wake) { [System.Windows.Forms.SendKeys]::SendWait('%+o') }
        else { [System.Windows.Forms.SendKeys]::SendWait('%o') }
    } catch {
        $msg = $_.Exception.Message
        try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) } catch { }
        return ('send_error:' + $msg)
    }

    # 焦点还给本程序，否则后面的输入会跑到镜像窗口里去
    Start-Sleep -Milliseconds 100
    try { [void]$shell.AppActivate([int][System.Diagnostics.Process]::GetCurrentProcess().Id) } catch { }
    try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) } catch { }
    try { $form.Activate() } catch { }

    # 以 scrcpy 日志里新增的那一行作为「指令真的执行了」的证据
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Milliseconds 120
        $new = Get-LogFrom $before
        if ($new -and ($new -match 'Device display turned (on|off)')) {
            if ($new -match 'Device display turned off') { $script:screenOff = $true }
            elseif ($new -match 'Device display turned on') { $script:screenOff = $false }
            else { $script:screenOff = -not $Wake }
            return 'ok'
        }
    }
    return 'no_effect'
}

$btnScreen.Add_Click({
    if (-not (Test-IsStreaming)) {
        Add-Log '需要先点「开始转发」——熄屏控制要切镜像窗口的快捷键，没有窗口就无从发起'
        Add-Log '  想在连上时就熄屏，勾「投屏时手机熄屏」即可'
        return
    }

    # 以手机真实状态为准，不看按钮上写的字（用户可能在镜像窗口里自己按过快捷键）
    $cur = Get-PanelPowerMode
    if ($cur) { $script:screenOff = ($cur -eq 'Off') }

    if ($script:screenOff) {
        Add-Log '正在点亮手机屏幕…'
        $form.Refresh()
        $r = Invoke-PanelWake
        if ($r -ne 'ok') {
            Add-Log '点亮失败：adb 命令没有执行成功，检查连接是否还在'
        } else {
            $now = Get-PanelPowerMode
            if ($now -eq 'Off' -or -not $now) {
                Add-Log '点亮指令已发出，但手机仍报告屏是关的，再点一次试试'
            } else {
                Add-Log '手机屏幕已点亮'
                $kw = ''
                try { $kw = (& $adbExe @(Get-AdbSelArgs) shell "dumpsys window | grep isKeyguardShowing" 2>$null | Out-String) } catch { }
                if ($kw -match 'isKeyguardShowing=true') {
                    Add-Log '  手机停在锁屏：华为这边点亮只能借电源周期，滑一下或解锁即可'
                }
            }
        }
    } else {
        Add-Log '正在关闭手机屏幕…'
        $form.Refresh()
        $r = Send-ScrcpyScreenKey -Wake:$false
        switch ($r) {
            'ok' { Add-Log '手机屏幕已关闭，画面继续传输（再点一次可点亮）' }
            'no_window' { Add-Log '没有找到镜像窗口（纯音频模式没有窗口），这种情况直接按手机电源键' }
            'no_com' { Add-Log '系统拦住了按键模拟通道，无法自动熄屏，请直接按手机电源键' }
            'no_focus' { Add-Log '切不过去镜像窗口（可能被全屏程序占着），先点一下镜像窗口再点本按钮' }
            'no_effect' { Add-Log '指令发出去了但 scrcpy 没响应，先点一下镜像窗口再试一次' }
            default { Add-Log ('发送失败: ' + $r) }
        }
    }

    $st = Get-PanelPowerMode
    if ($st) { $script:screenOff = ($st -eq 'Off') }
    Set-ScreenLabel
    $btnScreen.Invalidate()
})

$btnWifi.Add_Click({ Set-Mode 'wifi' })
$btnUsb.Add_Click({ Set-Mode 'usb' })

$btnLog.Add_Click({
    if (-not $logForm.Visible) { $logForm.Show() }
    Set-WindowIcon $logForm.Handle $icoPath
    $logForm.BringToFront()
    $logForm.Activate()
})

$timer.Add_Tick({
    if ($script:proc -and $script:proc.HasExited) {
        if ($script:state -eq 'running') {
            Add-Log '[断开] scrcpy 已退出'
            Show-Failure '连接已断开 · 检查手机 Wi-Fi 或 IP 是否变化'
        }
        $timer.Stop()
    }
    if (Test-Path $logFile) {
        $content = Get-Content -Path $logFile -Raw -ErrorAction SilentlyContinue
        if ($content) {
            $txtLog.Text = $content
            $txtLog.SelectionStart = $txtLog.Text.Length
            $txtLog.ScrollToCaret()
        }
    }
})

$form.Add_FormClosing({
    param($s, $e)
    if ($script:state -eq 'running') {
        $r = [System.Windows.Forms.MessageBox]::Show('正在转发中，确定要停止并退出吗？', '确认', 'YesNo', 'Question')
        if ($r -ne 'Yes') { $e.Cancel = $true; return }
    }
    Stop-Stream
})

$uiTimer = New-Object System.Windows.Forms.Timer
$uiTimer.Interval = 400
$uiTimer.Add_Tick({
    $uiTimer.Stop()
    try {
        if ($script:hasNative) {
            $hCon = [NativeConsole]::GetConsoleWindow()
            if ($hCon -ne [IntPtr]::Zero) { [void][NativeConsole]::ShowWindow($hCon, 0) }
            [void][NativeConsole]::ShowWindow($form.Handle, 5)
            Set-WindowIcon $form.Handle $icoPath
            [void][NativeConsole]::SetForegroundWindow($form.Handle)
        }
    } catch { }
})
$uiTimer.Start()

# 熄屏状态改由按钮点击时实时读手机，不再轮询
# （dumpsys SurfaceFlinger 每次要几百毫秒，挂在 UI 线程上定时跑会让界面发卡）

$guardTimer = New-Object System.Windows.Forms.Timer
$guardTimer.Interval = 1200
$guardTimer.Add_Tick({
    $guardTimer.Stop()
    try {
        if (-not $form.Visible) { $form.Show() }
        [void][NativeConsole]::ShowWindow($form.Handle, 5)
    } catch { }
})
$guardTimer.Start()

Set-Mode 'wifi'
Set-UiState 'idle'

Add-Log '就绪'
Add-Log '  Wi-Fi : 填手机 WLAN 里的 IP，端口固定 5555'
Add-Log '  USB   : 选「USB 数据线」，无需 IP'
Add-Log ''
Add-Log '键盘输入：连上后点一下镜像窗口让它获得焦点，即可直接打字。'
Add-Log '  中文走手机输入法组词，手机上会看到候选词；打不出中文时用 Ctrl+V 粘贴兜底。'

[void]$form.ShowDialog()
