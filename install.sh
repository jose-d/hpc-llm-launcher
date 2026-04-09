#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${VENV_DIR:-$ROOT_DIR/.venv}"
VLLM_SPEC="${VLLM_SPEC:-vllm}"
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
PYTHON_BIN="${PYTHON_BIN:-}"
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

check_step "Create venv"
uv python install "$PYTHON_VERSION" >/dev/null 2>&1 || true
UV_VENV_CLEAR=1 uv venv --clear --python "$PYTHON_BIN" "$VENV_DIR"
status_ok

check_step "Upgrade pip"
uv pip install --python "$VENV_DIR/bin/python" --upgrade pip
status_ok

check_step "Install torch"
uv pip install --python "$VENV_DIR/bin/python" --torch-backend=auto torch
status_ok

check_step "Install setuptools_scm"
uv pip install --python "$VENV_DIR/bin/python" setuptools_scm
status_ok

check_step "Install vllm"
uv pip install --python "$VENV_DIR/bin/python" --torch-backend=auto --no-build-isolation "$VLLM_SPEC"
status_ok

cat <<MSG
llm_launcher bootstrap complete.

Created:
- $VENV_DIR

Installed:
- vllm from spec: $VLLM_SPEC
- PYTHON_BIN: $PYTHON_BIN

Next steps:
- copy .env.example to .env
- adjust MODEL_ID / GPU settings for the cluster
- submit scripts/sbatch-vllm-serve.sh with sbatch
MSG
