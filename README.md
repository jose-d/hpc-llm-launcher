# llm_launcher

A small, self-contained vLLM launcher bundle for Slurm.

## Layout

- `scripts/sbatch-vllm-serve.sh` - the Slurm launcher
- `.env.example` - example runtime overrides
- `install.sh` - optional helper that can create a local environment

## Quick start

1. Copy `.env.example` to `.env` and edit it.
2. Ensure the model workdir exists and contains a usable vLLM environment, or point `VLLM_EXEC` at a system `vllm`.
3. Submit the script with `sbatch`.

Example:

```bash
cp .env.example .env
sbatch -p gpu -N 1 --gres=gpu:1 scripts/sbatch-vllm-serve.sh
```

## Notes

- The launcher does not depend on the `skills/` tree.
- It defaults to the repository root as `VLLM_WORKDIR`.
- If `.env` exists in the repo root, the launcher will source it.
