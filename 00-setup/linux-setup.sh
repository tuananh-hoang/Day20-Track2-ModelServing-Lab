#!/usr/bin/env bash
# Linux setup for Day 20 lab. Tested on Ubuntu 22.04 / 24.04 and Fedora 40.
# Installs Python deps + llama.cpp prebuilt binary path. Skips Docker — install it
# yourself via your distro's docs (rootless is fine).
set -euo pipefail

cd "$(dirname "$0")/.."
LAB_ROOT="$(pwd)"

echo "==> Day 20 lab setup (Linux)"
echo "    repo: $LAB_ROOT"

# 1. Python virtualenv
if [[ ! -d .venv ]]; then
  echo "==> Creating .venv"
  python3 -m venv .venv
fi
# shellcheck source=/dev/null
source .venv/bin/activate

echo "==> Upgrading pip"
python -m pip install --upgrade pip wheel >/dev/null

echo "==> Installing Python deps from requirements.txt"
pip install -r requirements.txt

# 2. llama-cpp-python (prefer CUDA/Vulkan when the toolchain is visible)
LLAMA_BACKEND="cpu"
if [[ "${LLAMA_CUDA:-0}" == "1" ]]; then
  LLAMA_BACKEND="cuda"
elif [[ "${LLAMA_VULKAN:-0}" == "1" ]]; then
  LLAMA_BACKEND="vulkan"
elif command -v nvidia-smi >/dev/null 2>&1; then
  LLAMA_BACKEND="cuda"
elif command -v vulkaninfo >/dev/null 2>&1 || command -v vulkaninfoSDK >/dev/null 2>&1; then
  LLAMA_BACKEND="vulkan"
fi

if [[ "$LLAMA_BACKEND" == "cuda" ]]; then
  echo "==> Building llama-cpp-python with CUDA support (GGML_CUDA=1)"
  CMAKE_ARGS="-DGGML_CUDA=on" pip install --upgrade --force-reinstall --no-cache-dir 'llama-cpp-python[server]'
elif [[ "$LLAMA_BACKEND" == "vulkan" ]]; then
  echo "==> Building llama-cpp-python with Vulkan support"
  CMAKE_ARGS="-DGGML_VULKAN=on" pip install --upgrade --force-reinstall --no-cache-dir 'llama-cpp-python[server]'
else
  echo "==> Installing prebuilt llama-cpp-python (CPU)"
  pip install --upgrade 'llama-cpp-python[server]'
fi

# 3. Probe hardware (writes hardware.json)
echo "==> Probing hardware"
python 00-setup/detect-hardware.py

# 4. Pull the recommended GGUF model
python 00-setup/download-model.py

echo
echo "==> Setup complete. Activate with: source .venv/bin/activate"
echo "==> Then proceed to: 01-llama-cpp-quickstart/README.md"
