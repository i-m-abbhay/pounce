param(
  [string]$Message = "Claude is waiting for your response",
  [string]$Mascot,           # cat | ghost | robot | blob | frog | random | custom name | sprite .txt path (default: saved pick, else cat)
  [switch]$NoSwat,           # keep the mascot inside the card; never touch the mouse pointer
  [switch]$Pick              # open the mascot picker and save the choice
)
# pounce: a desktop notification card for Claude Code hooks (Stop / Notification).
# Unofficial; not affiliated with Anthropic.
# ASCII-only on purpose: powershell.exe 5.1 reads BOM-less files as ANSI.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Rgb($hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
$bg      = Rgb '#1F1E1D'
$surface = Rgb '#2A2927'
$text    = Rgb '#ECEAE4'
$muted   = Rgb '#9C9A92'
$accent  = Rgb '#D97757'
$uiFont  = 'Segoe UI'
# --- one compile for all native calls ---
Add-Type -Namespace Native -Name Win32 -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool FlashWindowEx(ref FLASHWINFO pwfi);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
[DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
[StructLayout(LayoutKind.Sequential)]
public struct FLASHWINFO {
  public uint cbSize; public IntPtr hwnd; public uint dwFlags; public uint uCount; public uint dwTimeout;
}
"@

# --- mascots: '#' body, 'o' eye (blinks / looks around), '.' empty; the last row is the feet ---
$sprites = @{
  cat = @(
    '.#..........#.',
    '.##........##.',
    '.############.',
    '.###o####o###.',
    '.###o####o###.',
    '.############.',
    '..##########..',
    '..#.#....#.#..')
  ghost = @(
    '....######....',
    '..##########..',
    '.############.',
    '.##oo####oo##.',
    '.##oo####oo##.',
    '.############.',
    '.############.',
    '.############.',
    '##..##..##..##')
  robot = @(
    '......##......',
    '......##......',
    '..##########..',
    '..#oo####oo#..',
    '..##########..',
    '..###....###..',
    '..##########..',
    '....######....',
    '...##....##...')
  blob = @(
    '.....####.....',
    '...########...',
    '..##########..',
    '.###o####o###.',
    '.###o####o###.',
    '.############.',
    '##############',
    '.#.#.#..#.#.#.')
  frog = @(
    '..###....###..',
    '.##o##..##o##.',
    '.############.',
    '.############.',
    '.####....####.',
    '.############.',
    '..##########..',
    '.##..#..#..##.')
}

$claudeDir  = Join-Path $env:USERPROFILE '.claude'
$choiceFile = Join-Path $claudeDir 'pounce-mascot.txt'    # saved by -Pick
$customDir  = Join-Path $claudeDir 'pounce-mascots'       # extra sprites: <name>.txt

# name -> sprite rows: built-in, custom-folder name, or a file path; unknown -> cat
function Get-SpriteRows($name) {
  if ($sprites[$name]) { return $sprites[$name] }
  foreach ($f in @((Join-Path $customDir "$name.txt"), $name)) {
    if ($f -and (Test-Path -LiteralPath $f -PathType Leaf)) { return @(Get-Content -LiteralPath $f | Where-Object { $_.Trim() }) }
  }
  $sprites['cat']
}
function Get-CustomNames { if (Test-Path $customDir) { @(Get-ChildItem -LiteralPath $customDir -Filter *.txt | ForEach-Object BaseName) } else { @() } }

# rows -> drawable sprite; Use-Sprite makes it the one Draw-Mascot paints
function New-Sprite($rows) {
  $sp = @{ Base = @{}; Eyes = @(); Cols = 0; MaxX = 0; RowCount = $rows.Count }
  for ($y = 0; $y -lt $rows.Count; $y++) {
    $sp.Cols = [Math]::Max($sp.Cols, $rows[$y].Length)
    for ($x = 0; $x -lt $rows[$y].Length; $x++) {
      switch ($rows[$y][$x]) {
        '#' { $sp.Base["$x,$y"] = 1; $sp.MaxX = [Math]::Max($sp.MaxX, $x) }
        'o' { $sp.Eyes += , @($x, $y) }
      }
    }
  }
  $sp.LegY = $rows.Count - 1
  $sp.MidY = [int][Math]::Floor($rows.Count / 2)
  $sp.Unit = [int][Math]::Max(3, [Math]::Min(6, [Math]::Floor(76 / $sp.Cols)))
  $sp
}
function Use-Sprite($sp) {
  $script:base = $sp.Base; $script:eyes = $sp.Eyes; $script:cols = $sp.Cols; $script:maxX = $sp.MaxX
  $script:rowCount = $sp.RowCount; $script:legY = $sp.LegY; $script:midY = $sp.MidY; $script:unit = $sp.Unit
}
$padX = 6; $hopRoom = 12
# poses: loop (48-frame idle: hop + shuffle, wave, wiggle, look around, blink), walk, up (paw raised), hit (paw out)
function Draw-Mascot($g, $pose, $f) {
  $cells = $script:base.Clone(); $dx = 0; $dy = 0
  $shuffle = {
    $feet = @($cells.Keys | Where-Object { $_.EndsWith(",$legY") })
    foreach ($k in $feet) { $cells.Remove($k) }
    foreach ($k in $feet) { $cells["$([int]$k.Split(',')[0] + 1),$legY"] = 1 }
  }
  $look = { param($d)
    foreach ($e in $eyes) { $cells["$($e[0]),$($e[1])"] = 1 }
    foreach ($e in $eyes) { $cells.Remove("$($e[0] + $d),$($e[1])") }
  }
  $blink = { foreach ($e in $eyes) { $cells["$($e[0]),$($e[1])"] = 1 } }
  switch ($pose) {
    'walk' { $dy = - [int](4 * [Math]::Abs([Math]::Sin($f * [Math]::PI / 3))); if ($f % 2) { & $shuffle } }
    'up'   { $cells["$($maxX + 1),$($midY - 1)"] = 1; $cells["$($maxX + 2),$($midY - 2)"] = 1; & $look 1 }
    'hit'  { $cells["$($maxX + 1),$midY"] = 1; $cells["$($maxX + 2),$midY"] = 1; $dx = $unit; & $look 1 }
    default {
      $f = $f % 48
      switch ([int][Math]::Floor($f / 12)) {
        0 { $dy = - [int](10 * [Math]::Abs([Math]::Sin($f * [Math]::PI / 6))); if ($f % 2) { & $shuffle } }
        1 { $cells["$($maxX + 1),$($midY - 1)"] = 1; $cells["$($maxX + 1 + ($f % 2)),$($midY - 2)"] = 1 }   # wave
        2 { $dx = if ($f % 2) { $unit } else { - $unit }; if ($f % 2) { & $shuffle } }                        # wiggle
        3 {
          if ($f -lt 40)         { & $look -1 }
          elseif ($f -lt 44)     { & $look 1 }
          elseif ($f -in 45, 46) { & $blink }
        }
      }
    }
  }
  $brush = New-Object System.Drawing.SolidBrush($accent)
  foreach ($k in $cells.Keys) {
    $xy = $k.Split(',')
    $g.FillRectangle($brush, ($padX + $dx + [int]$xy[0] * $unit), ($hopRoom + $dy + [int]$xy[1] * $unit), $unit, $unit)
  }
  $brush.Dispose()
}

# --- picker: every mascot animating in a grid; click to select, Save writes the choice ---
if ($Pick) {
  $current = if (Test-Path $choiceFile) { (Get-Content $choiceFile -Raw).Trim() } else { 'cat' }
  $names = @('cat', 'ghost', 'robot', 'blob', 'frog') + (Get-CustomNames) + @('random')
  $script:selected = $current
  $script:frame = 0

  $pk = New-Object System.Windows.Forms.Form
  $pk.Text = 'pounce - pick a mascot'
  $pk.StartPosition = 'CenterScreen'
  $pk.FormBorderStyle = 'FixedDialog'
  $pk.MaximizeBox = $false
  $pk.BackColor = $bg
  $pk.KeyPreview = $true
  $pk.Font = New-Object System.Drawing.Font($uiFont, 9)

  $title = New-Object System.Windows.Forms.Label
  $title.Text = 'Pick your mascot'
  $title.Font = New-Object System.Drawing.Font($uiFont, 13, [System.Drawing.FontStyle]::Bold)
  $title.ForeColor = $text
  $title.SetBounds(20, 16, 400, 28)
  $sub = New-Object System.Windows.Forms.Label
  $sub.Text = 'Click one, then Save (or double-click). Add your own: .claude\pounce-mascots\<name>.txt'
  $sub.ForeColor = $muted
  $sub.AutoEllipsis = $true
  $sub.SetBounds(20, 44, 560, 20)
  $pk.Controls.AddRange(@($title, $sub))

  $tileW = 136; $tileH = 120; $perRow = 4
  $tiles = @()
  for ($i = 0; $i -lt $names.Count; $i++) {
    $t = New-Object System.Windows.Forms.Panel
    $t.SetBounds((20 + ($i % $perRow) * ($tileW + 10)), (76 + [Math]::Floor($i / $perRow) * ($tileH + 10)), $tileW, $tileH)
    $t.BackColor = $surface
    $t.Cursor = 'Hand'
    $t.TabIndex = $i
    $t.Tag = @{ Name = $names[$i]; Sprite = $(if ($names[$i] -ne 'random') { New-Sprite (Get-SpriteRows $names[$i]) }) }
    $t.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($t, $true, $null)
    $t.Add_Paint({
      param($sender, $e)
      $info = $sender.Tag; $g = $e.Graphics
      if ($info.Sprite) {
        Use-Sprite $info.Sprite
        $w = ($cols + 3) * $unit + 2 * $padX
        $g.TranslateTransform([int](($sender.Width - $w) / 2), 6)
        Draw-Mascot $g 'loop' ($script:frame + $sender.TabIndex * 7)   # offset so they don't move in sync
        $g.ResetTransform()
      } else {
        $qf = New-Object System.Drawing.Font($uiFont, 28, [System.Drawing.FontStyle]::Bold)
        $sz = $g.MeasureString('?', $qf)
        $qb = New-Object System.Drawing.SolidBrush($accent)
        $g.DrawString('?', $qf, $qb, (($sender.Width - $sz.Width) / 2), 22)
        $qb.Dispose(); $qf.Dispose()
      }
      $isSel = $info.Name -eq $script:selected
      $nb = New-Object System.Drawing.SolidBrush($(if ($isSel) { $text } else { $muted }))
      $nf = New-Object System.Drawing.Font($uiFont, 9, $(if ($isSel) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }))
      $ns = $g.MeasureString($info.Name, $nf)
      $g.DrawString($info.Name, $nf, $nb, (($sender.Width - $ns.Width) / 2), ($sender.Height - 26))
      $nb.Dispose(); $nf.Dispose()
      if ($isSel) {
        $pen = New-Object System.Drawing.Pen($accent, 3)
        $g.DrawRectangle($pen, 1, 1, ($sender.Width - 3), ($sender.Height - 3))
        $pen.Dispose()
      }
    })
    $t.Add_Click({ param($sender) $script:selected = $sender.Tag.Name; foreach ($x in $tiles) { $x.Invalidate() } })
    $t.Add_DoubleClick({ param($sender) $script:selected = $sender.Tag.Name; $save.PerformClick() })
    $tiles += $t
  }
  $pk.Controls.AddRange($tiles)

  $btnY = 76 + [Math]::Ceiling($names.Count / $perRow) * ($tileH + 10) + 6
  $save = New-Object System.Windows.Forms.Button
  $save.Text = 'Save'
  $save.Font = New-Object System.Drawing.Font($uiFont, 9, [System.Drawing.FontStyle]::Bold)
  $save.FlatStyle = 'Flat'; $save.FlatAppearance.BorderSize = 0
  $save.BackColor = $accent; $save.ForeColor = $bg; $save.Cursor = 'Hand'
  $save.SetBounds(20, $btnY, 120, 34)
  $save.Add_Click({
    if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir | Out-Null }
    Set-Content -LiteralPath $choiceFile -Value $script:selected -NoNewline
    $pk.Close()
  })
  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = 'Cancel'
  $cancel.Font = $save.Font
  $cancel.FlatStyle = 'Flat'; $cancel.FlatAppearance.BorderSize = 0
  $cancel.BackColor = $surface; $cancel.ForeColor = $text; $cancel.Cursor = 'Hand'
  $cancel.SetBounds(150, $btnY, 100, 34)
  $cancel.Add_Click({ $pk.Close() })
  $pk.Controls.AddRange(@($save, $cancel))
  $pk.AcceptButton = $save
  $pk.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $pk.Close() } })
  $pk.ClientSize = New-Object System.Drawing.Size((40 + $perRow * ($tileW + 10) - 10), ($btnY + 34 + 20))

  $tick = New-Object System.Windows.Forms.Timer
  $tick.Interval = 90
  $tick.Add_Tick({ $script:frame++; foreach ($x in $tiles) { $x.Invalidate() } })
  $pk.Add_Shown({
    $dark = 1
    [Native.Win32]::DwmSetWindowAttribute($pk.Handle, 20, [ref]$dark, 4) | Out-Null
    $tick.Start()
  })
  [void]$pk.ShowDialog()
  $tick.Dispose()
  return
}

# --- the mascot for this card: -Mascot, else the saved pick, else cat ---
if (-not $Mascot) { $Mascot = if (Test-Path $choiceFile) { (Get-Content $choiceFile -Raw).Trim() } else { 'cat' } }
if ($Mascot -eq 'random') { $Mascot = Get-Random -InputObject (@($sprites.Keys) + (Get-CustomNames)) }
Use-Sprite (New-Sprite (Get-SpriteRows $Mascot))
# --- context from hook JSON on stdin (empty when run manually) ---
$hookEvent = 'Stop'
$folder = $null
$detail = $null
if ([Console]::IsInputRedirected) {
  $stdin = [Console]::In.ReadToEnd()
  if ($stdin) {
    try {
      $hookInfo = $stdin | ConvertFrom-Json
      if ($hookInfo.hook_event_name) { $hookEvent = $hookInfo.hook_event_name }
      if ($hookInfo.cwd) { $folder = Split-Path -Leaf $hookInfo.cwd }
      if ($hookEvent -eq 'Notification' -and $hookInfo.message) { $detail = $hookInfo.message }
      if ($hookEvent -eq 'Stop' -and $hookInfo.last_assistant_message) { $detail = $hookInfo.last_assistant_message }
    } catch {}
  }
}
if (-not $detail) { $detail = $Message }

# strip markdown noise so the snippet reads as plain text
$detail = $detail -replace '```[\s\S]*?```', ' [code] '
$detail = $detail -replace '\[([^\]]+)\]\([^)]+\)', '$1'   # [text](url) -> text
$detail = $detail -replace '(?m)^\s*(#+|>|[-*]|\d+\.)\s+', ''
$detail = $detail -replace '\*\*|__|`|\*', ''
$detail = ($detail -replace '\s+', ' ').Trim()
if ($detail.Length -gt 260) { $detail = $detail.Substring(0, 260).TrimEnd() + '...' }

# --- find the terminal window: one process snapshot, then walk parents ---
$parentOf = @{}
Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId | ForEach-Object { $parentOf[[int]$_.ProcessId] = [int]$_.ParentProcessId }
$hwnd = [IntPtr]::Zero
$id = $PID
for ($i = 0; $i -lt 15 -and $id; $i++) {
  $p = Get-Process -Id $id -ErrorAction SilentlyContinue
  if ($p -and $p.MainWindowHandle -ne [IntPtr]::Zero) { $hwnd = $p.MainWindowHandle; break }
  $id = $parentOf[$id]
}

$force = $env:POUNCE_FORCE -eq '1'   # testing: show even while the terminal is focused
if (-not $force -and $hwnd -ne [IntPtr]::Zero -and $hwnd -eq [Native.Win32]::GetForegroundWindow()) {
  return  # already looking at the terminal
}

if ($hwnd -ne [IntPtr]::Zero) {
  $fw = New-Object Native.Win32+FLASHWINFO
  $fw.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($fw)
  $fw.hwnd = $hwnd
  $fw.dwFlags = 0x0000000F  # FLASHW_ALL | FLASHW_TIMERNOFG
  $fw.uCount = 5
  [Native.Win32]::FlashWindowEx([ref]$fw) | Out-Null
}

function Focus-Terminal {
  if ($hwnd -ne [IntPtr]::Zero) {
    # restore only when minimized; SW_RESTORE on a maximized window un-maximizes it
    if ([Native.Win32]::IsIconic($hwnd)) { [Native.Win32]::ShowWindowAsync($hwnd, 9) | Out-Null }
    [Native.Win32]::SetForegroundWindow($hwnd) | Out-Null
  }
}

# --- card UI ---
if ($hookEvent -eq 'Notification') { $accent = Rgb '#E5A54B' }
$heading = if ($hookEvent -eq 'Notification') { 'Needs your input' } else { 'Response ready' }

$W = 400; $H = 196
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Claude Code'
$form.FormBorderStyle = 'None'
$form.StartPosition = 'Manual'
$form.ClientSize = New-Object System.Drawing.Size($W, $H)
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.BackColor = $bg
$form.KeyPreview = $true
$form.Opacity = 0

# bottom-right of the screen the mouse is on, like a system notification
$screen = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea
$form.Location = New-Object System.Drawing.Point(($screen.Right - $W - 16), ($screen.Bottom - $H - 16))

$bar = New-Object System.Windows.Forms.Panel
$bar.BackColor = $accent
$bar.SetBounds(0, 0, 4, $H)

$appLabel = New-Object System.Windows.Forms.Label
$appLabel.Text = 'CLAUDE CODE' + $(if ($folder) { '  ' + [char]0x00B7 + '  ' + $folder } else { '' })
$appLabel.Font = New-Object System.Drawing.Font($uiFont, 8, [System.Drawing.FontStyle]::Bold)
$appLabel.ForeColor = $muted
$appLabel.AutoEllipsis = $true
$appLabel.SetBounds(22, 16, 290, 18)

$timeLabel = New-Object System.Windows.Forms.Label
$timeLabel.Text = (Get-Date -Format 'HH:mm')
$timeLabel.Font = New-Object System.Drawing.Font($uiFont, 8)
$timeLabel.ForeColor = $muted
$timeLabel.TextAlign = 'TopRight'
$timeLabel.SetBounds(312, 16, 44, 18)

$close = New-Object System.Windows.Forms.Label
$close.Text = [string][char]0x2715
$close.Font = New-Object System.Drawing.Font($uiFont, 9)
$close.ForeColor = $muted
$close.TextAlign = 'MiddleCenter'
$close.Cursor = 'Hand'
$close.SetBounds(362, 10, 28, 28)
$close.Add_MouseEnter({ $close.ForeColor = $text })
$close.Add_MouseLeave({ $close.ForeColor = $muted })
$close.Add_Click({ $form.Close() })

$headLabel = New-Object System.Windows.Forms.Label
$headLabel.Text = $heading
$headLabel.Font = New-Object System.Drawing.Font($uiFont, 12, [System.Drawing.FontStyle]::Bold)
$headLabel.ForeColor = $text
$headLabel.SetBounds(22, 38, 360, 26)

$body = New-Object System.Windows.Forms.Label
$body.Text = $detail
$body.Font = New-Object System.Drawing.Font($uiFont, 9.5)
$body.ForeColor = $muted
$body.AutoEllipsis = $true
$body.UseMnemonic = $false   # keep literal '&' characters
$body.SetBounds(22, 68, 360, 66)

function New-CardButton($caption, $fill, $fore) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $caption
  $b.Font = New-Object System.Drawing.Font($uiFont, 9, [System.Drawing.FontStyle]::Bold)
  $b.FlatStyle = 'Flat'
  $b.FlatAppearance.BorderSize = 0
  $b.BackColor = $fill
  $b.ForeColor = $fore
  $b.Cursor = 'Hand'
  $b
}
$go = New-CardButton 'Go to Claude' $accent $bg
$go.FlatAppearance.MouseOverBackColor = [System.Windows.Forms.ControlPaint]::Light($accent, 0.2)
$go.SetBounds(22, 146, 150, 34)
$go.Add_Click({ Focus-Terminal; $form.Close() })

$later = New-CardButton 'Dismiss' $surface $text
$later.FlatAppearance.MouseOverBackColor = [System.Windows.Forms.ControlPaint]::Light($surface, 0.3)
$later.SetBounds(182, 146, 100, 34)
$later.Add_Click({ $form.Close() })

# --- mascot drawing ---
$mW = ($cols + 3) * $unit + 2 * $padX; $mH = $rowCount * $unit + $hopRoom
$pet = New-Object System.Windows.Forms.Panel
$pet.SetBounds(($W - $mW - 8), ($H - $mH - 8), $mW, $mH)
$pet.BackColor = $bg
$pet.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($pet, $true, $null)
$script:frame = 0

$pet.Add_Paint({ Draw-Mascot $_.Graphics 'loop' $script:frame })

# --- the pounce: a click-through copy of the mascot that leaves the card and bats the pointer ---
$cat = New-Object System.Windows.Forms.Form
$cat.FormBorderStyle = 'None'
$cat.ShowInTaskbar = $false
$cat.TopMost = $true
$cat.StartPosition = 'Manual'
$cat.Size = $pet.Size
$cat.BackColor = [System.Drawing.Color]::Magenta
$cat.TransparencyKey = [System.Drawing.Color]::Magenta
$cat.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($cat, $true, $null)
$cat.Add_Paint({ Draw-Mascot $_.Graphics $script:catPose $script:frame })
$exStyle = [Native.Win32]::GetWindowLong($cat.Handle, -20)
[Native.Win32]::SetWindowLong($cat.Handle, -20, ($exStyle -bor 0x80020 -bor 0x80 -bor 0x08000000)) | Out-Null  # layered, click-through, toolwindow, noactivate
$form.Add_FormClosed({ $cat.Close() })

$pawX = $padX + ($maxX + 4) * $unit; $pawY = $hopRoom + $midY * $unit + [int]($unit / 2)   # paw tip in the hit pose
$script:catState = 'home'; $script:catPose = 'walk'; $script:catT = 0; $script:nextAttack = 12   # first pounce ~1s after showing
function Get-CatTarget {
  $c = [System.Windows.Forms.Cursor]::Position
  New-Object System.Drawing.Point(($c.X - $pawX - 2), ($c.Y - $pawY))
}
function Move-CatToward($pt) {
  $nx = $cat.Left + [int](($pt.X - $cat.Left) * 0.3); $ny = $cat.Top + [int](($pt.Y - $cat.Top) * 0.3)
  $cat.Location = New-Object System.Drawing.Point($nx, $ny)
  [Math]::Abs($pt.X - $nx) + [Math]::Abs($pt.Y - $ny) -lt 8
}

$anim = New-Object System.Windows.Forms.Timer
$anim.Interval = 90
$anim.Add_Tick({
  $script:frame++
  $script:catT++
  switch ($script:catState) {
    'home' {
      $pet.Invalidate()
      if ($NoSwat -or $script:catT -lt $script:nextAttack) { return }
      if ($form.Bounds.Contains([System.Windows.Forms.Cursor]::Position)) { $script:catT = 0; $script:nextAttack = 60; return }  # already looking
      $cat.Location = $pet.PointToScreen([System.Drawing.Point]::Empty)
      $pet.Visible = $false; $cat.Show(); $form.Activate()
      $script:catState = 'out'; $script:catPose = 'walk'; $script:catT = 0
    }
    'out' {   # chase the pointer, even if it moves
      $arrived = Move-CatToward (Get-CatTarget)
      if ($arrived -or $script:catT -gt 40) { $script:catState = 'swat'; $script:catT = 0 }
    }
    'swat' {  # up, hit, up, hit, up, hit
      $script:catPose = if ($script:catT % 2) { 'hit' } else { 'up' }
      if ($script:catPose -eq 'hit') {
        $c = [System.Windows.Forms.Cursor]::Position
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(($c.X + 10), ($c.Y + 3))
      }
      if ($script:catT -ge 6) { $script:catState = 'back'; $script:catPose = 'walk'; $script:catT = 0 }
    }
    'back' {
      $arrived = Move-CatToward ($pet.PointToScreen([System.Drawing.Point]::Empty))
      if ($arrived -or $script:catT -gt 40) {
        $cat.Hide(); $pet.Visible = $true
        $script:catState = 'home'; $script:catT = 0; $script:nextAttack = 200   # again in ~18s if still ignored
      }
    }
  }
  $cat.Invalidate()
})

$form.Controls.AddRange(@($bar, $appLabel, $timeLabel, $close, $headLabel, $body, $go, $later, $pet))
$form.AcceptButton = $go
$form.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $form.Close() } })

# drag the borderless card by its background or labels
$drag = { if ($_.Button -eq 'Left') { $script:dragFrom = [System.Windows.Forms.Cursor]::Position; $script:formFrom = $form.Location } }
$move = { if ($_.Button -eq 'Left' -and $script:dragFrom) {
  $c = [System.Windows.Forms.Cursor]::Position
  $form.Location = New-Object System.Drawing.Point(($script:formFrom.X + $c.X - $script:dragFrom.X), ($script:formFrom.Y + $c.Y - $script:dragFrom.Y)) } }
foreach ($ctl in @($form, $appLabel, $headLabel, $body, $pet)) { $ctl.Add_MouseDown($drag); $ctl.Add_MouseMove($move) }

# fade in, then close by itself once the user is back in the terminal
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 30
$timer.Add_Tick({
  if ($form.Opacity -lt 1) { $form.Opacity = [Math]::Min(1.0, $form.Opacity + 0.12); return }   # 1.0, not 1: the int overload would truncate to 0
  $timer.Interval = 1000
  if (-not $force -and $hwnd -ne [IntPtr]::Zero -and [Native.Win32]::GetForegroundWindow() -eq $hwnd) { $form.Close() }
})

$form.Add_Shown({
  $round = 2  # DWMWCP_ROUND (Windows 11 rounded corners + shadow)
  [Native.Win32]::DwmSetWindowAttribute($form.Handle, 33, [ref]$round, 4) | Out-Null
  $dark = 1
  [Native.Win32]::DwmSetWindowAttribute($form.Handle, 20, [ref]$dark, 4) | Out-Null
  $form.Activate()
  $timer.Start()
  $anim.Start()
})
[void]$form.ShowDialog()
$timer.Dispose(); $anim.Dispose()
