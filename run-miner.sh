#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CHECK_CONFIG=0
if [[ "${1:-}" == "--check-config" ]]; then
    CHECK_CONFIG=1
    shift
fi
if (($# > 1)); then
    echo "Использование: $0 [--check-config [ПРОФИЛЬ]]" >&2
    exit 2
fi

if (($# == 1)); then
    PROFILE_NAME="$1"
elif [[ -s "$BASE_DIR/current-profile" ]]; then
    PROFILE_NAME="$(tr -d '[:space:]' < "$BASE_DIR/current-profile")"
else
    PROFILE_NAME="pearlhash"
fi

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
: "${MINER_PASS:?MINER_PASS is required in $PROFILE_FILE}"

wallet_line="$(awk '/^[[:space:]]*MINER_USER[[:space:]]*=/{print NR; exit}' "$PROFILE_FILE")"
lower_user="${MINER_USER:-}"
lower_user="${lower_user,,}"
if [[ -z "${lower_user//[[:space:]]/}" ]] ||
   [[ "$lower_user" =~ (your.*(wallet|address|login|user)|change.?me|replace.?me|insert.*(wallet|address|login|user)) ]]; then
    echo "Ошибка: в профиле '$PROFILE_NAME' не указан адрес кошелька или логин пула." >&2
    if [[ -n "$wallet_line" ]]; then
        printf 'Укажите его в строке MINER_USER файла: %s:%s\n' "$PROFILE_FILE" "$wallet_line" >&2
    else
        printf 'Добавьте MINER_USER="ВАШ_АДРЕС_ИЛИ_ЛОГИН" в файл: %s\n' "$PROFILE_FILE" >&2
    fi
    printf 'Шаблон профиля: %s\n' "$BASE_DIR/profiles/$PROFILE_NAME.example.conf" >&2
    printf 'Инструкция: %s (раздел «Установка на новую Ubuntu»).\n' "$BASE_DIR/README.md" >&2
    exit 2
fi

MINER_USER="${MINER_USER//\{RIG_NAME\}/$RIG_NAME}"
WORKER="${WORKER:-}"
WORKER="${WORKER//\{RIG_NAME\}/$RIG_NAME}"

if (( CHECK_CONFIG )); then
    exit 0
fi

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
