param(
  [ValidateRange(1, 65535)]
  [int]$Port = 8000,
  [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $PSScriptRoot 'build-web.ps1'
$dist = Join-Path $projectRoot 'web\dist'

function Test-TcpPortAvailable([int]$Candidate) {
  $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Candidate)
  try {
    $listener.Start()
    return $true
  } catch {
    return $false
  } finally {
    $listener.Stop()
  }
}

Write-Host 'Building PhotoPrivacy WebAssembly application...'
& $buildScript
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$python = Get-Command python -ErrorAction SilentlyContinue
$pythonArguments = @()
if (-not $python) {
  $python = Get-Command py -ErrorAction SilentlyContinue
  $pythonArguments = @('-3')
}
if (-not $python) {
  throw 'Python was not found. Install Python or make it available on PATH.'
}

$selectedPort = $Port
while ($selectedPort -le [Math]::Min($Port + 20, 65535) -and
  -not (Test-TcpPortAvailable $selectedPort)) {
  $selectedPort += 1
}
if ($selectedPort -gt [Math]::Min($Port + 20, 65535)) {
  throw "No available local port was found from $Port through $($Port + 20)."
}

$url = "http://127.0.0.1:$selectedPort/"
$quotedDist = '"' + $dist + '"'
$pythonArguments += @(
  '-m',
  'http.server',
  $selectedPort.ToString(),
  '--bind',
  '127.0.0.1',
  '--directory',
  $quotedDist
)

$server = Start-Process `
  -FilePath $python.Source `
  -ArgumentList $pythonArguments `
  -WindowStyle Hidden `
  -PassThru

try {
  $ready = $false
  for ($attempt = 0; $attempt -lt 50; $attempt += 1) {
    if ($server.HasExited) {
      throw "The local Web server exited with code $($server.ExitCode)."
    }
    try {
      $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 1
      if ($response.StatusCode -eq 200) {
        $ready = $true
        break
      }
    } catch {
      Start-Sleep -Milliseconds 100
    }
  }
  if (-not $ready) {
    throw 'The local Web server did not become ready in time.'
  }

  Write-Host "PhotoPrivacy is running at $url"
  Write-Host 'Use Ctrl+C or stop the VS Code task to close the local server.'
  if (-not $NoBrowser) {
    Start-Process -FilePath $url
  }
  Wait-Process -Id $server.Id
} finally {
  if (-not $server.HasExited) {
    Stop-Process -Id $server.Id
  }
}
