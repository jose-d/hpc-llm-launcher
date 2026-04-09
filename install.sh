#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$ROOT_DIR/.venv"
cat <<MSG
llm_launcher is now a self-contained launcher bundle.

Next steps:
- copy .env.example to .env
- provide a working vLLM executable via VLLM_EXEC, or create a repo-local .venv/bin/vllm
- submit scripts/sbatch-vllm-serve.sh with sbatch
MSG
