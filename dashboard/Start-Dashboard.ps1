param([int]$Port = 8766)
$ErrorActionPreference = 'Stop'
$repoPath = Split-Path $PSScriptRoot -Parent
Push-Location $repoPath
try {
    node dashboard/scripts/build.mjs
    if ($LASTEXITCODE) { throw 'Dashboard build failed' }
    Set-Location backend
    $env:AB_ENVIRONMENT = 'development'
    $env:AB_DASHBOARD_DEV_AUTH = 'true'
    $env:AB_DATABASE_URL = 'sqlite:///./dashboard.db'
    $env:AB_DASHBOARD_API_BASE_URL = ''
    & .venv/Scripts/python.exe -m alembic upgrade head
    if ($LASTEXITCODE) { throw 'Database migration failed' }
    & .venv/Scripts/python.exe -m app.dashboard_seed
    if ($LASTEXITCODE) { throw 'Development seed failed' }
    Write-Host "Open http://127.0.0.1:$Port/merchant/"
    & .venv/Scripts/python.exe -m uvicorn app.main:app --host 127.0.0.1 --port $Port
} finally { Pop-Location }
