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
#   export MODEL_ID=Qwen/Qwen3.6-35B-A3B
#   export VLLM_STARTUP_CMD=./setup-env.sh
#   export VLLM_EXEC=./.venv/bin/vllm
#   export HF_TOKEN=...                 # if required for model download
#   export OPENAI_API_KEY=...           # client auth token
#   export PORT=8000
#   export TENSOR_PARALLEL_SIZE=1       # single-GPU H100-style start
#   export GPU_MEMORY_UTILIZATION=0.92
#   export MAX_MODEL_LEN=32768
#   export MAX_NUM_BATCHED_TOKENS=4096
#   export LANGUAGE_MODEL_ONLY=1        # skip the vision encoder for text-only use

if [[ -n "${SLURM_SUBMIT_DIR:-}" ]]; then
  REPO_ROOT="$SLURM_SUBMIT_DIR"
else
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
if [[ -f "$REPO_ROOT/.env" ]]; then
  # Preserve exported environment overrides across the .env load.
  PRESET_VLLM_WORKDIR="${VLLM_WORKDIR-}"
  PRESET_MODEL_ID="${MODEL_ID-}"
  PRESET_VLLM_STARTUP_CMD="${VLLM_STARTUP_CMD-}"
  PRESET_VLLM_EXEC="${VLLM_EXEC-}"
  PRESET_PORT="${PORT-}"
  PRESET_TENSOR_PARALLEL_SIZE="${TENSOR_PARALLEL_SIZE-}"
  PRESET_GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION-}"
  PRESET_MAX_MODEL_LEN="${MAX_MODEL_LEN-}"
  PRESET_MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS-}"
  PRESET_SWAP_SPACE_GB="${SWAP_SPACE_GB-}"
  PRESET_VLLM_HOST="${VLLM_HOST-}"
  PRESET_TUNNEL_LOGIN_HOST="${TUNNEL_LOGIN_HOST-}"
  PRESET_ENABLE_AUTO_TOOL_CHOICE="${ENABLE_AUTO_TOOL_CHOICE-}"
  PRESET_TOOL_CALL_PARSER="${TOOL_CALL_PARSER-}"
  PRESET_REASONING_PARSER="${REASONING_PARSER-}"
  PRESET_LANGUAGE_MODEL_ONLY="${LANGUAGE_MODEL_ONLY-}"
  PRESET_TORCH_LIB_DIR="${TORCH_LIB_DIR-}"
  # shellcheck disable=SC1090
  source "$REPO_ROOT/.env"
  [[ -n "${PRESET_VLLM_WORKDIR}" ]] && VLLM_WORKDIR="$PRESET_VLLM_WORKDIR"
  [[ -n "${PRESET_MODEL_ID}" ]] && MODEL_ID="$PRESET_MODEL_ID"
  [[ -n "${PRESET_VLLM_STARTUP_CMD}" ]] && VLLM_STARTUP_CMD="$PRESET_VLLM_STARTUP_CMD"
  [[ -n "${PRESET_VLLM_EXEC}" ]] && VLLM_EXEC="$PRESET_VLLM_EXEC"
  [[ -n "${PRESET_PORT}" ]] && PORT="$PRESET_PORT"
  [[ -n "${PRESET_TENSOR_PARALLEL_SIZE}" ]] && TENSOR_PARALLEL_SIZE="$PRESET_TENSOR_PARALLEL_SIZE"
  [[ -n "${PRESET_GPU_MEMORY_UTILIZATION}" ]] && GPU_MEMORY_UTILIZATION="$PRESET_GPU_MEMORY_UTILIZATION"
  [[ -n "${PRESET_MAX_MODEL_LEN}" ]] && MAX_MODEL_LEN="$PRESET_MAX_MODEL_LEN"
  [[ -n "${PRESET_MAX_NUM_BATCHED_TOKENS}" ]] && MAX_NUM_BATCHED_TOKENS="$PRESET_MAX_NUM_BATCHED_TOKENS"
  [[ -n "${PRESET_SWAP_SPACE_GB}" ]] && SWAP_SPACE_GB="$PRESET_SWAP_SPACE_GB"
  [[ -n "${PRESET_VLLM_HOST}" ]] && VLLM_HOST="$PRESET_VLLM_HOST"
  [[ -n "${PRESET_TUNNEL_LOGIN_HOST}" ]] && TUNNEL_LOGIN_HOST="$PRESET_TUNNEL_LOGIN_HOST"
  [[ -n "${PRESET_ENABLE_AUTO_TOOL_CHOICE}" ]] && ENABLE_AUTO_TOOL_CHOICE="$PRESET_ENABLE_AUTO_TOOL_CHOICE"
  [[ -n "${PRESET_TOOL_CALL_PARSER}" ]] && TOOL_CALL_PARSER="$PRESET_TOOL_CALL_PARSER"
  [[ -n "${PRESET_REASONING_PARSER}" ]] && REASONING_PARSER="$PRESET_REASONING_PARSER"
  [[ -n "${PRESET_LANGUAGE_MODEL_ONLY}" ]] && LANGUAGE_MODEL_ONLY="$PRESET_LANGUAGE_MODEL_ONLY"
  [[ -n "${PRESET_TORCH_LIB_DIR}" ]] && TORCH_LIB_DIR="$PRESET_TORCH_LIB_DIR"
fi

VLLM_WORKDIR="${VLLM_WORKDIR:-$REPO_ROOT}"
MODEL_ID="${MODEL_ID:-mistralai/Mistral-Large-3-675B-Instruct-2512-NVFP4}"
VLLM_STARTUP_CMD="${VLLM_STARTUP_CMD:-}"
VLLM_EXEC="${VLLM_EXEC:-./.venv/bin/vllm}"

PORT="${PORT:-8000}"
TENSOR_PARALLEL_SIZE="${TENSOR_PARALLEL_SIZE:-${SLURM_GPUS_ON_NODE:-1}}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.92}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-}"
MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-4096}"
SWAP_SPACE_GB="${SWAP_SPACE_GB:-0}"
VLLM_HOST="${VLLM_HOST:-0.0.0.0}"
TUNNEL_LOGIN_HOST="${TUNNEL_LOGIN_HOST:-<login-host>}"
ENABLE_AUTO_TOOL_CHOICE="${ENABLE_AUTO_TOOL_CHOICE:-1}"
TOOL_CALL_PARSER="${TOOL_CALL_PARSER:-qwen3_xml}"
REASONING_PARSER="${REASONING_PARSER:-qwen3}"
LANGUAGE_MODEL_ONLY="${LANGUAGE_MODEL_ONLY:-0}"
TORCH_LIB_DIR="${TORCH_LIB_DIR:-}"
STARTUP_TIMEOUT_SEC="${STARTUP_TIMEOUT_SEC:-1800}"
HEALTHCHECK_INTERVAL_SEC="${HEALTHCHECK_INTERVAL_SEC:-10}"
READY_CHECK_HOST="${READY_CHECK_HOST:-127.0.0.1}"
READY_CHECK_PATH="${READY_CHECK_PATH:-/v1/models}"

cd "$VLLM_WORKDIR"

if [[ -n "$VLLM_STARTUP_CMD" ]]; then
  eval "$VLLM_STARTUP_CMD"
elif [[ -x ./setup-env.sh ]]; then
  ./setup-env.sh
fi

if [[ -z "$TORCH_LIB_DIR" ]]; then
  for candidate in "$VLLM_WORKDIR"/.venv/lib/python*/site-packages/torch/lib; do
    if [[ -d "$candidate" ]]; then
      TORCH_LIB_DIR="$candidate"
      break
    fi
  done
fi

if [[ -n "$TORCH_LIB_DIR" && -d "$TORCH_LIB_DIR" ]]; then
  export LD_LIBRARY_PATH="$TORCH_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
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

SERVER_HOST="$(hostname -f 2>/dev/null || hostname)"

if [[ ! -x "$VLLM_EXEC" ]] && command -v vllm >/dev/null 2>&1; then
  VLLM_EXEC="$(command -v vllm)"
fi

echo "[$(date -Is)] host: $SERVER_HOST"
echo "[$(date -Is)] workdir: $VLLM_WORKDIR"
echo "[$(date -Is)] model: $MODEL_ID"
echo "[$(date -Is)] port:  $PORT"
echo "[$(date -Is)] tp:    $TENSOR_PARALLEL_SIZE"
echo "[$(date -Is)] mlen:  ${MAX_MODEL_LEN:-<model-default>}"
echo "[$(date -Is)] gmu:   $GPU_MEMORY_UTILIZATION"
echo "[$(date -Is)] mbt:   $MAX_NUM_BATCHED_TOKENS"
echo "[$(date -Is)] swap:  $SWAP_SPACE_GB"
echo "[$(date -Is)] tools: auto=${ENABLE_AUTO_TOOL_CHOICE} parser=${TOOL_CALL_PARSER}"
echo "[$(date -Is)] reason:${REASONING_PARSER:-<disabled>}"
echo "[$(date -Is)] lm-only:${LANGUAGE_MODEL_ONLY}"
echo "[$(date -Is)] exec:  $VLLM_EXEC"
echo "[$(date -Is)] torch: ${TORCH_LIB_DIR:-<not-set>}"
cat <<MSG
[$(date -Is)]
[$(date -Is)] opencode from login node:
export OPENAI_BASE_URL=http://${SERVER_HOST}:${PORT}/v1
export OPENAI_API_KEY='${OPENAI_API_KEY}'
mkdir -p ~/.config/opencode
cat > ~/.config/opencode/opencode.json <<'JSON'
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "phoebe-qwen/${MODEL_ID}",
  "provider": {
    "phoebe-qwen": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "{env:OPENAI_BASE_URL}",
        "apiKey": "{env:OPENAI_API_KEY}"
      },
      "models": {
        "${MODEL_ID}": { "name": "Phoebe Qwen" }
      }
    }
  }
}
JSON
opencode -m 'phoebe-qwen/${MODEL_ID}'
[$(date -Is)]
[$(date -Is)] opencode from laptop (tunnel via login host):
ssh -f -N -o ExitOnForwardFailure=yes -L ${PORT}:${SERVER_HOST}:${PORT} ${USER}@${TUNNEL_LOGIN_HOST}
export OPENAI_BASE_URL=http://127.0.0.1:${PORT}/v1
export OPENAI_API_KEY='${OPENAI_API_KEY}'
opencode -m 'phoebe-qwen/${MODEL_ID}'
MSG

if [[ ! -x "$VLLM_EXEC" ]]; then
  echo "[$(date -Is)] ERROR: vLLM executable not found: $VLLM_EXEC" >&2
  exit 1
fi

log() {
  echo "[$(date -Is)] $*"
}

cleanup() {
  if [[ -n "${VLLM_PID:-}" ]] && kill -0 "$VLLM_PID" 2>/dev/null; then
    kill "$VLLM_PID" 2>/dev/null || true
  fi
}

http_status() {
  local path="$1"
  curl --silent --show-error --output /dev/null \
    --connect-timeout 2 --max-time 5 \
    --write-out '%{http_code}' \
    "http://${READY_CHECK_HOST}:${PORT}${path}" 2>/dev/null || true
}

wait_for_ready() {
  local deadline phase status ready_status
  deadline=$((SECONDS + STARTUP_TIMEOUT_SEC))
  phase="booting"

  if ! command -v curl >/dev/null 2>&1; then
    log "WARNING: curl not found; skipping HTTP readiness checks"
    return 0
  fi

  log "startup-check: probing http://${READY_CHECK_HOST}:${PORT}${READY_CHECK_PATH} every ${HEALTHCHECK_INTERVAL_SEC}s for up to ${STARTUP_TIMEOUT_SEC}s"
  while kill -0 "$VLLM_PID" 2>/dev/null; do
    ready_status="$(http_status "$READY_CHECK_PATH")"
    if [[ "$ready_status" == "200" ]]; then
      log "startup-check: model ready on http://${SERVER_HOST}:${PORT}${READY_CHECK_PATH}"
      return 0
    fi

    status="$(http_status "/health")"
    if [[ "$status" == "200" ]]; then
      if [[ "$phase" != "http-up" ]]; then
        log "startup-check: HTTP server is responding; waiting for model readiness"
        phase="http-up"
      else
        log "startup-check: still loading model; readiness endpoint returned ${ready_status:-<no-response>}"
      fi
    else
      log "startup-check: process is alive; HTTP not ready yet"
    fi

    if (( SECONDS >= deadline )); then
      log "ERROR: startup-check timed out after ${STARTUP_TIMEOUT_SEC}s"
      return 1
    fi

    sleep "$HEALTHCHECK_INTERVAL_SEC"
  done

  log "ERROR: vLLM exited before becoming ready"
  return 1
}

trap cleanup EXIT INT TERM

VLLM_ARGS=(
  --host "$VLLM_HOST"
  --port "$PORT"
  --tensor-parallel-size "$TENSOR_PARALLEL_SIZE"
  --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION"
  --max-num-batched-tokens "$MAX_NUM_BATCHED_TOKENS"
)

if [[ -n "$MAX_MODEL_LEN" ]]; then
  VLLM_ARGS+=(--max-model-len "$MAX_MODEL_LEN")
fi

if [[ -n "$REASONING_PARSER" ]]; then
  VLLM_ARGS+=(--reasoning-parser "$REASONING_PARSER")
fi

if [[ "$ENABLE_AUTO_TOOL_CHOICE" != "0" ]]; then
  VLLM_ARGS+=(--enable-auto-tool-choice --tool-call-parser "$TOOL_CALL_PARSER")
fi

if [[ "$LANGUAGE_MODEL_ONLY" != "0" ]]; then
  VLLM_ARGS+=(--language-model-only)
fi

# Some vLLM builds do not expose --swap-space on `serve`. Only pass it when
# the installed CLI advertises support.
if "$VLLM_EXEC" serve --help 2>&1 | grep -q -- '--swap-space'; then
  VLLM_ARGS+=(--swap-space "$SWAP_SPACE_GB")
fi

"$VLLM_EXEC" serve "$MODEL_ID" "${VLLM_ARGS[@]}" &
VLLM_PID=$!
log "startup-check: spawned vLLM pid=$VLLM_PID"

if ! wait_for_ready; then
  cleanup
  wait "$VLLM_PID" || true
  exit 1
fi

wait "$VLLM_PID"
