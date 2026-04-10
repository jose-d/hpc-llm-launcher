#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${VENV_DIR:-$ROOT_DIR/.venv}"

#VLLM_VERSION="${VLLM_VERSION:-0.19.0}"
export VLLM_VERSION=$(curl -s https://api.github.com/repos/vllm-project/vllm/releases/latest | jq -r .tag_name | sed 's/^v//')

VLLM_SPEC="${VLLM_SPEC:-vllm==${VLLM_VERSION}}"
TORCH_SPEC="${TORCH_SPEC:-torch==2.10.0}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
UV_BIN="${UV_BIN:-uv}"
GCC_MODULE_NAME="${GCC_MODULE_NAME:-GCC/15.2.0}"
CUDA_MODULE_NAME="${CUDA_MODULE_NAME:-CUDA/13.0.2}"
PYTORCH_EXTRA_INDEX_URL="${PYTORCH_EXTRA_INDEX_URL:-https://download.pytorch.org/whl/cu130}"
VLLM_EXTRA_INDEX_URL="${VLLM_EXTRA_INDEX_URL:-https://wheels.vllm.ai/${VLLM_VERSION}/cu130}"

if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT_DIR/.env"
fi

if [[ "${1:-}" == "--cleanup" ]]; then
  rm -rf "$VENV_DIR"
  echo "Removed: $VENV_DIR"
  exit 0
fi

if [[ -n "${1:-}" ]]; then
  echo "ERROR: unknown argument: $1" >&2
  echo "Use --cleanup to remove the local .venv." >&2
  exit 1
fi

ensure_module_command() {
  if type module >/dev/null 2>&1; then
    return 0
  fi
  if [[ -f /etc/profile.d/z00_lmod.sh ]]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/z00_lmod.sh
  elif [[ -f /etc/profile.d/modules.sh ]]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/modules.sh
  elif [[ -f /usr/share/lmod/lmod/init/bash ]]; then
    # shellcheck disable=SC1091
    source /usr/share/lmod/lmod/init/bash
  fi
  type module >/dev/null 2>&1
}

echo "Loading modules: $GCC_MODULE_NAME $CUDA_MODULE_NAME"
ensure_module_command
module load "$GCC_MODULE_NAME" "$CUDA_MODULE_NAME"

command -v "$PYTHON_BIN" >/dev/null 2>&1 || { echo "ERROR: python not found: $PYTHON_BIN" >&2; exit 1; }
command -v "$UV_BIN" >/dev/null 2>&1 || { echo "ERROR: uv not found: $UV_BIN" >&2; exit 1; }
command -v gcc >/dev/null 2>&1 || { echo "ERROR: gcc not found after module load" >&2; exit 1; }
command -v g++ >/dev/null 2>&1 || { echo "ERROR: g++ not found after module load" >&2; exit 1; }
command -v nvcc >/dev/null 2>&1 || { echo "ERROR: nvcc not found after module load" >&2; exit 1; }

export CC="$(command -v gcc)"
export CXX="$(command -v g++)"
export CUDAHOSTCXX="$CXX"
export CUDA_HOME="$(cd "$(dirname "$(command -v nvcc)")/.." && pwd)"
export VLLM_PYTHON_EXECUTABLE="$VENV_DIR/bin/python"

echo "Using CC: $CC"
echo "Using CXX: $CXX"
echo "Using CUDA_HOME: $CUDA_HOME"
echo "Using Python: $(command -v "$PYTHON_BIN")"
echo "Using uv: $(command -v "$UV_BIN")"

echo "Installing vllm: $VLLM_SPEC"
"$UV_BIN" pip install vllm --torch-backend=auto

cat <<MSG
Install complete.

Created:
- $VENV_DIR

Loaded modules:
- $GCC_MODULE_NAME
- $CUDA_MODULE_NAME
MSG
