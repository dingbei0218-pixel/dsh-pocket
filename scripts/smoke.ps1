param([int]$Port = 18081)

# End-to-end smoke test on Windows: mock DeepSeek SSE -> dsh CLI -> tool call -> answer.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $root ".tooling\smoke-run"
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$work\ws", "$work\sessions" | Out-Null
Set-Content -Path "$work\ws\hello.txt" -Value "hello from mock" -Encoding utf8

$mock = Start-Process node -ArgumentList @("$PSScriptRoot\mock-deepseek.mjs", "$Port") -PassThru -NoNewWindow
try {
    Start-Sleep -Seconds 1
    Push-Location $root
    $env:DEEPSEEK_API_KEY = "test"
    & swift run dsh run "read hello.txt and tell me what it says" -C "$work\ws" --base-url "http://127.0.0.1:$Port" --preset danger --root "$work\sessions"
    Write-Host "`n--- sessions ---"
    & swift run dsh sessions --root "$work\sessions"
    Pop-Location
}
finally {
    if (-not $mock.HasExited) { Stop-Process -Id $mock.Id -Force }
}
