#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${VENV_DIR:-$ROOT_DIR/.venv}"
VLLM_SPEC="${VLLM_SPEC:-vllm}"
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
CUDA_HOME="${CUDA_HOME:-}"

detect_cuda_home() {
  if [[ -n "$CUDA_HOME" && -d "$CUDA_HOME" ]]; then
    printf '%s\n' "$CUDA_HOME"
    return 0
  fi

  if command -v nvcc >/dev/null 2>&1; then
    local nvcc_path
    nvcc_path="$(command -v nvcc)"
    if [[ "$nvcc_path" == */bin/nvcc ]]; then
      printf '%s\n' "${nvcc_path%/bin/nvcc}"
      return 0
    fi
  fi

  for candidate in \
    /usr/local/cuda \
    /usr/local/cuda-12 \
    /usr/local/cuda-12.* \
    /usr/local/cuda-13 \
    /usr/local/cuda-13.* \
    /opt/cuda \
    /usr/lib/cuda; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

if ! command -v uv >/dev/null 2>&1; then
  cat <<'MSG' >&2
ERROR: uv is not installed or not on PATH.
Install uv first, then rerun this script.
MSG
  exit 1
fi

mkdir -p "$ROOT_DIR"

if [[ -z "$CUDA_HOME" ]]; then
  if CUDA_HOME="$(detect_cuda_home)"; then
    export CUDA_HOME
  fi
fi

if [[ -z "${CUDA_HOME:-}" ]]; then
  cat <<'MSG' >&2
ERROR: CUDA_HOME is not set and CUDA could not be autodetected.
Install or load a CUDA toolkit before running this script, or set CUDA_HOME explicitly.
MSG
  exit 1
fi

export CUDA_HOME

uv python install "$PYTHON_VERSION" >/dev/null 2>&1 || true
uv venv --python "$PYTHON_VERSION" "$VENV_DIR"
uv pip install --python "$VENV_DIR/bin/python" --upgrade pip
uv pip install --python "$VENV_DIR/bin/python" "$VLLM_SPEC"

cat <<MSG
llm_launcher bootstrap complete.

Created:
- $VENV_DIR

Installed:
- vllm from spec: $VLLM_SPEC
- CUDA_HOME: $CUDA_HOME

Next steps:
- copy .env.example to .env
- adjust MODEL_ID / GPU settings for the cluster
- submit scripts/sbatch-vllm-serve.sh with sbatch
MSG
