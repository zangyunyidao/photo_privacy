$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$moon = Join-Path $env:USERPROFILE '.moon\bin\moon.exe'
$dist = Join-Path $projectRoot 'web\dist'
$site = Join-Path $projectRoot 'web\site'
$artifact = Join-Path $projectRoot '_build\wasm\release\build\web\wasm\wasm.wasm'

Push-Location $projectRoot
try {
  & $moon build web/wasm --target wasm --release
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  $resolvedRoot = [IO.Path]::GetFullPath($projectRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
  $resolvedDist = [IO.Path]::GetFullPath($dist)
  $expectedPrefix = $resolvedRoot + [IO.Path]::DirectorySeparatorChar
  if (-not $resolvedDist.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
      (Split-Path -Leaf $resolvedDist) -ne 'dist') {
    throw "Refusing to replace unexpected output directory: $resolvedDist"
  }
  if (Test-Path -LiteralPath $resolvedDist) {
    Remove-Item -LiteralPath $resolvedDist -Recurse -Force
  }
  New-Item -ItemType Directory -Path $resolvedDist | Out-Null
  Copy-Item -Path (Join-Path $site '*') -Destination $resolvedDist -Recurse
  Copy-Item -LiteralPath $artifact -Destination (Join-Path $resolvedDist 'photo_privacy.wasm')
  Write-Host "Web build ready: $resolvedDist"
} finally {
  Pop-Location
}
