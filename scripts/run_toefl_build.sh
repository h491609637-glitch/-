#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$ROOT_DIR/.venv"
PYTHON_BIN="${PYTHON_BIN:-python3}"

echo "[run_toefl_build] project root: $ROOT_DIR"
cd "$ROOT_DIR"

if [[ ! -d "$VENV_DIR" ]]; then
  echo "[run_toefl_build] creating virtualenv: $VENV_DIR"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

if ! python -c "import pandas, requests" >/dev/null 2>&1; then
  echo "[run_toefl_build] installing dependencies: pandas requests"
  python -m pip install --upgrade pip
  python -m pip install pandas requests
fi

download_flag=1
declare -a passthrough_args=()
for arg in "$@"; do
  if [[ "$arg" == "--no-download" ]]; then
    download_flag=0
    continue
  fi
  passthrough_args+=("$arg")
done

declare -a cmd=("python" "build_toefl_vocab.py")
if [[ $download_flag -eq 1 ]]; then
  cmd+=("--download")
fi
cmd+=("--output-dir" "./output")
cmd+=("${passthrough_args[@]}")

echo "[run_toefl_build] running: ${cmd[*]}"
"${cmd[@]}"
echo "[run_toefl_build] done. output in $ROOT_DIR/output"
