#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${VENV_DIR:-$ROOT_DIR/.venv}"
VLLM_VERSION="${VLLM_VERSION:-0.19.0}"
VLLM_SPEC="${VLLM_SPEC:-vllm==${VLLM_VERSION}}"
TORCH_SPEC="${TORCH_SPEC:-torch==2.10.0}"
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
PYTHON_BIN="${PYTHON_BIN:-}"
UV_BIN="${UV_BIN:-}"
UV_INDEX_STRATEGY="${UV_INDEX_STRATEGY:-unsafe-best-match}"
VLLM_EXTRA_INDEX_URL="${VLLM_EXTRA_INDEX_URL:-https://wheels.vllm.ai/${VLLM_VERSION}/cu130}"
PYTORCH_EXTRA_INDEX_URL="${PYTORCH_EXTRA_INDEX_URL:-https://download.pytorch.org/whl/cu130}"
CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
BOOTSTRAP_BUILD_TOOLS="${BOOTSTRAP_BUILD_TOOLS:-1}"
UV_NO_BUILD_ISOLATION="${UV_NO_BUILD_ISOLATION:-1}"
PIP_CACHE_DIR="${PIP_CACHE_DIR:-$ROOT_DIR/.cache/pip}"
PIP_DISABLE_PIP_VERSION_CHECK="${PIP_DISABLE_PIP_VERSION_CHECK:-1}"
PIP_RETRIES="${PIP_RETRIES:-1}"
PIP_TIMEOUT="${PIP_TIMEOUT:-15}"
MIN_GCC_MAJOR_VERSION="${MIN_GCC_MAJOR_VERSION:-15}"
RED="\033[31m"
GREEN="\033[32m"
RESET="\033[0m"
DO_CLEANUP=0

for arg in "$@"; do
  case "$arg" in
    --cleanup)
      DO_CLEANUP=1
      ;;
    *)
      cat <<MSG >&2
ERROR: unknown argument: $arg
Use --cleanup to remove the local .venv.
MSG
      exit 1
      ;;
  esac
done

check_step() {
  printf 'Checking %s... ' "$1"
}

status_ok() {
  printf '%b[ok]%b\n' "$GREEN" "$RESET"
}

status_fail() {
  printf '%b[fail]%b\n' "$RED" "$RESET"
}

die() {
  status_fail >&2
  cat >&2
  exit 1
}

if (( DO_CLEANUP )); then
  check_step "Remove venv"
  if [[ -d "$VENV_DIR" ]]; then
    rm -rf "$VENV_DIR"
    status_ok
    echo "Removed: $VENV_DIR"
  else
    status_ok
    echo "No venv present at: $VENV_DIR"
  fi
  exit 0
fi

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

detect_uv_bin() {
  if [[ -n "$UV_BIN" ]]; then
    if command -v "$UV_BIN" >/dev/null 2>&1; then
      printf '%s\n' "$(command -v "$UV_BIN")"
      return 0
    fi
    return 1
  fi

  if command -v uv >/dev/null 2>&1; then
    printf '%s\n' "$(command -v uv)"
    return 0
  fi

  return 1
}

detect_glibc_version() {
  local libc_version
  libc_version="$(getconf GNU_LIBC_VERSION 2>/dev/null || true)"
  libc_version="${libc_version#glibc }"
  printf '%s\n' "$libc_version"
}

version_lt() {
  [[ "$1" != "$2" ]] && [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" == "$1" ]]
}

detect_ninja_bin() {
  if command -v ninja >/dev/null 2>&1; then
    printf '%s\n' "$(command -v ninja)"
    return 0
  fi

  return 1
}

detect_c_compiler() {
  if [[ -n "${CC:-}" ]]; then
    if command -v "$CC" >/dev/null 2>&1; then
      printf '%s\n' "$(command -v "$CC")"
      return 0
    fi
    return 1
  fi

  if command -v gcc >/dev/null 2>&1; then
    printf '%s\n' "$(command -v gcc)"
    return 0
  fi

  return 1
}

detect_cxx_compiler() {
  if [[ -n "${CXX:-}" ]]; then
    if command -v "$CXX" >/dev/null 2>&1; then
      printf '%s\n' "$(command -v "$CXX")"
      return 0
    fi
    return 1
  fi

  if command -v g++ >/dev/null 2>&1; then
    printf '%s\n' "$(command -v g++)"
    return 0
  fi

  return 1
}

detect_gcc_major_version() {
  local compiler="$1"
  local version

  version="$("$compiler" -dumpfullversion -dumpversion 2>/dev/null || true)"
  version="${version%%.*}"
  printf '%s\n' "$version"
}

sanitize_path() {
  local old_path="$1"
  local part
  local sanitized=""

  IFS=':' read -r -a path_parts <<< "$old_path"
  for part in "${path_parts[@]}"; do
    [[ -z "$part" ]] && continue
    case "$part" in
      */.cache/uv/builds-v0/.tmp*/bin)
        continue
        ;;
    esac
    if [[ -z "$sanitized" ]]; then
      sanitized="$part"
    else
      sanitized="${sanitized}:$part"
    fi
  done

  printf '%s\n' "$sanitized"
}

recommended_torch_spec() {
  case "$1" in
    0.19.*)
      printf '%s\n' "torch==2.10.0"
      ;;
    *)
      return 1
      ;;
  esac
}

check_step "Python interpreter"
if ! PYTHON_BIN="$(detect_python_bin)"; then
  die <<'MSG'
ERROR: no usable python3 interpreter was found on PATH.
Install Python 3.11+ or set PYTHON_BIN explicitly.
MSG
fi

PYTHON_MAJOR_MINOR="$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
case "$PYTHON_MAJOR_MINOR" in
  3.11|3.12|3.13)
    PYTHON_VERSION="$PYTHON_MAJOR_MINOR"
    ;;
  *)
    die <<MSG
ERROR: unsupported Python version detected: $PYTHON_MAJOR_MINOR
Install Python 3.11, 3.12, or 3.13, or set PYTHON_BIN explicitly.
MSG
    ;;
esac
status_ok
echo "Using Python: $PYTHON_BIN ($PYTHON_VERSION)"

check_step "uv"
if ! UV_BIN="$(detect_uv_bin)"; then
  die <<'MSG'
ERROR: uv was not found on PATH.
Install uv or set UV_BIN explicitly.
MSG
fi
status_ok
echo "Using uv: $UV_BIN"

check_step "GCC toolchain"
if ! GCC_BIN="$(detect_c_compiler)"; then
  die <<'MSG'
ERROR: no usable gcc compiler was found on PATH.
Source your toolchain first, for example:
  source /opt/rh/gcc-toolset-15/enable
or set CC explicitly.
MSG
fi

if ! GXX_BIN="$(detect_cxx_compiler)"; then
  die <<'MSG'
ERROR: no usable g++ compiler was found on PATH.
Source your toolchain first, for example:
  source /opt/rh/gcc-toolset-15/enable
or set CXX explicitly.
MSG
fi

export CC="$GCC_BIN"
export CXX="$GXX_BIN"
export CUDAHOSTCXX="$CXX"
export PATH="$(dirname "$CC"):$PATH"

GCC_MAJOR_VERSION="$(detect_gcc_major_version "$CC")"
if [[ -z "$GCC_MAJOR_VERSION" || ! "$GCC_MAJOR_VERSION" =~ ^[0-9]+$ ]]; then
  die <<MSG
ERROR: could not determine GCC version from: $CC
Set CC/CXX explicitly or source a GCC toolset first, for example:
  source /opt/rh/gcc-toolset-15/enable
MSG
fi

if (( GCC_MAJOR_VERSION < MIN_GCC_MAJOR_VERSION )); then
  die <<MSG
ERROR: GCC $GCC_MAJOR_VERSION is too old; require GCC >= $MIN_GCC_MAJOR_VERSION
Active compiler: $CC
Source a newer toolchain first, for example:
  source /opt/rh/gcc-toolset-15/enable
MSG
fi

status_ok
echo "Using CC: $CC"
echo "Using CXX: $CXX"
echo "Using GCC major version: $GCC_MAJOR_VERSION"

mkdir -p "$ROOT_DIR"
mkdir -p "$PIP_CACHE_DIR"
export PIP_CACHE_DIR
export PIP_DISABLE_PIP_VERSION_CHECK
export PIP_RETRIES
export PIP_TIMEOUT
if [[ -x "$CUDA_HOME/bin/nvcc" ]]; then
  export CUDA_HOME
  export PATH="$CUDA_HOME/bin:$PATH"
fi

check_step "Create venv"
rm -rf "$VENV_DIR"
"$PYTHON_BIN" -m venv "$VENV_DIR"
status_ok

GLIBC_VERSION="$(detect_glibc_version)"
if [[ -n "$GLIBC_VERSION" ]] && version_lt "$GLIBC_VERSION" "2.35"; then
  echo "glibc $GLIBC_VERSION detected; vLLM wheel index requires manylinux_2_35, so a source build may be needed."
fi

if RECOMMENDED_TORCH_SPEC="$(recommended_torch_spec "$VLLM_VERSION" 2>/dev/null)"; then
  if [[ "$TORCH_SPEC" != "$RECOMMENDED_TORCH_SPEC" ]]; then
    die <<MSG
ERROR: $TORCH_SPEC is not compatible with the default vLLM source build for VLLM_VERSION=$VLLM_VERSION
Use:
  TORCH_SPEC='$RECOMMENDED_TORCH_SPEC'

The current vLLM $VLLM_VERSION sdist expects $RECOMMENDED_TORCH_SPEC at build time.
Override both TORCH_SPEC and VLLM_SPEC explicitly if you intentionally want a different pair.
MSG
  fi
fi

if (( BOOTSTRAP_BUILD_TOOLS )); then
  check_step "Install build tools"
  if ! "$UV_BIN" pip install \
    --python "$VENV_DIR/bin/python" \
    ninja \
    cmake \
    packaging \
    setuptools_scm; then
    die <<MSG
ERROR: failed to install source-build helpers into $VENV_DIR

Current install settings:
- BOOTSTRAP_BUILD_TOOLS=$BOOTSTRAP_BUILD_TOOLS
- CUDA_HOME=$CUDA_HOME
MSG
  fi
  status_ok
fi

if NINJA_BIN="$(detect_ninja_bin)"; then
  PATH="$(sanitize_path "$PATH")"
  export PATH="$(dirname "$NINJA_BIN"):$PATH"
  export CMAKE_MAKE_PROGRAM="$NINJA_BIN"
  export NVCC_PREPEND_FLAGS="${NVCC_PREPEND_FLAGS:-} -ccbin=$CXX"
  export CMAKE_ARGS="${CMAKE_ARGS:-} -DCMAKE_MAKE_PROGRAM=$NINJA_BIN -DCMAKE_CUDA_HOST_COMPILER=$CXX -DCMAKE_CUDA_FLAGS=--compiler-bindir=$CXX"
fi

check_step "Install torch"
if ! "$UV_BIN" pip install \
  --python "$VENV_DIR/bin/python" \
  "$TORCH_SPEC" \
  --extra-index-url "$PYTORCH_EXTRA_INDEX_URL" \
  --index-strategy "$UV_INDEX_STRATEGY"; then
  die <<MSG
ERROR: failed to install $TORCH_SPEC into $VENV_DIR

Current install settings:
- TORCH_SPEC=$TORCH_SPEC
- PYTORCH_EXTRA_INDEX_URL=$PYTORCH_EXTRA_INDEX_URL
- UV_INDEX_STRATEGY=$UV_INDEX_STRATEGY
MSG
fi
status_ok

check_step "Install vllm"
if ! "$UV_BIN" pip install \
  --python "$VENV_DIR/bin/python" \
  $( (( UV_NO_BUILD_ISOLATION )) && printf '%s ' --no-build-isolation ) \
  "$VLLM_SPEC" \
  --extra-index-url "$VLLM_EXTRA_INDEX_URL" \
  --extra-index-url "$PYTORCH_EXTRA_INDEX_URL" \
  --index-strategy "$UV_INDEX_STRATEGY"; then
  die <<MSG
ERROR: failed to install $VLLM_SPEC into $VENV_DIR

Common causes:
- no network access to one of the required package indexes
- cluster login nodes block outbound HTTPS
- the requested spec has no compatible wheel for Python $PYTHON_VERSION
- the CUDA wheel indexes do not match the local driver/runtime expectation

Current install settings:
- TORCH_SPEC=$TORCH_SPEC
- VLLM_SPEC=$VLLM_SPEC
- VLLM_EXTRA_INDEX_URL=$VLLM_EXTRA_INDEX_URL
- PYTORCH_EXTRA_INDEX_URL=$PYTORCH_EXTRA_INDEX_URL
- UV_INDEX_STRATEGY=$UV_INDEX_STRATEGY
- UV_NO_BUILD_ISOLATION=$UV_NO_BUILD_ISOLATION

If you need a different package build or wheel source, rerun with overrides, for example:
  VLLM_VERSION=0.19.0 ./install.sh
  TORCH_SPEC='torch==2.4.0' ./install.sh
  VLLM_SPEC='vllm==0.19.0' ./install.sh
  VLLM_EXTRA_INDEX_URL=https://wheels.vllm.ai/<version>/<cuda> ./install.sh
MSG
fi
status_ok

cat <<MSG
llm_launcher bootstrap complete.

Created:
- $VENV_DIR

Installed:
- torch from spec: $TORCH_SPEC
- vllm from spec: $VLLM_SPEC
- vLLM wheels index: $VLLM_EXTRA_INDEX_URL
- PyTorch wheels index: $PYTORCH_EXTRA_INDEX_URL
- PYTHON_BIN: $PYTHON_BIN

Next steps:
- copy .env.example to .env
- adjust MODEL_ID / GPU settings for the cluster
- submit scripts/sbatch-vllm-serve.sh with sbatch
MSG
