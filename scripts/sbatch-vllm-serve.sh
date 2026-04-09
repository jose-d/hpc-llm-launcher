#!/usr/bin/env bash
set -euo pipefail

# Slurm template: serve a model with vLLM.
#
# This script is intentionally cluster-agnostic. Override the environment to fit
# the local cluster, GPU type, model, and launch layout.
#
# Usage examples:
#   sbatch -p gpu -N 1 --gres=gpu:8 -t 24:00:00 sbatch-vllm-serve.sh
#   sbatch -p h100 -N 1 --gres=gpu:1 -t 08:00:00 sbatch-vllm-serve.sh
#
# Common overrides:
#   export VLLM_WORKDIR=/home/jose/projects/vllm_mistral
#   export MODEL_ID=mistralai/Devstral-2-123B-Instruct-2512
#   export MODEL_ID=Qwen/Qwen3-30B-A3B-Thinking-2507
#   export VLLM_STARTUP_CMD=./setup-env.sh
#   export VLLM_EXEC=./.venv/bin/vllm
#   export HF_TOKEN=...                 # if required for model download
#   export OPENAI_API_KEY=...           # client auth token
#   export PORT=8000
#   export TENSOR_PARALLEL_SIZE=1       # single-GPU H100-style start
#   export GPU_MEMORY_UTILIZATION=0.92
#   export MAX_MODEL_LEN=32768
#   export MAX_NUM_BATCHED_TOKENS=4096
#   export SWAP_SPACE_GB=0

if [[ -n "${SLURM_SUBMIT_DIR:-}" ]]; then
  REPO_ROOT="$SLURM_SUBMIT_DIR"
else
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
if [[ -f "$REPO_ROOT/.env" ]]; then
  # shellcheck disable=SC1090
  source "$REPO_ROOT/.env"
fi

VLLM_WORKDIR="${VLLM_WORKDIR:-$REPO_ROOT}"
MODEL_ID="${MODEL_ID:-mistralai/Mistral-Large-3-675B-Instruct-2512-NVFP4}"
VLLM_STARTUP_CMD="${VLLM_STARTUP_CMD:-}"
VLLM_EXEC="${VLLM_EXEC:-./.venv/bin/vllm}"

PORT="${PORT:-8000}"
TENSOR_PARALLEL_SIZE="${TENSOR_PARALLEL_SIZE:-${SLURM_GPUS_ON_NODE:-1}}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.92}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-32768}"
MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-4096}"
SWAP_SPACE_GB="${SWAP_SPACE_GB:-0}"
VLLM_HOST="${VLLM_HOST:-0.0.0.0}"

cd "$VLLM_WORKDIR"

if [[ -n "$VLLM_STARTUP_CMD" ]]; then
  eval "$VLLM_STARTUP_CMD"
elif [[ -x ./setup-env.sh ]]; then
  ./setup-env.sh
fi

export HF_HOME="${HF_HOME:-/tmp/$USER/hf-cache}"
mkdir -p "$HF_HOME"

if [[ -n "${HF_TOKEN:-}" ]]; then
  export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"
fi

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  if [[ -f "${OPENAI_API_KEY_FILE:-$VLLM_WORKDIR/.api-key}" ]]; then
    export OPENAI_API_KEY="$(tr -d '\r\n' < "${OPENAI_API_KEY_FILE:-$VLLM_WORKDIR/.api-key}")"
  else
    export OPENAI_API_KEY="vllm-internal-$(date +%s)"
  fi
fi

if [[ ! -x "$VLLM_EXEC" ]] && command -v vllm >/dev/null 2>&1; then
  VLLM_EXEC="$(command -v vllm)"
fi

echo "[$(date -Is)] host: $(hostname -f 2>/dev/null || hostname)"
echo "[$(date -Is)] workdir: $VLLM_WORKDIR"
echo "[$(date -Is)] model: $MODEL_ID"
echo "[$(date -Is)] port:  $PORT"
echo "[$(date -Is)] tp:    $TENSOR_PARALLEL_SIZE"
echo "[$(date -Is)] mlen:  $MAX_MODEL_LEN"
echo "[$(date -Is)] gmu:   $GPU_MEMORY_UTILIZATION"
echo "[$(date -Is)] mbt:   $MAX_NUM_BATCHED_TOKENS"
echo "[$(date -Is)] swap:  ${SWAP_SPACE_GB}G"
echo "[$(date -Is)] exec:  $VLLM_EXEC"

if [[ ! -x "$VLLM_EXEC" ]]; then
  echo "[$(date -Is)] ERROR: vLLM executable not found: $VLLM_EXEC" >&2
  exit 1
fi

exec "$VLLM_EXEC" serve "$MODEL_ID" \
  --host "$VLLM_HOST" \
  --port "$PORT" \
  --tensor-parallel-size "$TENSOR_PARALLEL_SIZE" \
  --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" \
  --max-model-len "$MAX_MODEL_LEN" \
  --max-num-batched-tokens "$MAX_NUM_BATCHED_TOKENS" \
  --swap-space "$SWAP_SPACE_GB"
