#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${VENV_DIR:-$ROOT_DIR/.venv}"
VLLM_SPEC="${VLLM_SPEC:-vllm}"
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
PYTHON_BIN="${PYTHON_BIN:-}"
CUDA_HOME="${CUDA_HOME:-}"
GCC_TOOLSET_ENABLE="${GCC_TOOLSET_ENABLE:-}"
RED="\033[31m"
GREEN="\033[32m"
RESET="\033[0m"

check_step() {
  printf 'Checking %s... ' "$1"
}

status_ok() {
  printf '%b[ok]%b\n' "$GREEN" "$RESET"
}

status_fail() {
  printf '%b[fail]%b\n' "$RED" "$RESET"
}

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

detect_python_bin() {
  if [[ -n "$PYTHON_BIN" ]]; then
    if command -v "$PYTHON_BIN" >/dev/null 2>&1; then
      printf '%s\n' "$(command -v "$PYTHON_BIN")"
      return 0
    fi
    return 1
  fi

  local candidate
  for candidate in python3.13 python3.12 python3.11 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$(command -v "$candidate")"
      return 0
    fi
  done

  return 1
}

check_step "uv"
if ! command -v uv >/dev/null 2>&1; then
  status_fail >&2
  cat <<'MSG' >&2
ERROR: uv is not installed or not on PATH.
Install uv first, then rerun this script.
MSG
  exit 1
fi
status_ok

check_step "ninja"
if ! command -v ninja >/dev/null 2>&1; then
  status_fail >&2
  cat <<'MSG' >&2
ERROR: ninja is not installed or not on PATH.
Install ninja before rerunning this script.
MSG
  exit 1
fi
status_ok

check_step "Python interpreter"
if ! PYTHON_BIN="$(detect_python_bin)"; then
  status_fail >&2
  cat <<'MSG' >&2
ERROR: no usable python3 interpreter was found on PATH.
Install Python 3.11+ or set PYTHON_BIN explicitly.
MSG
  exit 1
fi

PYTHON_MAJOR_MINOR="$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
case "$PYTHON_MAJOR_MINOR" in
  3.11|3.12|3.13)
    PYTHON_VERSION="$PYTHON_MAJOR_MINOR"
    ;;
  *)
    status_fail >&2
    cat <<MSG >&2
ERROR: unsupported Python version detected: $PYTHON_MAJOR_MINOR
Install Python 3.11, 3.12, or 3.13, or set PYTHON_BIN explicitly.
MSG
    exit 1
    ;;
esac
status_ok
echo "Using Python: $PYTHON_BIN ($PYTHON_VERSION)"

mkdir -p "$ROOT_DIR"

check_step "GCC toolset"
if [[ -z "$GCC_TOOLSET_ENABLE" ]]; then
  if GCC_TOOLSET_ENABLE="$(detect_gcc_toolset_enable)"; then
    # shellcheck disable=SC1090
    source "$GCC_TOOLSET_ENABLE"
  fi
elif [[ -f "$GCC_TOOLSET_ENABLE" ]]; then
  # shellcheck disable=SC1090
  source "$GCC_TOOLSET_ENABLE"
else
  status_fail >&2
  cat <<'MSG' >&2
ERROR: GCC_TOOLSET_ENABLE is set but does not point to a readable enable script.
MSG
  exit 1
fi
status_ok
echo "Using compiler toolset: ${GCC_TOOLSET_ENABLE:-<not set>}"

if command -v gcc >/dev/null 2>&1; then
  echo "gcc: $(command -v gcc)"
  gcc --version | sed -n '1p'
fi
if command -v g++ >/dev/null 2>&1; then
  echo "g++: $(command -v g++)"
  g++ --version | sed -n '1p'
fi

check_step "CUDA toolkit"
if [[ -z "$CUDA_HOME" ]]; then
  if CUDA_HOME="$(detect_cuda_home)"; then
    export CUDA_HOME
  fi
fi

if [[ -z "${CUDA_HOME:-}" ]]; then
  status_fail >&2
  cat <<'MSG' >&2
ERROR: CUDA_HOME is not set and CUDA could not be autodetected.
Install or load a CUDA toolkit before running this script, or set CUDA_HOME explicitly.
MSG
  exit 1
fi
status_ok
echo "Using CUDA_HOME: $CUDA_HOME"

export CUDA_HOME

check_step "Create venv"
uv python install "$PYTHON_VERSION" >/dev/null 2>&1 || true
UV_VENV_CLEAR=1 uv venv --clear --python "$PYTHON_BIN" "$VENV_DIR"
status_ok

check_step "Upgrade pip"
uv pip install --python "$VENV_DIR/bin/python" --upgrade pip
status_ok

check_step "Install build deps"
uv pip install --python "$VENV_DIR/bin/python" ninja numpy
status_ok

check_step "Install vllm"
uv pip install --python "$VENV_DIR/bin/python" "$VLLM_SPEC"
status_ok

cat <<MSG
llm_launcher bootstrap complete.

Created:
- $VENV_DIR

Installed:
- vllm from spec: $VLLM_SPEC
- PYTHON_BIN: $PYTHON_BIN
- CUDA_HOME: $CUDA_HOME
- GCC_TOOLSET_ENABLE: ${GCC_TOOLSET_ENABLE:-<not set>}

Next steps:
- copy .env.example to .env
- adjust MODEL_ID / GPU settings for the cluster
- submit scripts/sbatch-vllm-serve.sh with sbatch
MSG
