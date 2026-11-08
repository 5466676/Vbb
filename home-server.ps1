# Home server for حرب العقول on Windows: one process, one SQLite file, exposed with Tailscale Funnel.
# The same as home-server.sh (Mac/Linux).
#
#   powershell -ExecutionPolicy Bypass -File home-server.ps1 start    # install (first time), migrate, seed, start, open the funnel
#   powershell -ExecutionPolicy Bypass -File home-server.ps1 stop
#   powershell -ExecutionPolicy Bypass -File home-server.ps1 status
#   powershell -ExecutionPolicy Bypass -File home-server.ps1 logs
#
# Or double-click start-server.bat / stop-server.bat.
# Settings live in backend\data\home.env (created on first start, never committed).
param([string]$Command = "")
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Backend = Join-Path $Root "backend"
$Data = Join-Path $Backend "data"
$Venv = Join-Path $Backend ".venv"
$VenvPy = Join-Path $Venv "Scripts\python.exe"
$Port = if ($env:HARB_PORT) { $env:HARB_PORT } else { "8080" }
$FunnelPort = if ($env:HARB_FUNNEL_PORT) { $env:HARB_FUNNEL_PORT } else { "443" }  # 443, 8443 or 10000
$PidFile = Join-Path $Data "server.pid"
$Log = Join-Path $Data "server.log"
$ErrLog = Join-Path $Data "server.err.log"

function Say($msg) { Write-Host $msg -ForegroundColor Cyan }

function Find-Python {
  # returns the command and its leading arguments, e.g. @("py", "-3.12")
  foreach ($c in @(@("py", "-3.12"), @("py", "-3"), @("python"))) {
    if (Get-Command $c[0] -ErrorAction SilentlyContinue) {
      $rest = @($c | Select-Object -Skip 1)
      $v = & $c[0] @rest -c "import sys;print(sys.version_info >= (3, 12))" 2>$null
      if ($v -eq "True") { return ,$c }
    }
  }
  throw "Python 3.12 or newer is needed: install it from python.org (tick 'Add python.exe to PATH')."
}

function Test-Running {
  if (-not (Test-Path $PidFile)) { return $false }
  $id = Get-Content $PidFile
  return [bool](Get-Process -Id $id -ErrorAction SilentlyContinue)
}

function Test-Healthy {
  try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 "http://127.0.0.1:$Port/health" | Out-Null; return $true }
  catch { return $false }
}

function Setup {
  New-Item -ItemType Directory -Force $Data | Out-Null
  if (-not (Test-Path $VenvPy)) {
    Say "Creating the Python environment (first start only)..."
    $py = Find-Python
    $rest = @($py | Select-Object -Skip 1)
    & $py[0] @rest -m venv $Venv
  }
  # reinstall when pyproject.toml changed
  $stamp = Join-Path $Venv ".installed"
  $sum = (Get-FileHash (Join-Path $Backend "pyproject.toml")).Hash
  if (-not (Test-Path $stamp) -or (Get-Content $stamp) -ne $sum) {
    Say "Installing the server..."
    & $VenvPy -m pip install -q --upgrade pip
    & $VenvPy -m pip install -q -e "$Backend[home]"
    Set-Content $stamp $sum
  }
  $envFile = Join-Path $Data "home.env"
  if (-not (Test-Path $envFile)) {
    $jwt = & $VenvPy -c "import secrets;print(secrets.token_urlsafe(48))"
    $admin = & $VenvPy -c "import secrets;print(secrets.token_urlsafe(24))"
    $db = (Join-Path $Data "harb.db") -replace "\\", "/"
    @(
      "HARB_ENV=home",
      "HARB_DATABASE_URL=sqlite+aiosqlite:///$db",
      "HARB_REDIS_URL=memory://",
      "HARB_JWT_SECRET=$jwt",
      "HARB_ADMIN_KEY=$admin"
    ) | Set-Content -Encoding ascii $envFile
    Say "Created $envFile (keep it private: it holds the admin key)."
  }
}

function Load-Env {
  foreach ($line in Get-Content (Join-Path $Data "home.env")) {
    if ($line -match "^\s*([A-Z_]+)=(.*)$") { Set-Item "env:$($Matches[1])" $Matches[2] }
  }
}

function Start-Server {
  if (Test-Running) { Say "Already running (pid $(Get-Content $PidFile))." }
  else {
    Setup
    Load-Env
    Push-Location $Backend
    try {
      & (Join-Path $Venv "Scripts\alembic.exe") upgrade head | Out-Null
      & $VenvPy -m app.questions.seed
      # one worker only: rooms live in this process (in-memory Redis)
      $p = Start-Process -PassThru -WindowStyle Hidden -FilePath (Join-Path $Venv "Scripts\uvicorn.exe") `
        -ArgumentList "app.main:app", "--host", "127.0.0.1", "--port", $Port, "--workers", "1", "--no-access-log" `
        -RedirectStandardOutput $Log -RedirectStandardError $ErrLog
      Set-Content $PidFile $p.Id
    } finally { Pop-Location }
    for ($i = 0; $i -lt 50 -and -not (Test-Healthy); $i++) { Start-Sleep -Milliseconds 200 }
    if (-not (Test-Healthy)) {
      Say "The server did not start. Last log lines:"
      Get-Content $ErrLog -Tail 20
      exit 1
    }
    Say "Server up on http://127.0.0.1:$Port"
  }
  if (Get-Command tailscale -ErrorAction SilentlyContinue) {
    tailscale funnel --bg --https=$FunnelPort "http://localhost:$Port" | Out-Null
    Say "Funnel open:"
    tailscale funnel status
  } else {
    Say "tailscale not found: the server is local only (install Tailscale and enable Funnel)."
  }
}

function Stop-Server {
  if (Get-Command tailscale -ErrorAction SilentlyContinue) {
    tailscale funnel --https=$FunnelPort off 2>$null | Out-Null
    Say "Funnel closed."
  }
  if (Test-Running) {
    Stop-Process -Id (Get-Content $PidFile) -Force
    Say "Server stopped."
  } else { Say "Server was not running." }
  Remove-Item -ErrorAction SilentlyContinue $PidFile
}

function Show-Status {
  if ((Test-Running) -and (Test-Healthy)) { Say "Server: running (pid $(Get-Content $PidFile)) on port $Port" }
  else { Say "Server: stopped" }
  if (Get-Command tailscale -ErrorAction SilentlyContinue) { tailscale funnel status }
}

switch ($Command) {
  "start" { Start-Server }
  "stop" { Stop-Server }
  "restart" { Stop-Server; Start-Server }
  "status" { Show-Status }
  "logs" { Get-Content $ErrLog -Tail 40 -Wait }
  default { Write-Host "usage: home-server.ps1 start|stop|restart|status|logs"; exit 2 }
}
