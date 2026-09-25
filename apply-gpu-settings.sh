#!/usr/bin/env bash
set -u

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
NVIDIA_SMI="/usr/bin/nvidia-smi"
SETTINGS_FILE="$BASE_DIR/gpu-settings.conf"

if [[ ! -x "$NVIDIA_SMI" ]]; then
    echo "nvidia-smi not found; skipping GPU tuning" >&2
    exit 0
fi
if [[ ! -r "$SETTINGS_FILE" ]]; then
    echo "GPU settings not configured; skipping GPU tuning" >&2
    exit 0
fi

# shellcheck source=/dev/null
source "$SETTINGS_FILE"
if [[ "${GPU_SETTINGS_ENABLED:-1}" != 1 ]]; then
    exit 0
fi

if ! declare -p GPU_SETTINGS >/dev/null 2>&1; then
    echo "GPU_SETTINGS is missing in $SETTINGS_FILE; skipping GPU tuning" >&2
    exit 0
fi

run_nvidia_smi() {
    if [[ "$EUID" -eq 0 ]]; then
        "$NVIDIA_SMI" "$@"
    else
        sudo -n "$NVIDIA_SMI" "$@"
    fi
}

for setting in "${GPU_SETTINGS[@]}"; do
    read -r gpu power_limit graphics_clock graphics_offset memory_clock <<< "$setting"
    [[ "$gpu" =~ ^[0-9]+$ ]] || continue

    if ! run_nvidia_smi -i "$gpu" -pm 1 >/dev/null 2>&1; then
        echo "GPU $gpu is not available or power management could not be enabled; skipping" >&2
        continue
    fi

    run_nvidia_smi -i "$gpu" -pl "$power_limit" >/dev/null 2>&1 || true
    run_nvidia_smi -i "$gpu" -lgc "$graphics_clock" >/dev/null 2>&1 || true
    run_nvidia_smi -i "$gpu" -gsc "$graphics_offset" >/dev/null 2>&1 || true
    run_nvidia_smi -i "$gpu" -lmc "$memory_clock" >/dev/null 2>&1 || true
done
