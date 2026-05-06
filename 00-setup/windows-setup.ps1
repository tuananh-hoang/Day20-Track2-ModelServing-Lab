# Day 20 lab setup (Windows). Requires PowerShell 7+ (`pwsh`).
# Two supported paths:
#   1. Native Windows (CPU only, prebuilt llama-cpp-python wheel)
#   2. WSL2 — recommended if you have an NVIDIA GPU; run linux-setup.sh inside WSL.
#
# Run as: pwsh -ExecutionPolicy Bypass -File 00-setup\windows-setup.ps1
$ErrorActionPreference = 'Stop'

Set-Location (Join-Path $PSScriptRoot '..')
$LabRoot = (Get-Location).Path

Write-Host "==> Day 20 lab setup (Windows)" -ForegroundColor Cyan
Write-Host "    repo: $LabRoot"

# 1. Python check (3.10–3.12 supported)
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Host "ERROR: Python 3.10+ not found. Install from https://www.python.org/downloads/" -ForegroundColor Red
    exit 1
}
$pyVer = (& python --version) 2>&1
Write-Host "    Python: $pyVer"

# 2. virtualenv
if (-not (Test-Path '.venv')) {
    Write-Host "==> Creating .venv"
    python -m venv .venv
}
& .\.venv\Scripts\Activate.ps1

Write-Host "==> Upgrading pip"
python -m pip install --upgrade pip wheel | Out-Null

Write-Host "==> Installing Python deps from requirements.txt"
pip install -r requirements.txt

# 3. llama-cpp-python — prefer CUDA when NVIDIA tooling is visible.
#    You can still force paths via $env:LLAMA_CUDA / $env:LLAMA_VULKAN.
$useCuda = $env:LLAMA_CUDA -eq '1' -or ((Get-Command nvidia-smi -ErrorAction SilentlyContinue) -ne $null)
if ($env:LLAMA_VULKAN -eq '1') {
    Write-Host "==> Building llama-cpp-python with Vulkan (requires Vulkan SDK + cmake)"
    $env:CMAKE_ARGS = '-DGGML_VULKAN=on'
    pip install --upgrade --force-reinstall --no-cache-dir 'llama-cpp-python[server]'
} elseif ($useCuda) {
    Write-Host "==> Building llama-cpp-python with CUDA (requires CUDA Toolkit + cmake)"
    $env:CMAKE_ARGS = '-DGGML_CUDA=on'
    pip install --upgrade --force-reinstall --no-cache-dir 'llama-cpp-python[server]'
} else {
    Write-Host "==> Installing prebuilt llama-cpp-python (CPU)"
    pip install --upgrade 'llama-cpp-python[server]'
}

# 4. Probe + download model
python .\00-setup\detect-hardware.py
python .\00-setup\download-model.py

Write-Host ""
Write-Host "==> Setup complete. Activate the venv next time with:" -ForegroundColor Green
Write-Host "    .\.venv\Scripts\Activate.ps1"
Write-Host ""
Write-Host "==> If you have an NVIDIA GPU, consider WSL2 path instead:"
Write-Host "    wsl --install -d Ubuntu-22.04"
Write-Host "    Then inside WSL: bash 00-setup/linux-setup.sh"
Write-Host ""
Write-Host "==> Next: 01-llama-cpp-quickstart\README.md"
