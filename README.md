# llm_launcher

A small, self-contained vLLM launcher bundle for Slurm.

## Layout

- `scripts/sbatch-vllm-serve.sh` - the Slurm launcher
- `.env.example` - example runtime overrides
- `install.sh` - optional helper that can create a local environment

## Quick start

1. Copy `.env.example` to `.env` and edit it.
2. Run `./install.sh` to create a local `.venv` with `vllm` installed via `uv`.
3. Submit the script with `sbatch`.

Example:

```bash
cp .env.example .env
./install.sh
sbatch -p gpu -N 1 --gres=gpu:1 scripts/sbatch-vllm-serve.sh
```

## Notes

- The launcher does not depend on the `skills/` tree.
- It defaults to the repository root as `VLLM_WORKDIR`.
- If `.env` exists in the repo root, the launcher will source it.
- `install.sh` expects `uv` on `PATH` and installs `vllm` into `.venv`.
- Under Slurm, the launcher uses `SLURM_SUBMIT_DIR` so the repo root resolves correctly instead of Slurm's spool directory.
