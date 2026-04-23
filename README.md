# llm_launcher

A small, self-contained vLLM launcher bundle for Slurm.

## Layout

- `scripts/sbatch-vllm-serve.sh` - the Slurm launcher
- `env.example.1xH100` / `env.example.2xA100` - example runtime overrides
- `install.sh` - optional helper that can create a local environment

## Quick start

1. Copy one of the example env files to `.env` and edit it.
2. Run `./install.sh` to create a local `.venv`, install the `torch` version expected by the pinned `vllm`, then install `vllm`.
3. Submit the script with `sbatch`.

Example:

```bash
cp env.example.1xH100 .env
./install.sh
sbatch -p gpu -N 1 --gres=gpu:1 scripts/sbatch-vllm-serve.sh
```

## Notes

- The launcher does not depend on the `skills/` tree.
- It defaults to the repository root as `VLLM_WORKDIR`.
- If `.env` exists in the repo root, the launcher will source it.
- The launcher now emits startup progress lines and waits for `http://127.0.0.1:$PORT/v1/models` to return `200` before declaring the model ready.
- Startup readiness can be tuned with `.env` overrides: `STARTUP_TIMEOUT_SEC`, `HEALTHCHECK_INTERVAL_SEC`, `READY_CHECK_HOST`, and `READY_CHECK_PATH`.
- `install.sh` expects a recent `python3` on `PATH`, uses `python -m venv`, preinstalls a `torch` version compatible with the selected `vllm`, and then installs `vllm` with `uv pip`.
- Under Slurm, the launcher uses `SLURM_SUBMIT_DIR` so the repo root resolves correctly instead of Slurm's spool directory.
- Model-specific settings belong in `.env`. For `Qwen/Qwen3.6-35B-A3B`, set `MODEL_ID=Qwen/Qwen3.6-35B-A3B`, `TOOL_CALL_PARSER=qwen3_coder`, and `LANGUAGE_MODEL_ONLY=1`.
