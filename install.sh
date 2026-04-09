#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${VENV_DIR:-$ROOT_DIR/.venv}"
VLLM_SPEC="${VLLM_SPEC:-vllm}"
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"

if ! command -v uv >/dev/null 2>&1; then
  cat <<'MSG' >&2
ERROR: uv is not installed or not on PATH.
Install uv first, then rerun this script.
MSG
  exit 1
fi

mkdir -p "$ROOT_DIR"

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

Next steps:
- copy .env.example to .env
- adjust MODEL_ID / GPU settings for the cluster
- submit scripts/sbatch-vllm-serve.sh with sbatch
MSG
