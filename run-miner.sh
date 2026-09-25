#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROFILE_NAME="$(tr -d '[:space:]' < "$BASE_DIR/current-profile")"

if [[ ! "$PROFILE_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "Invalid profile name: $PROFILE_NAME" >&2
    exit 2
fi

PROFILE_FILE="$BASE_DIR/profiles/$PROFILE_NAME.conf"
if [[ ! -r "$PROFILE_FILE" ]]; then
    echo "Profile not found: $PROFILE_FILE" >&2
    exit 2
fi

if [[ -s "$BASE_DIR/rig-name" ]]; then
    RIG_NAME="$(tr -d '\r\n' < "$BASE_DIR/rig-name")"
else
    RIG_NAME="$(hostname -s | tr '[:upper:]' '[:lower:]')"
    RIG_NAME="${RIG_NAME//[^a-z0-9._-]/-}"
fi
if [[ ! "$RIG_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$ ]]; then
    echo "Invalid rig name in $BASE_DIR/rig-name: $RIG_NAME" >&2
    exit 2
fi

# Profiles contain assignments only; wallet values live in ignored *.conf
# files, while the tracked examples use a {RIG_NAME} substitution token.
# shellcheck source=/dev/null
source "$PROFILE_FILE"

: "${ALGO:?ALGO is required in $PROFILE_FILE}"
: "${POOL_URL:?POOL_URL is required in $PROFILE_FILE}"
: "${MINER_USER:?MINER_USER is required in $PROFILE_FILE}"
: "${MINER_PASS:?MINER_PASS is required in $PROFILE_FILE}"

MINER_USER="${MINER_USER//\{RIG_NAME\}/$RIG_NAME}"
WORKER="${WORKER:-}"
WORKER="${WORKER//\{RIG_NAME\}/$RIG_NAME}"

MINER_BIN="$BASE_DIR/wildrig-multi"
if [[ ! -x "$MINER_BIN" ]]; then
    echo "Miner binary is not executable: $MINER_BIN" >&2
    exit 1
fi

args=(--algo "$ALGO" --url "$POOL_URL" --user "$MINER_USER" --pass "$MINER_PASS")
if [[ -n "$WORKER" ]]; then
    args+=(--worker "$WORKER")
fi
if [[ -n "${API_PORT:-}" ]]; then
    args+=(--api-port "$API_PORT")
fi
if declare -p MINER_EXTRA_ARGS >/dev/null 2>&1; then
    args+=("${MINER_EXTRA_ARGS[@]}")
fi

exec "$MINER_BIN" "${args[@]}"
