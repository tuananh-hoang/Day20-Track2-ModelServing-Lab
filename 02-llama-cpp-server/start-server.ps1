# Launch llama-server (via llama-cpp-python) reading models/active.json.
# Windows PowerShell 7+.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$model   = python -c 'import json; print(json.load(open("models/active.json"))["primary_model"])'
$threads = python -c 'import json; hw=json.load(open("hardware.json")); print(hw["cpu"].get("cores_physical") or 4)'
$gpu     = if ($env:LAB_N_GPU_LAYERS) { $env:LAB_N_GPU_LAYERS } else { '99' }
$ctx     = if ($env:LAB_N_CTX) { $env:LAB_N_CTX } else { '2048' }

Write-Host "==> Starting llama-server" -ForegroundColor Cyan
Write-Host "    model     : $model"
Write-Host "    threads   : $threads"
Write-Host "    gpu_layers: $gpu"
Write-Host "    ctx       : $ctx"
Write-Host "    listening : http://0.0.0.0:8080"
Write-Host ""

python -c "import uvicorn" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: missing server dependency 'uvicorn'." -ForegroundColor Red
    Write-Host "Run: pip install -r requirements.txt; pip install 'llama-cpp-python[server]'" -ForegroundColor Yellow
    exit 1
}

python -m llama_cpp.server `
    --model "$model" `
    --host 0.0.0.0 --port 8080 `
    --n_threads $threads `
    --n_gpu_layers $gpu `
    --n_ctx $ctx
