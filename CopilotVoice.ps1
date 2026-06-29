#requires -Version 5.1
<#
  Copilot Voice - a voice assistant powered by GitHub Models.
  - Talk with your microphone (Windows built-in speech recognition)
  - It talks back (Windows SAPI text-to-speech)
  - Powered by GitHub Copilot models (GitHub Models API)
  - Built-in model picker

  Zero external installs: uses Windows .NET System.Speech + the GitHub CLI token.

  Voice or typed commands:  "switch model", "new chat", "exit"
#>
param(
  [string]$Model = "",
  [string]$Voice = "Microsoft Zira Desktop",
  [string]$Token = "",
  [switch]$NoVosk
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$script:CatalogUrl   = "https://api.githubcopilot.com/models"
$script:ChatUrl      = "https://api.githubcopilot.com/chat/completions"
$script:ResponsesUrl = "https://api.githubcopilot.com/responses"
$script:ExchangeUrl  = "https://api.github.com/copilot_internal/v2/token"
$script:UserUrl      = "https://api.github.com/user"

# GitHub device-code sign-in (the GitHub Copilot OAuth app, as used by editor plugins).
$script:ClientId       = "Iv1.b507a08c87ecfe98"
$script:DeviceCodeUrl  = "https://github.com/login/device/code"
$script:AccessTokenUrl = "https://github.com/login/oauth/access_token"
$script:OAuthCachePath = Join-Path $env:LOCALAPPDATA "CopilotVoice\account.dat"

# ---- Auth state (resolved from the signed-in GitHub Copilot account) ----
$script:OAuthToken    = $null               # GitHub account token (identity / Copilot entitlement)
$script:NeedsExchange = $false              # does the OAuth token need exchanging for a Copilot token?
$script:Bearer        = $null               # current bearer used for api.githubcopilot.com
$script:BearerExp     = [datetime]::MinValue
$script:Login         = $null               # GitHub username of the signed-in account

function Get-Headers($token) {
  return @{
    Authorization            = "Bearer $token"
    "Content-Type"           = "application/json"
    "Copilot-Integration-Id" = "vscode-chat"
    "Editor-Version"         = "CopilotVoice/1.0"
  }
}

function Find-Gh {
  $cmd = Get-Command gh -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $candidates = @(
    "$env:LOCALAPPDATA\copilot-desktop-gh-*\gh.exe",
    "$env:ProgramFiles\GitHub CLI\gh.exe",
    "${env:ProgramFiles(x86)}\GitHub CLI\gh.exe",
    "$env:LOCALAPPDATA\Programs\GitHub CLI\gh.exe"
  )
  foreach ($c in $candidates) {
    $found = Get-ChildItem $c -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($found) { return $found.FullName }
  }
  return $null
}

function Invoke-Json($uri, $headers, $method = 'Get', $bodyBytes = $null) {
  if ($bodyBytes) {
    $wr = Invoke-WebRequest -Uri $uri -Method $method -Headers $headers -Body $bodyBytes -UseBasicParsing -TimeoutSec 60
  } else {
    $wr = Invoke-WebRequest -Uri $uri -Method $method -Headers $headers -UseBasicParsing -TimeoutSec 60
  }
  $txt = [System.Text.Encoding]::UTF8.GetString($wr.RawContentStream.ToArray())
  if ([string]::IsNullOrWhiteSpace($txt)) { return $null }
  return ($txt | ConvertFrom-Json)
}

function Test-CopilotToken($bearer) {
  if (-not $bearer) { return $false }
  try { Invoke-Json $script:CatalogUrl (Get-Headers $bearer) | Out-Null; return $true } catch { return $false }
}

function Exchange-Token($oauth) {
  # Exchange a GitHub OAuth token for a short-lived Copilot token (what editors do).
  try {
    $h = @{ Authorization = "token $oauth"; "User-Agent" = "CopilotVoice/1.0"; Accept = "application/json" }
    $j = Invoke-Json $script:ExchangeUrl $h 'Get' $null
    if ($j -and $j.token) {
      $exp = (Get-Date).AddMinutes(20)
      if ($j.expires_at) { try { $exp = [DateTimeOffset]::FromUnixTimeSeconds([int64]$j.expires_at).LocalDateTime } catch {} }
      return @{ Token = $j.token; Exp = $exp }
    }
  } catch {}
  return $null
}

function Get-Login($oauth) {
  try {
    $j = Invoke-Json $script:UserUrl @{ Authorization = "token $oauth"; "User-Agent" = "CopilotVoice/1.0" }
    if ($j.login) { return $j.login }
  } catch {}
  return $null
}

function Try-Account($oauth) {
  # Returns an account hashtable if this GitHub token grants Copilot access, else $null.
  if (-not $oauth) { return $null }
  if (Test-CopilotToken $oauth) {
    return @{ OAuth = $oauth; NeedsExchange = $false; Bearer = $oauth; Exp = [datetime]::MaxValue; Login = (Get-Login $oauth) }
  }
  $ex = Exchange-Token $oauth
  if ($ex -and (Test-CopilotToken $ex.Token)) {
    return @{ OAuth = $oauth; NeedsExchange = $true; Bearer = $ex.Token; Exp = $ex.Exp; Login = (Get-Login $oauth) }
  }
  return $null
}

function Get-GhToken {
  $gh = Find-Gh
  if ($gh) { try { $t = & $gh auth token 2>$null; if ($t) { return $t.Trim() } } catch {} }
  return $null
}

function Resolve-Account {
  # Use whoever is signed in. First candidate with Copilot access wins.
  $candidates = New-Object System.Collections.Generic.List[string]
  if ($Token) { $candidates.Add($Token) }
  if ($env:GITHUB_TOKEN) { $candidates.Add($env:GITHUB_TOKEN) }
  if ($env:GH_TOKEN) { $candidates.Add($env:GH_TOKEN) }
  $ghTok = Get-GhToken
  if ($ghTok) { $candidates.Add($ghTok) }
  $cached = Get-CachedOAuth
  if ($cached) { $candidates.Add($cached) }
  foreach ($c in $candidates) {
    $acct = Try-Account $c
    if ($acct) { return $acct }
  }
  return $null
}

function Set-Account($acct) {
  $script:OAuthToken    = $acct.OAuth
  $script:NeedsExchange = $acct.NeedsExchange
  $script:Bearer        = $acct.Bearer
  $script:BearerExp     = $acct.Exp
  $script:Login         = $acct.Login
}

function Get-Bearer {
  # Refresh the short-lived Copilot token when it is close to expiring.
  if ($script:NeedsExchange) {
    if (-not $script:Bearer -or (Get-Date) -ge $script:BearerExp.AddSeconds(-60)) {
      $ex = Exchange-Token $script:OAuthToken
      if ($ex) { $script:Bearer = $ex.Token; $script:BearerExp = $ex.Exp }
    }
  }
  return $script:Bearer
}

function Save-CachedOAuth($oauth) {
  if (-not $oauth) { return }
  try {
    $dir = Split-Path $script:OAuthCachePath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $sec = ConvertTo-SecureString $oauth -AsPlainText -Force
    ConvertFrom-SecureString $sec | Set-Content -Path $script:OAuthCachePath -Encoding ASCII
  } catch {}
}

function Get-CachedOAuth {
  try {
    if (Test-Path $script:OAuthCachePath) {
      $enc = (Get-Content $script:OAuthCachePath -Raw).Trim()
      if ($enc) { $sec = ConvertTo-SecureString $enc; return [System.Net.NetworkCredential]::new('', $sec).Password }
    }
  } catch {}
  return $null
}

function Clear-CachedOAuth { Remove-Item $script:OAuthCachePath -Force -ErrorAction SilentlyContinue }

function Invoke-DeviceLogin {
  # GitHub device-code flow with the Copilot client id. Returns an OAuth token (gho_...) or $null.
  $hdr = @{ Accept = "application/json"; "Content-Type" = "application/json"; "User-Agent" = "CopilotVoice/1.0" }
  try {
    $body = @{ client_id = $script:ClientId; scope = "read:user" } | ConvertTo-Json
    $dc = Invoke-Json $script:DeviceCodeUrl $hdr 'Post' ([System.Text.Encoding]::UTF8.GetBytes($body))
  } catch { Write-Host "Could not start sign-in: $($_.Exception.Message)" -ForegroundColor Red; return $null }
  if (-not $dc -or -not $dc.user_code) { Write-Host "Could not start sign-in." -ForegroundColor Red; return $null }

  Write-Host ""
  Write-Host "  Sign in to GitHub Copilot:" -ForegroundColor Cyan
  Write-Host "    1) Open " -NoNewline -ForegroundColor White; Write-Host $dc.verification_uri -ForegroundColor White
  Write-Host "    2) Enter code: " -NoNewline -ForegroundColor White; Write-Host $dc.user_code -ForegroundColor Yellow
  Write-Host ""
  try { Set-Clipboard -Value $dc.user_code -ErrorAction SilentlyContinue; Write-Host "  (code copied to clipboard)" -ForegroundColor DarkGray } catch {}
  try { Start-Process $dc.verification_uri | Out-Null; Write-Host "  (browser opened)" -ForegroundColor DarkGray } catch {}
  Write-Host "  Waiting for authorization..." -ForegroundColor DarkGray

  $interval = [int]$dc.interval; if ($interval -lt 5) { $interval = 5 }
  $deadline = (Get-Date).AddSeconds([int]$dc.expires_in)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds $interval
    $tr = $null
    try {
      $tb = @{ client_id = $script:ClientId; device_code = $dc.device_code; grant_type = "urn:ietf:params:oauth:grant-type:device_code" } | ConvertTo-Json
      $tr = Invoke-Json $script:AccessTokenUrl $hdr 'Post' ([System.Text.Encoding]::UTF8.GetBytes($tb))
    } catch { continue }
    if ($tr.access_token) { return $tr.access_token }
    switch ($tr.error) {
      "authorization_pending" { }
      "slow_down"             { $interval += 5 }
      "expired_token"         { Write-Host "  Sign-in code expired. Please try again." -ForegroundColor Yellow; return $null }
      "access_denied"         { Write-Host "  Sign-in was canceled." -ForegroundColor Yellow; return $null }
    }
  }
  Write-Host "  Sign-in timed out." -ForegroundColor Yellow
  return $null
}

function Get-ChatModels {
  $r = Invoke-Json $script:CatalogUrl (Get-Headers (Get-Bearer))
  $chat = $r.data | Where-Object {
    $_.capabilities.type -eq 'chat' -and
    $_.model_picker_enabled -eq $true -and
    (($_.supported_endpoints -contains '/chat/completions') -or ($_.supported_endpoints -contains '/responses'))
  }
  foreach ($m in $chat) {
    $ep = if ($m.supported_endpoints -contains '/chat/completions') { 'chat' } else { 'responses' }
    $m | Add-Member -NotePropertyName _endpoint -NotePropertyValue $ep -Force
  }
  return @($chat | Sort-Object vendor, name)
}

function Select-Model($models, $current) {
  Write-Host ""
  Write-Host "==== Model Picker ====" -ForegroundColor Cyan
  for ($i = 0; $i -lt $models.Count; $i++) {
    $m = $models[$i]
    $mark = ""
    if ($m.id -eq $current) { $mark = "  <- current" }
    Write-Host ("{0,3}. {1,-22} {2,-12} {3}{4}" -f ($i + 1), $m.name, $m.vendor, $m.id, $mark)
  }
  Write-Host ""
  $sel = Read-Host "Pick a model number (Enter = keep current / default gpt-5-mini)"
  if ([string]::IsNullOrWhiteSpace($sel)) {
    if ($current) { return $current }
    $def = $models | Where-Object { $_.id -eq "gpt-5-mini" } | Select-Object -First 1
    if ($def) { return $def.id } else { return $models[0].id }
  }
  $n = 0
  if ([int]::TryParse($sel, [ref]$n) -and $n -ge 1 -and $n -le $models.Count) {
    return $models[$n - 1].id
  }
  Write-Host "Invalid choice; keeping current." -ForegroundColor Yellow
  if ($current) { return $current } else { return $models[0].id }
}

Add-Type -AssemblyName System.Speech

$script:Synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
try { $script:Synth.SelectVoice($Voice) } catch { Write-Host "Voice '$Voice' not found; using default." -ForegroundColor Yellow }

# ---------- High-accuracy voice input via Vosk (offline) ----------
$script:ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:VoskRoot    = Join-Path $env:LOCALAPPDATA "CopilotVoice"
$script:VoskModel   = Join-Path $script:VoskRoot "models\vosk-model-small-en-us-0.15"
$script:ListenPy    = Join-Path $script:ScriptDir "listen.py"
$script:ModelUrl    = "https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip"
$script:Python      = $null
$script:UseVosk     = $false
$script:RunDir      = Join-Path $script:VoskRoot "run"
$script:SttProc     = $null
$script:SttIn       = $null
$script:SttErr      = $null

function Find-Python {
  foreach ($c in @('python', 'python3', 'py')) {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if ($cmd) {
      try {
        $v = & $cmd.Source -c "import sys; print(sys.version_info[0])" 2>$null
        if ($v -eq '3') { return $cmd.Source }
      } catch {}
    }
  }
  return $null
}

function Ensure-Vosk {
  if ($NoVosk) { return $false }
  $py = Find-Python
  if (-not $py) { return $false }
  $script:Python = $py
  if (-not (Test-Path $script:ListenPy)) { return $false }

  # Are python deps importable?
  $depsOk = $false
  try {
    & $py -c "import vosk, sounddevice" 2>$null
    if ($LASTEXITCODE -eq 0) { $depsOk = $true }
  } catch {}
  if (-not $depsOk) {
    Write-Host "First-time voice setup: installing speech engine (vosk, sounddevice)..." -ForegroundColor Yellow
    try { & $py -m pip install --quiet --disable-pip-version-check vosk sounddevice 2>&1 | Out-Null } catch {}
    try { & $py -c "import vosk, sounddevice" 2>$null; if ($LASTEXITCODE -eq 0) { $depsOk = $true } } catch {}
  }
  if (-not $depsOk) { return $false }

  # Is the model present? If not, download it (~40 MB, once).
  if (-not (Test-Path $script:VoskModel)) {
    Write-Host "Downloading speech model (~40 MB, one time)..." -ForegroundColor Yellow
    try {
      $modelsDir = Split-Path $script:VoskModel -Parent
      if (-not (Test-Path $modelsDir)) { New-Item -ItemType Directory -Force -Path $modelsDir | Out-Null }
      $zip = Join-Path $modelsDir "model.zip"
      Invoke-WebRequest -Uri $script:ModelUrl -OutFile $zip -TimeoutSec 300 -UseBasicParsing
      Expand-Archive -Path $zip -DestinationPath $modelsDir -Force
      Remove-Item $zip -ErrorAction SilentlyContinue
    } catch { Write-Host "Model download failed: $($_.Exception.Message)" -ForegroundColor Yellow }
  }
  return (Test-Path $script:VoskModel)
}

function Start-SttServer {
  # Launch (once) the persistent Vosk listener that keeps the model + mic warm.
  # Returns $true when it is ready, $false on failure ($script:SttErr holds why).
  if ($script:SttProc -and -not $script:SttProc.HasExited) { return $true }
  $script:SttErr = $null
  try { if (-not (Test-Path $script:RunDir)) { New-Item -ItemType Directory -Force -Path $script:RunDir | Out-Null } } catch {}
  $readyF = Join-Path $script:RunDir "ready"
  $errF   = Join-Path $script:RunDir "error"
  Remove-Item $readyF, $errF -ErrorAction SilentlyContinue

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName               = $script:Python
  $psi.Arguments              = '"{0}" --serve "{1}" "{2}"' -f $script:ListenPy, $script:VoskModel, $script:RunDir
  $psi.UseShellExecute        = $false
  $psi.RedirectStandardInput  = $true
  $psi.CreateNoWindow         = $true
  try {
    $script:SttProc = [System.Diagnostics.Process]::Start($psi)
  } catch {
    $script:SttErr = $_.Exception.Message
    return $false
  }
  $script:SttIn = $script:SttProc.StandardInput

  $t0 = Get-Date
  while ($true) {
    if (Test-Path $readyF) { return $true }
    if (Test-Path $errF)   { $script:SttErr = (Get-Content $errF -Raw -ErrorAction SilentlyContinue); return $false }
    if ($script:SttProc.HasExited) { $script:SttErr = "listener exited during startup"; return $false }
    if (((Get-Date) - $t0).TotalSeconds -gt 30) { $script:SttErr = "listener startup timed out"; return $false }
    Start-Sleep -Milliseconds 150
  }
}

function Stop-SttServer {
  if ($script:SttProc) {
    try { if (-not $script:SttProc.HasExited) { $script:SttIn.WriteLine("QUIT"); $script:SttIn.Flush() } } catch {}
    Start-Sleep -Milliseconds 200
    try { if (-not $script:SttProc.HasExited) { $script:SttProc.Kill() } } catch {}
  }
  $script:SttProc = $null; $script:SttIn = $null
}

function Listen-Vosk {
  # Returns: [pscustomobject]@{ Text=<string|null>; Broken=<bool>; Err=<string|null> }
  if (-not (Start-SttServer)) {
    return [pscustomobject]@{ Text = $null; Broken = $true; Err = $script:SttErr }
  }

  $utt = Join-Path $script:RunDir ("utt_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
  Remove-Item $utt -ErrorAction SilentlyContinue

  # Mic is already open in the server, so the cue lines up with real listening.
  Write-Host "Listening... speak now." -ForegroundColor Green
  try { [System.Console]::Beep(880, 150) } catch {}

  try {
    $script:SttIn.WriteLine("LISTEN`t$utt"); $script:SttIn.Flush()
  } catch {
    return [pscustomobject]@{ Text = $null; Broken = $true; Err = "listener pipe closed" }
  }

  $t0 = Get-Date
  while ($true) {
    if (Test-Path $utt) { break }
    if ($script:SttProc.HasExited) { return [pscustomobject]@{ Text = $null; Broken = $true; Err = "listener stopped" } }
    if (((Get-Date) - $t0).TotalSeconds -gt 28) { return [pscustomobject]@{ Text = $null; Broken = $false; Err = $null } }
    Start-Sleep -Milliseconds 120
  }

  $text = ""
  try { $text = [System.IO.File]::ReadAllText($utt) } catch {}
  Remove-Item $utt -ErrorAction SilentlyContinue
  if ($text) { $text = $text.Trim() }
  return [pscustomobject]@{ Text = $text; Broken = $false; Err = $null }
}

function Init-Reco {
  try {
    $r = New-Object System.Speech.Recognition.SpeechRecognitionEngine
    $r.SetInputToDefaultAudioDevice()
    $r.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar))
    $r.InitialSilenceTimeout = [TimeSpan]::FromSeconds(8)
    $r.BabbleTimeout         = [TimeSpan]::FromSeconds(2)
    $r.EndSilenceTimeout     = [TimeSpan]::FromSeconds(1)
    return $r
  } catch {
    return $null
  }
}

function Speak($text) {
  if (-not $text) { return }
  $spoken = $text
  if ($spoken -match '```') { $spoken = ($spoken -replace '(?s)```.*?```', ' I have shown the code on screen. ') }
  $spoken = ($spoken -replace '[*_`#>|]', '').Trim()
  if ($spoken.Length -gt 800) { $spoken = $spoken.Substring(0, 800) + " ... see the screen for the rest." }
  try { $script:Synth.Speak($spoken) } catch {}
}

function Listen($reco) {
  if ($script:UseVosk) { return (Listen-Vosk) }
  if (-not $reco) { return [pscustomobject]@{ Text = $null; Broken = $true; Err = 'no recognizer' } }
  Write-Host "Listening... speak now." -ForegroundColor Green
  try { [System.Console]::Beep(880, 150) } catch {}
  try {
    $res = $reco.Recognize()
    if ($res -and $res.Text) { return [pscustomobject]@{ Text = $res.Text; Broken = $false; Err = $null } }
  } catch { return [pscustomobject]@{ Text = $null; Broken = $true; Err = $_.Exception.Message } }
  return [pscustomobject]@{ Text = $null; Broken = $false; Err = $null }
}

function Invoke-CopilotApi($url, $payloadObj) {
  $payload = $payloadObj | ConvertTo-Json -Depth 8
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
  for ($attempt = 0; $attempt -lt 2; $attempt++) {
    try {
      $wr = Invoke-WebRequest -Uri $url -Method Post -Body $bytes -Headers (Get-Headers (Get-Bearer)) -TimeoutSec 180 -UseBasicParsing
      $json = [System.Text.Encoding]::UTF8.GetString($wr.RawContentStream.ToArray())
      return ($json | ConvertFrom-Json)
    } catch {
      $code = $null
      try { $code = [int]$_.Exception.Response.StatusCode } catch {}
      # Token may have expired mid-session: force a refresh and retry once.
      if ($code -eq 401 -and $attempt -eq 0 -and $script:NeedsExchange) { $script:Bearer = $null; continue }
      throw
    }
  }
}

function Invoke-Chat($model, $messages) {
  $ep = 'chat'
  if ($script:ModelEndpoints -and $script:ModelEndpoints.ContainsKey($model)) { $ep = $script:ModelEndpoints[$model] }
  if ($ep -eq 'responses') {
    $resp = Invoke-CopilotApi $script:ResponsesUrl @{ model = $model; input = [object[]]$messages }
    if ($resp.output_text) { return $resp.output_text }
    $sb = New-Object System.Text.StringBuilder
    foreach ($item in @($resp.output)) {
      foreach ($c in @($item.content)) {
        if ($c.type -eq 'output_text' -and $c.text) { [void]$sb.Append($c.text) }
      }
    }
    return $sb.ToString()
  }
  $resp = Invoke-CopilotApi $script:ChatUrl @{ model = $model; messages = [object[]]$messages }
  return $resp.choices[0].message.content
}

function Main {
  Write-Host "===========================================" -ForegroundColor Cyan
  Write-Host "       Copilot Voice  (GitHub Copilot)      " -ForegroundColor Cyan
  Write-Host "===========================================" -ForegroundColor Cyan

  Write-Host "Checking your GitHub Copilot sign-in..." -ForegroundColor DarkGray
  $acct = Resolve-Account
  if (-not $acct) {
    # Not signed in. Offer device-code sign-in with the user's own Copilot account.
    Write-Host ""
    Write-Host "You're not signed in to GitHub Copilot." -ForegroundColor Yellow
    Write-Host "Copilot Voice uses YOUR GitHub account and Copilot subscription." -ForegroundColor Gray
    $ans = Read-Host "Press ENTER to sign in now, or type N to skip"
    if ($ans -notmatch '^[Nn]') {
      $newTok = Invoke-DeviceLogin
      if ($newTok) {
        $acct = Try-Account $newTok
        if ($acct) {
          Save-CachedOAuth $newTok
        } else {
          Write-Host ""
          Write-Host "Signed in, but this account has no active Copilot subscription." -ForegroundColor Red
          Write-Host "Get Copilot at https://github.com/features/copilot then run this again." -ForegroundColor Gray
          Read-Host "Press ENTER to close" | Out-Null
          return
        }
      }
    }
  }
  if (-not $acct) {
    Write-Host ""
    Write-Host "Please sign in to use Copilot Voice. Run it again and choose sign in." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press ENTER to close" | Out-Null
    return
  }
  Set-Account $acct
  if ($script:Login) {
    Write-Host "Signed in as @$($script:Login) - using your Copilot subscription." -ForegroundColor Green
  } else {
    Write-Host "Signed in - using your Copilot subscription." -ForegroundColor Green
  }

  Write-Host "Loading available models..." -ForegroundColor DarkGray
  $models = Get-ChatModels
  if (-not $models -or $models.Count -eq 0) { Write-Host "No chat models available for this account." -ForegroundColor Red; return }
  $script:ModelEndpoints = @{}
  foreach ($m in $models) { $script:ModelEndpoints[$m.id] = $m._endpoint }

  $model = $Model
  if (-not $model) { $model = Select-Model $models $null }

  Write-Host "Preparing microphone..." -ForegroundColor DarkGray
  $script:UseVosk = Ensure-Vosk
  $reco = $null
  if ($script:UseVosk) {
    # Warm up the persistent listener once (loads the model + opens the mic),
    # so each later voice turn starts instantly.
    if (Start-SttServer) {
      Write-Host "Voice input: Vosk (high accuracy, offline)." -ForegroundColor Green
    } else {
      $script:UseVosk = $false
      Write-Host "Vosk listener could not start ($script:SttErr); using basic recognizer." -ForegroundColor Yellow
    }
  }
  if (-not $script:UseVosk) { $reco = Init-Reco }
  if ($script:UseVosk) {
    # already reported above
  } elseif ($reco) {
    Write-Host "Voice input: Windows recognizer (basic). Typing recommended for accuracy." -ForegroundColor Yellow
  } else {
    Write-Host "Voice input unavailable - type your messages." -ForegroundColor Yellow
  }
  $script:VoiceOk = ($script:UseVosk -or [bool]$reco)

  $sys = @{ role = "system"; content = @"
You are Copilot Voice, a friendly, helpful AI assistant powered by GitHub Copilot.
You are spoken to through a microphone and your answers are read aloud by text-to-speech,
so keep replies clear and reasonably concise unless the user asks for detail.
You can help with coding, explanations, planning, brainstorming, math, and general questions.
When you must share code, keep it short; it is shown on the user's screen.
"@ }

  $messages = New-Object System.Collections.Generic.List[object]
  $messages.Add($sys) | Out-Null

  Write-Host ""
  Write-Host "Ready. Model: $model" -ForegroundColor Green
  if ($script:VoiceOk) {
    Write-Host "Type a message and press ENTER, or press ENTER on an empty line to TALK with your mic." -ForegroundColor DarkGray
  } else {
    Write-Host "Type a message and press ENTER." -ForegroundColor DarkGray
  }
  Write-Host "Commands (say or type): 'switch model', 'new chat', 'sign out', 'exit'." -ForegroundColor DarkGray
  Speak "Copilot voice is ready. How can I help you?"

  while ($true) {
    Write-Host ""
    $typed = Read-Host "You"
    $text = $null
    if ([string]::IsNullOrWhiteSpace($typed)) {
      # Non-interactive / piped stdin: an empty line means end-of-input, not "talk".
      if ([Console]::IsInputRedirected) { break }
      if (-not $script:VoiceOk) {
        Write-Host "(voice input is off - please type your message)" -ForegroundColor DarkGray
        continue
      }
      $r = Listen $reco
      if ($r.Broken) {
        $script:VoiceOk = $false
        Write-Host "Microphone/voice engine unavailable - switching to typing only." -ForegroundColor Yellow
        if ($r.Err) { Write-Host "  ($($r.Err))" -ForegroundColor DarkGray }
        continue
      }
      if ($r.Text) {
        $text = $r.Text
        Write-Host "You (voice): $text" -ForegroundColor White
      } else {
        Write-Host "(didn't catch that - press ENTER to try again, or just type)" -ForegroundColor DarkGray
        continue
      }
    } else {
      $text = $typed
    }

    $cmd = $text.ToLower().Trim().TrimEnd('.', '!', '?')
    if ($cmd -in @('exit', 'quit', 'goodbye', 'bye', 'stop listening', 'close')) { Speak "Goodbye!"; break }
    if ($cmd -in @('sign out', 'signout', 'log out', 'logout', 'switch account', 'switch user')) {
      Clear-CachedOAuth
      Write-Host "Signed out. Close this window and run Copilot Voice again to sign in with a different account." -ForegroundColor Green
      Speak "You are signed out. Run Copilot Voice again to sign in."
      break
    }
    if ($cmd -in @('switch model', 'change model', 'model picker', 'pick model', 'select model')) {
      $model = Select-Model $models $model
      Write-Host "Now using: $model" -ForegroundColor Green
      Speak "Switched model."
      continue
    }
    if ($cmd -in @('new chat', 'new conversation', 'clear', 'reset', 'start over')) {
      $messages.Clear(); $messages.Add($sys) | Out-Null
      Write-Host "Conversation cleared." -ForegroundColor Green
      Speak "Okay, starting a fresh conversation."
      continue
    }

    $messages.Add(@{ role = "user"; content = $text }) | Out-Null
    Write-Host "Copilot is thinking..." -ForegroundColor DarkGray
    $reply = $null
    try { $reply = Invoke-Chat $model $messages }
    catch {
      Write-Host "API error: $($_.Exception.Message)" -ForegroundColor Red
      Speak "Sorry, I hit an error reaching the model."
    }

    if ($reply) {
      $messages.Add(@{ role = "assistant"; content = $reply }) | Out-Null
      if ($messages.Count -gt 25) {
        $keep = New-Object System.Collections.Generic.List[object]
        $keep.Add($messages[0]) | Out-Null
        for ($i = $messages.Count - 24; $i -lt $messages.Count; $i++) { $keep.Add($messages[$i]) | Out-Null }
        $messages = $keep
      }
      Write-Host ""
      Write-Host "Copilot> " -ForegroundColor Cyan -NoNewline
      Write-Host $reply
      Speak $reply
    }
  }

  Write-Host "Session ended." -ForegroundColor Green
}

try { Main } finally { Stop-SttServer }
