#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${VENV_DIR:-$ROOT_DIR/.venv}"
VLLM_SPEC="${VLLM_SPEC:-vllm}"
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
CUDA_HOME="${CUDA_HOME:-}"
GCC_TOOLSET_ENABLE="${GCC_TOOLSET_ENABLE:-}"

detect_gcc_toolset_enable() {
  if [[ -n "$GCC_TOOLSET_ENABLE" && -f "$GCC_TOOLSET_ENABLE" ]]; then
    printf '%s\n' "$GCC_TOOLSET_ENABLE"
    return 0
  fi

  local best_enable=""
  local best_version=0
  local candidate
  for candidate in /opt/rh/gcc-toolset-*/enable; do
    [[ -e "$candidate" ]] || continue
    local candidate_version
    candidate_version="${candidate##*/gcc-toolset-}"
    candidate_version="${candidate_version%/enable}"
    candidate_version="${candidate_version%%.*}"
    if [[ "$candidate_version" =~ ^[0-9]+$ ]] && (( candidate_version > best_version )); then
      best_enable="$candidate"
      best_version="$candidate_version"
    fi
  done

  if [[ -n "$best_enable" ]]; then
    printf '%s\n' "$best_enable"
    return 0
  fi

  return 1
}

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

if [[ -z "$GCC_TOOLSET_ENABLE" ]]; then
  if GCC_TOOLSET_ENABLE="$(detect_gcc_toolset_enable)"; then
    # shellcheck disable=SC1090
    source "$GCC_TOOLSET_ENABLE"
  fi
elif [[ -f "$GCC_TOOLSET_ENABLE" ]]; then
  # shellcheck disable=SC1090
  source "$GCC_TOOLSET_ENABLE"
else
  cat <<'MSG' >&2
ERROR: GCC_TOOLSET_ENABLE is set but does not point to a readable enable script.
MSG
  exit 1
fi

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
UV_VENV_CLEAR=1 uv venv --clear --python "$PYTHON_VERSION" "$VENV_DIR"
uv pip install --python "$VENV_DIR/bin/python" --upgrade pip
uv pip install --python "$VENV_DIR/bin/python" "$VLLM_SPEC"

cat <<MSG
llm_launcher bootstrap complete.

Created:
- $VENV_DIR

Installed:
- vllm from spec: $VLLM_SPEC
- CUDA_HOME: $CUDA_HOME
- GCC_TOOLSET_ENABLE: ${GCC_TOOLSET_ENABLE:-<not set>}

Next steps:
- copy .env.example to .env
- adjust MODEL_ID / GPU settings for the cluster
- submit scripts/sbatch-vllm-serve.sh with sbatch
MSG
